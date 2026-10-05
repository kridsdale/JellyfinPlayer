#!/usr/bin/env python3
"""Seed/restore only simulator-local resume state for opt-in real VLC EOF tests.

No server requests, credentials, media files, or catalogs are read or changed.
Backups are required and retained on this checkout's internal build volume.
"""
import argparse
import json
import math
import os
import plistlib
import uuid
from pathlib import Path
import subprocess
import tempfile

BUNDLE = 'com.kridsdale.JellyfinPlayer'
REPO = Path(__file__).resolve().parents[2]


def atomic_write(path, data):
    fd, name = tempfile.mkstemp(prefix='.kids-validation-', dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inspect', 'snapshot', 'seed', 'restore'])
    parser.add_argument('--device', required=True)
    parser.add_argument('--backup', type=Path)
    parser.add_argument('--show-id')
    parser.add_argument('--item-id')
    parser.add_argument('--season', type=int)
    parser.add_argument('--episode', type=int)
    parser.add_argument('--runtime', type=float)
    parser.add_argument('--completed', type=int, choices=[0, 1])
    args = parser.parse_args()
    if args.action != 'inspect':
        subprocess.run(['xcrun', 'simctl', 'terminate', args.device, BUNDLE], check=False, capture_output=True)
    result = subprocess.run(['xcrun', 'simctl', 'get_app_container', args.device, BUNDLE, 'data'], check=True, capture_output=True, text=True)
    container = Path(result.stdout.strip()).resolve()
    expected_root = Path.home() / 'Library/Developer/CoreSimulator/Devices' / args.device / 'data/Containers/Data/Application'
    if container.parent != expected_root.resolve():
        raise ValueError('Refusing a path outside this simulator app container')
    state_path = container / 'Library/Application Support/KidsPlayer/state-v1.json'
    if not state_path.resolve().is_relative_to(container):
        raise ValueError('Refusing a redirected state path')
    store_path = state_path.parent / 'progress.store'
    is_swiftdata = store_path.exists()
    binding = None
    if is_swiftdata:
        preferences = plistlib.loads((container / 'Library/Preferences' / (BUNDLE + '.plist')).read_bytes())
        binding = json.loads(preferences['kids.binding.v1'])
        app_path = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.device, BUNDLE, 'app'], text=True).strip())
        if plistlib.loads((app_path / 'Info.plist').read_bytes()).get('KidsCloudSyncEnabled') == 'YES':
            raise ValueError('Refusing test seeds in a live iCloud-enabled build')
        with tempfile.TemporaryDirectory(prefix='kids-state-export-') as temporary:
            bind_file = Path(temporary) / 'binding.json'
            export_file = Path(temporary) / 'state.json'
            bind_file.write_text(json.dumps(binding))
            subprocess.run(['swift', 'run', '--package-path', str(REPO / 'KidsCore'), 'KidsStateTool',
                            'export', str(store_path), str(bind_file), str(export_file)], check=True)
            original = export_file.read_bytes()
    else:
        original = state_path.read_bytes()
    state = json.loads(original)

    def write_state(data):
        if not is_swiftdata:
            atomic_write(state_path, data)
            return
        if json.loads(data)['binding'] != binding:
            raise ValueError('Refusing to write across account/library identity')
        with tempfile.TemporaryDirectory(prefix='kids-state-import-') as temporary:
            bind_file = Path(temporary) / 'binding.json'
            import_file = Path(temporary) / 'state.json'
            bind_file.write_text(json.dumps(binding))
            import_file.write_bytes(data)
            mode = 'restore' if args.action == 'restore' else 'import'
            subprocess.run(['swift', 'run', '--package-path', str(REPO / 'KidsCore'), 'KidsStateTool',
                            mode, str(store_path), str(bind_file), str(import_file)], check=True)
    if state.get('version') != 1 or len(set(state['binding'].values())) != 4:
        raise ValueError('Unexpected state schema or identity')
    if args.action == 'inspect':
        print(json.dumps({'ordered': state['ordered'], 'session': state.get('session'), 'episodeLimit': state['preferences']['episodeLimit']}))
        return
    if not args.backup or not args.backup.resolve().is_relative_to(REPO / 'build/validation'):
        raise ValueError('A backup under this checkout build/validation directory is required')
    backup = args.backup.resolve()
    if args.action == 'snapshot':
        backup.parent.mkdir(parents=True, exist_ok=True)
        with backup.open('xb') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(original)
        print('Saved a scoped simulator-state snapshot without changing playback state.')
        return
    if args.action == 'restore':
        data = backup.read_bytes()
        if json.loads(data)['binding'] != state['binding']:
            raise ValueError('Refusing to restore across account/library identity')
        write_state(data)
        print('Restored the original local progress; retained backup.')
        return
    if not all([args.show_id, args.item_id, args.season and args.season > 0, args.episode and args.episode > 0,
                args.runtime and math.isfinite(args.runtime) and args.runtime > 35]) or args.completed is None:
        raise ValueError('Verified regular episode metadata and completion count are required')
    if args.completed == 1:
        session = state.get('session') or {}
        if not (session.get('completed') == 1 and session.get('limit') == 2 and
                session.get('itemID') == args.item_id and session.get('showID') == args.show_id and session.get('mode') == 'ordered'):
            raise ValueError('Second test requires the real first EOF and next-item budget to have persisted')
        if not backup.is_file():
            raise ValueError('Original backup is missing')
    else:
        backup.parent.mkdir(parents=True, exist_ok=True)
        with backup.open('xb') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(original)
    seconds = args.runtime - 25
    state['preferences']['episodeLimit'] = 2
    state['ordered'][args.show_id] = {'itemID': args.item_id, 'seconds': seconds, 'complete': False,
                                     'season': args.season, 'episode': args.episode, 'selectionID': str(uuid.uuid4())}
    state['session'] = {'showID': args.show_id, 'mode': 'ordered', 'completed': args.completed, 'limit': 2,
                        'itemID': args.item_id, 'seconds': seconds}
    write_state(json.dumps(state, sort_keys=True).encode())
    print(json.dumps({'itemID': args.item_id, 'resumeSeconds': seconds, 'completed': args.completed, 'limit': 2}))


if __name__ == '__main__':
    main()
