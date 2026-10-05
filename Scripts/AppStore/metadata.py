#!/usr/bin/env python3
"""Plan/apply scoped App Store Connect metadata; never uploads builds or submits releases."""
import argparse
import base64
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'}
LIMITS = {'name': 30, 'subtitle': 30, 'description': 4000, 'promotionalText': 170}
INFO_FIELDS = {'name', 'subtitle', 'privacyPolicyUrl', 'privacyPolicyText'}
VERSION_FIELDS = {'description', 'keywords', 'promotionalText', 'supportUrl', 'marketingUrl'}


class MetadataError(Exception):
    pass


def load_metadata(path):
    data = json.loads(Path(path).read_text())
    if (data['appId'], data['bundleId'], data['platform']) != (
        '6819134482', 'com.kridsdale.JellyfinPlayer', 'TV_OS'
    ):
        raise MetadataError('Metadata must target the confirmed KidsJellyFin tvOS registration.')
    for group, allowed in [('appInfo', INFO_FIELDS), ('version', VERSION_FIELDS)]:
        if set(data[group]) - allowed:
            raise MetadataError('Unsupported metadata field.')
        for field, value in data[group].items():
            if not isinstance(value, str) or not value.strip():
                raise MetadataError(f'{field} must be nonempty text.')
            if field in LIMITS and len(value) > LIMITS[field]:
                raise MetadataError(f'{field} exceeds Apple character limit.')
            if field == 'keywords' and len(value.encode('utf-8')) > 100:
                raise MetadataError('Keywords exceed 100 UTF-8 bytes.')
            if field.endswith(('Url', 'URL')) and not value.startswith('https://'):
                raise MetadataError('Public metadata URLs must use HTTPS.')
    if data.get('categoryId') != 'ENTERTAINMENT':
        raise MetadataError('Unexpected category.')
    return data


def token(key_file, key_id, issuer):
    # The private key and short-lived JWT exist only in process memory.
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils
    key = serialization.load_pem_private_key(Path(key_file).read_bytes(), password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
        raise MetadataError('API key must be an ES256 key.')
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b'=')
    now = int(time.time())
    payload = {'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}
    payload.update({'iss': issuer} if issuer else {'sub': 'user'})
    message = encode(json.dumps({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}).encode()) + b'.' + encode(json.dumps(payload).encode())
    r, s = utils.decode_dss_signature(key.sign(message, ec.ECDSA(hashes.SHA256())))
    return (message + b'.' + encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))).decode()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise MetadataError('API redirect refused; authorization remains on Apple API host.')


class API:
    def __init__(self, bearer):
        self.bearer = bearer
        self.opener = urllib.request.build_opener(NoRedirect)

    def request(self, method, path, body=None):
        # No arbitrary external URLs and no release, build, credential or review endpoints.
        if not re.fullmatch(r'/v1/(?:apps|appInfos|appInfoLocalizations|appStoreVersions|appStoreVersionLocalizations|appCategories|betaAppLocalizations)(?:/[A-Za-z0-9-]+){0,2}(?:\?[A-Za-z0-9%=&._\[\],-]+)?', path):
            raise MetadataError('Unsupported API path.')
        req = urllib.request.Request('https://api.appstoreconnect.apple.com' + path, method=method,
            data=json.dumps(body).encode() if body else None,
            headers={'Authorization': 'Bearer ' + self.bearer, 'Accept': 'application/json', 'Content-Type': 'application/json'})
        try:
            with self.opener.open(req, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Never echo request headers, a JWT or arbitrary response content.
            try:
                codes = [item.get('code', 'UNKNOWN') for item in json.load(error).get('errors', [])]
            except Exception:
                codes = ['UNKNOWN']
            raise MetadataError(f'Apple HTTP {error.code}: {", ".join(codes)}') from None

    def list(self, path):
        result = self.request('GET', path + '?limit=200')
        if result.get('links', {}).get('next'):
            raise MetadataError('Unexpected pagination; refusing incomplete resource selection.')
        return result['data']


def only(values, predicate, message):
    candidates = [item for item in values if predicate(item)]
    if len(candidates) != 1:
        raise MetadataError(message)
    return candidates[0]


def changes(before, desired):
    return {key: value for key, value in desired.items() if before.get(key) != value}


def plan(api, meta):
    app_id = meta['appId']
    app = api.request('GET', f'/v1/apps/{app_id}')['data']
    attrs = app['attributes']
    if app['id'] != app_id or attrs['bundleId'] != meta['bundleId'] or attrs['sku'] != meta['sku']:
        raise MetadataError('App ID, bundle ID or SKU mismatch. No writes performed.')
    info = only(api.list(f'/v1/apps/{app_id}/appInfos'),
        lambda value: value['attributes'].get('state', value['attributes'].get('appStoreState')) in EDITABLE,
        'Expected exactly one editable App Information record.')
    version = only(api.list(f'/v1/apps/{app_id}/appStoreVersions'),
        lambda value: value['attributes']['platform'] == meta['platform'] and value['attributes']['versionString'] == meta['versionString']
            and value['attributes'].get('appVersionState', value['attributes'].get('appStoreState')) in EDITABLE,
        'Expected exactly one editable tvOS version matching metadata.')
    operations = []
    for parent, child_type, desired in [(info, 'appInfoLocalizations', meta['appInfo']), (version, 'appStoreVersionLocalizations', meta['version'])]:
        values = api.list(f'/v1/{parent["type"]}/{parent["id"]}/{child_type}')
        localized = [value for value in values if value['attributes']['locale'] == meta['locale']]
        if len(localized) > 1:
            raise MetadataError('Duplicate localization records.')
        before = localized[0]['attributes'] if localized else {}
        delta = changes(before, desired)
        if delta:
            if localized:
                resource_id = localized[0]['id']
                operations.append({'method': 'PATCH', 'path': f'/v1/{child_type}/{resource_id}',
                    'before': before, 'body': {'data': {'id': resource_id, 'type': child_type, 'attributes': delta}}})
            else:
                relationship = 'appInfo' if child_type == 'appInfoLocalizations' else 'appStoreVersion'
                operations.append({'method': 'POST', 'path': f'/v1/{child_type}', 'before': None,
                    'body': {'data': {'type': child_type, 'attributes': {'locale': meta['locale'], **desired},
                    'relationships': {relationship: {'data': {'id': parent['id'], 'type': parent['type']}}}}}})
    delta = changes(version['attributes'], {'copyright': meta['copyright']})
    if delta:
        operations.append({'method': 'PATCH', 'path': f'/v1/appStoreVersions/{version["id"]}', 'before': version['attributes'],
            'body': {'data': {'id': version['id'], 'type': 'appStoreVersions', 'attributes': delta}}})
    # Category is a relationship on the shared editable App Information record.
    current = api.request('GET', f'/v1/appInfos/{info["id"]}/primaryCategory')['data']
    if not current or current['id'] != meta['categoryId']:
        api.request('GET', f'/v1/appCategories/{meta["categoryId"]}')
        operations.append({'method': 'PATCH', 'path': f'/v1/appInfos/{info["id"]}', 'before': {'primaryCategory': current},
            'body': {'data': {'id': info['id'], 'type': 'appInfos', 'relationships': {'primaryCategory': {'data': {'id': meta['categoryId'], 'type': 'appCategories'}}}}}})
    return {'appId': app_id, 'bundleId': attrs['bundleId'], 'sku': attrs['sku'], 'platform': meta['platform'],
        'versionString': meta['versionString'], 'operations': operations}


def apply(api, proposal, journal_path):
    completed = []
    for operation in proposal['operations']:
        result = api.request(operation['method'], operation['path'], operation['body'])['data']
        resource_id = result['id']
        actual = api.request('GET', f'/v1/{result["type"]}/{resource_id}')['data']
        for field, expected in operation['body']['data'].get('attributes', {}).items():
            if actual['attributes'].get(field) != expected:
                raise MetadataError(f'Apple read-back mismatch for {field}.')
        for field, expected in operation['body']['data'].get('relationships', {}).items():
            related = api.request('GET', f'/v1/{result["type"]}/{resource_id}/{field}')['data']
            if related is None or related['id'] != expected['data']['id']:
                raise MetadataError('Apple relationship read-back mismatch.')
        completed.append({'method': operation['method'], 'resourceType': result['type'], 'resourceId': resource_id, 'verified': True})
        Path(journal_path).write_text(json.dumps({'completed': completed}, indent=2) + '\n')
    return completed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata', type=Path, default=ROOT / 'AppStore/en-US/metadata.json')
    parser.add_argument('--key-file', type=Path, required=True)
    parser.add_argument('--key-id', required=True)
    parser.add_argument('--issuer-id')
    parser.add_argument('--expected-sku', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    destination = ROOT / 'build/validation/app-store'
    destination.mkdir(parents=True, exist_ok=True)
    meta = load_metadata(args.metadata)
    meta['sku'] = args.expected_sku
    api = API(token(args.key_file, args.key_id, args.issuer_id))
    proposal = plan(api, meta)
    (destination / 'metadata-plan.json').write_text(json.dumps(proposal, indent=2) + '\n')
    print(json.dumps({key: value for key, value in proposal.items() if key != 'operations'}))
    print(f'Planned metadata operations: {len(proposal["operations"])}')
    if args.apply:
        completed = apply(api, proposal, destination / 'metadata-applied.json')
        remaining = plan(api, meta)['operations']
        if remaining:
            raise MetadataError('Verification found unapplied metadata.')
        print(f'Applied and read-back verified {len(completed)} operations. Repeat plan is empty.')
    else:
        print('Read-only plan saved; pass --apply to write and verify metadata.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, MetadataError) else f'Failure type: {type(error).__name__}', file=sys.stderr)
        sys.exit(1)
