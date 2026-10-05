import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('metadata', Path(__file__).with_name('metadata.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
META = m.load_metadata(m.ROOT / 'AppStore/en-US/metadata.json')
META['sku'] = 'fixture-sku'


class FixtureAPI:
    def __init__(self):
        self.writes = []
        self.app = {'id': META['appId'], 'type': 'apps', 'attributes': {'bundleId': META['bundleId'], 'sku': META['sku']}}
        self.info = {'id': 'info', 'type': 'appInfos', 'attributes': {'state': 'PREPARE_FOR_SUBMISSION'}}
        self.version = {'id': 'tv', 'type': 'appStoreVersions', 'attributes': {'platform': 'TV_OS', 'versionString': '1.0', 'appVersionState': 'PREPARE_FOR_SUBMISSION', 'copyright': None}}
        self.localization = {'id': 'tv-locale', 'type': 'appStoreVersionLocalizations', 'attributes': {'locale': 'en-US'}}
        self.info_locale = {'id': 'info-locale', 'type': 'appInfoLocalizations', 'attributes': {'locale': 'en-US'}}
        self.category = {'id': 'ENTERTAINMENT', 'type': 'appCategories', 'attributes': {}}
        self.mismatch = False
        self.other = {'id': 'ios', 'type': 'appStoreVersions', 'attributes': {'platform': 'IOS', 'versionString': '1.0', 'appVersionState': 'PREPARE_FOR_SUBMISSION'}}

    def list(self, path):
        if path.endswith('/appInfos'): return [self.info]
        if path.endswith('/appStoreVersions'): return [self.other, self.version]
        if path.endswith('/appInfoLocalizations'): return [self.info_locale]
        if path.endswith('/appStoreVersionLocalizations'): return [self.localization]
        raise AssertionError(path)

    def request(self, method, path, body=None):
        if path.startswith('/v1/apps/'): item = self.app
        elif path.endswith('/primaryCategory') or path.startswith('/v1/appCategories/'): item = self.category
        elif path.startswith('/v1/appInfoLocalizations/'): item = self.info_locale
        elif path.startswith('/v1/appStoreVersionLocalizations/'): item = self.localization
        elif path.startswith('/v1/appStoreVersions/'): item = self.version
        elif path.startswith('/v1/appInfos/'): item = self.info
        else: raise AssertionError(path)
        if method != 'GET':
            self.writes.append((method, path, copy.deepcopy(body)))
            if not self.mismatch: item['attributes'].update(body['data'].get('attributes', {}))
        return {'data': copy.deepcopy(item)}


class MetadataTests(unittest.TestCase):
    def test_registration_mismatch_prevents_writes(self):
        for field in ['bundleId', 'sku']:
            api = FixtureAPI(); api.app['attributes'][field] = 'other'
            with self.assertRaises(m.MetadataError): m.plan(api, META)
            self.assertEqual(api.writes, [])

    def test_plan_is_read_only_and_updates_only_tv_platform(self):
        api = FixtureAPI(); proposal = m.plan(api, META)
        self.assertEqual(api.writes, [])
        self.assertEqual(len(proposal['operations']), 3)
        for operation in proposal['operations']:
            self.assertNotIn('/ios', operation['path'])
            self.assertNotIn('release', operation['path'].lower())

    def test_noneditable_version_refuses_writes(self):
        api = FixtureAPI(); api.version['attributes']['appVersionState'] = 'READY_FOR_DISTRIBUTION'
        with self.assertRaises(m.MetadataError): m.plan(api, META)
        self.assertEqual(api.writes, [])

    def test_apply_verifies_and_repeat_is_empty(self):
        api = FixtureAPI()
        with tempfile.TemporaryDirectory() as directory:
            completed = m.apply(api, m.plan(api, META), Path(directory) / 'journal.json')
        self.assertEqual(len(completed), 3)
        self.assertEqual(m.plan(api, META)['operations'], [])

    def test_failed_readback_stops_following_writes(self):
        api = FixtureAPI(); api.mismatch = True
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(m.MetadataError): m.apply(api, m.plan(api, META), Path(directory) / 'journal.json')
        self.assertEqual(len(api.writes), 1)

    def test_keyword_limit_uses_bytes_and_unsupported_fields_are_rejected(self):
        for change in [{'keywords': 'é' * 51}, {'unsupported': 'x'}]:
            meta = copy.deepcopy(META); meta['version'].update(change)
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'metadata.json'; path.write_text(json.dumps(meta))
                with self.assertRaises(m.MetadataError): m.load_metadata(path)


if __name__ == '__main__': unittest.main()
