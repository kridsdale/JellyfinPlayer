#!/usr/bin/env python3
"""Collect private simulator timing logs and summarize client latency; never contacts Jellyfin or the RAID."""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import shutil
import statistics
import subprocess

REPO = Path(__file__).resolve().parents[2]
BUNDLE = 'com.kridsdale.JellyfinPlayer'


def stats(values):
    negative = sum(math.isfinite(v) and v < 0 for v in values)
    values = sorted(v for v in values if math.isfinite(v) and v >= 0)
    if not values:
        return {'n': 0, 'excluded_negative': negative}
    return {'n': len(values), 'excluded_negative': negative, 'median_ms': round(statistics.median(values), 3),
            'p95_ms': round(values[max(0, math.ceil(.95 * len(values)) - 1)], 3),
            'min_ms': round(values[0], 3), 'max_ms': round(values[-1], 3)}


def collect(device, destination):
    destination = destination.resolve()
    if not destination.is_relative_to(REPO / 'build/validation'):
        raise ValueError('Retain logs under this checkout build/validation directory')
    container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, BUNDLE, 'data'], text=True).strip()).resolve()
    expected = Path.home() / 'Library/Developer/CoreSimulator/Devices' / device / 'data/Containers/Data/Application'
    if container.parent != expected.resolve():
        raise ValueError('Refusing a non-simulator or redirected app container')
    source = container / 'Library/Application Support/KidsPlayer/Performance'
    if source.is_symlink() or not source.resolve().is_relative_to(container):
        raise ValueError('Refusing a redirected diagnostics directory')
    destination.mkdir(parents=True, exist_ok=True)
    copied = 0
    marker = destination / 'start-unix-ms.json'
    after = json.loads(marker.read_text())['after_unix_ms'] if marker.exists() else 0
    for path in sorted(source.glob('*.jsonl')):
        if path.is_symlink() or path.stat().st_size > 8 * 1024 * 1024:
            raise ValueError('Unexpected profiling artifact')
        first = next((line for line in path.read_text().splitlines() if line.strip()), None)
        if first is None or json.loads(first).get('unixMS', 0) < after:
            continue
        target = destination / path.name
        shutil.copyfile(path, target)
        target.chmod(0o600)
        copied += 1
    return copied


def analyze(directory):
    spans = defaultdict(list)
    bad_lines = 0
    files = sorted(directory.glob('*.jsonl'))
    for path in files:
        for line in path.read_text().splitlines():
            try:
                event = json.loads(line)
                if not all(k in event for k in ('runID', 'traceID', 'operation', 'phase', 'elapsedMS')):
                    raise ValueError('Not a timing event')
                spans[event['traceID']].append(event)
            except (ValueError, KeyError):
                bad_lines += 1
    for events in spans.values():
        events.sort(key=lambda event: event['uptimeMS'])
    metrics = defaultdict(list)
    starts = []
    http = defaultdict(list)
    network = defaultdict(lambda: defaultdict(list))
    failures = defaultdict(int)
    cancellations = defaultdict(int)
    incomplete = defaultdict(int)
    response_status = defaultdict(lambda: defaultdict(int))
    children = defaultdict(list)
    for key, events in spans.items():
        parent = events[0].get('parentID')
        if parent:
            children[parent].append(key)

    def descendants(trace):
        for child in children.get(trace, []):
            yield child
            yield from descendants(child)

    for key, events in spans.items():
        base = events[0]
        operation, variant = base['operation'], base['variant']
        phases = {e['phase']: e for e in events}
        end = phases.get('end')
        if end and end.get('outcome') == 'failure':
            failures[operation] += 1
        elif end and end.get('outcome') == 'cancelled':
            cancellations[operation] += 1
        elif end is None:
            incomplete[operation] += 1
        if 'response' in phases and 'status' in phases['response']['values']:
            response_status[operation][str(int(phases['response']['values']['status']))] += 1
        if operation == 'launch':
            for name in ('catalogReady', 'browsePresented'):
                if name in phases:
                    metrics['launch.' + name].append(phases[name]['elapsedMS'])
        if operation == 'catalog' and 'catalogReady' in phases:
            metrics['catalog.ready'].append(phases['catalogReady']['elapsedMS'])
            if 'browsePresented' in phases:
                metrics['catalog.presented'].append(phases['browsePresented']['elapsedMS'])
        if operation == 'title' and 'actionsReady' in phases:
            metrics['title.actionsReady.' + variant].append(phases['actionsReady']['elapsedMS'])
        if operation == 'artwork':
            for name in ('response', 'imageConstructed', 'artworkPresented'):
                if name in phases:
                    metrics['artwork.' + name + '.' + variant].append(phases[name]['elapsedMS'])
            if 'response' in phases and 'artworkPresented' in phases:
                metrics['artwork.responseToPresentation.' + variant].append(
                    phases['artworkPresented']['elapsedMS'] - phases['response']['elapsedMS'])
        if end and end.get('outcome') == 'success':
            if operation in ('storeOpen', 'storeLoad', 'storeSave', 'metadata', 'bitrate', 'playbackInfo', 'policy', 'episodes', 'authorize', 'ancestry'):
                metrics['operation.' + operation].append(end['elapsedMS'])
            if operation == 'http':
                http[base.get('endpoint', 'other')].append(end['elapsedMS'])
        for event in events:
            if event['phase'] == 'network':
                endpoint = base.get('endpoint', 'other')
                for k, v in event['values'].items():
                    network[endpoint][k].append(v)
        if operation == 'playback':
            row = {'run_id': base['runID'], 'trace_id': key, 'mode': variant,
                   'outcome': end.get('outcome') if end else 'incomplete'}
            valid = bool(end and end.get('outcome') == 'success' and
                         all(p in phases for p in ('firstVideoOutput', 'firstClock', 'playerSurfacePresented')))
            row['validated_timing_sample'] = valid
            for phase, event in phases.items():
                row[phase + '_ms'] = round(event['elapsedMS'], 3)
                if phase in ('itemSelected', 'providerReady', 'firstVideoOutput'):
                    row.update(event['values'])
            for milestone in ('authorized', 'controllerReady', 'providerReady', 'vlcOpen', 'vlcPlaying', 'firstInput', 'firstDecode', 'firstVideoOutput', 'firstClock', 'playbackBegan', 'playerSurfacePresented'):
                if valid and milestone in phases:
                    metrics['playback.' + milestone + '.' + variant].append(phases[milestone]['elapsedMS'])
            parts = [('selection', 'begin', 'itemSelected'), ('authorization', 'itemSelected', 'authorized'),
                     ('controllerPreparation', 'authorized', 'controllerReady'), ('provider', 'controllerReady', 'providerReady'),
                     ('viewAndOpen', 'providerReady', 'vlcOpen'), ('openToPlaying', 'vlcOpen', 'vlcPlaying'),
                     ('openToVideoOutput', 'vlcOpen', 'firstVideoOutput'),
                     ('outputToSurface', 'firstVideoOutput', 'playerSurfacePresented')]
            for name, a, b in parts:
                if a in phases and b in phases:
                    value = phases[b]['elapsedMS'] - phases[a]['elapsedMS']
                    row[name + '_ms'] = round(value, 3)
                    if valid:
                        metrics['playback.component.' + name + '.' + variant].append(value)
            nested = [spans[x][0] for x in descendants(key)]
            row['instrumented_http_count'] = sum(e['operation'] == 'http' for e in nested)
            row['ancestor_http_count'] = sum(e['operation'] == 'http' and e.get('endpoint') == 'ancestors' for e in nested)
            starts.append(row)
    result = {'files': len(files), 'events': sum(len(v) for v in spans.values()), 'spans': len(spans),
              'malformed_lines': bad_lines, 'failures': dict(failures),
              'cancellations': dict(cancellations), 'incomplete_spans': dict(incomplete),
              'response_status': {k: dict(v) for k, v in response_status.items()},
              'metrics': {k: stats(v) for k, v in sorted(metrics.items())},
              'http': {k: stats(v) for k, v in sorted(http.items())},
              'network': {endpoint: {k: stats(v) if k.endswith('_ms') else {'n': len(v), 'sum': sum(v), 'median': statistics.median(v)}
                                      for k, v in values.items()} for endpoint, values in network.items()},
              'playback_starts': starts}
    (directory / 'summary.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    lines = ['# Measured client timing summary', '',
             'Opt-in Release simulator probes, actual approved Jellyfin content. Values in milliseconds. P95 is the observed nearest rank; small samples are not a population guarantee.', '',
             f'Files: {len(files)}; events: {result["events"]}; malformed lines: {bad_lines}.', '',
             '| Metric | n | Median ms | Observed P95 ms | Min ms | Max ms |',
             '|---|---:|---:|---:|---:|---:|']
    for k, v in result['metrics'].items():
        if v['n']:
            lines.append(f'| {k} | {v["n"]} | {v["median_ms"]:.1f} | {v["p95_ms"]:.1f} | {v["min_ms"]:.1f} | {v["max_ms"]:.1f} |')
    lines.extend(['', '## HTTP completion (catalog requests only; SDK request network metrics are also in summary.json)', '',
                  '| Endpoint | n | Median ms | Observed P95 ms |', '|---|---:|---:|---:|'])
    for k, v in result['http'].items():
        if v['n']:
            lines.append(f'| {k} | {v["n"]} | {v["median_ms"]:.1f} | {v["p95_ms"]:.1f} |')
    lines.extend(['', 'First video output uses libVLC cumulative statistics, observed every 50 ms; libVLC updates some counters more slowly. Presentation markers are the next main-run-loop frame opportunity, not GPU fences. HTTP first-byte wait includes server processing and network transit and cannot isolate a disk seek. Fresh process is not cold RAID/OS/server cache. Negative milestone differences are excluded from latency distributions and counted explicitly in summary.json, since asynchronous counter observations can trail the UI surface. No cache purge or performance optimization occurred.'])
    (directory / 'summary.md').write_text('\n'.join(lines) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['collect', 'analyze'])
    parser.add_argument('--device')
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    if args.action == 'collect':
        if not args.device:
            parser.error('--device is required for collection')
        print(json.dumps({'files_collected': collect(args.device, args.directory)}))
    result = analyze(args.directory)
    print(json.dumps({k: result[k] for k in ('files', 'events', 'spans', 'malformed_lines', 'failures')}, sort_keys=True))


if __name__ == '__main__':
    main()
