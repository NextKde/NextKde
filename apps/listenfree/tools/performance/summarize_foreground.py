"""Validate foreground acceptance inputs before reporting memory/frame results."""
import argparse
import json
import pathlib
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('results', type=pathlib.Path)
parser.add_argument('--runs', nargs='+', default=['acceptance-2', 'acceptance-3', 'acceptance-4'])
args = parser.parse_args()
stages = ['cold-30s', 'ordinary-playing', 'nowplaying', 'fullscreen-monet', 'cooldown']
output = {'runs': [], 'scope': 'Native Release modules, threaded rendering, no screenshot readback, fixed local AIZO fixture'}
for name in args.runs:
    path = args.results/name
    objects = json.loads((path/'objects.json').read_text(encoding='utf-8'))
    summary = json.loads((path/'summary.json').read_text(encoding='utf-8'))
    samples = [json.loads(line) for line in (path/'samples.jsonl').read_text(encoding='utf-8').splitlines()]
    assert summary['exit'] == 0 and summary['finished'] and objects[-1]['label'] == 'finished', (name, 'incomplete')
    assert summary['renderLoop'] == 'threaded' and summary['renderReadbackMs'] == 0, (name, 'non-production render conditions')
    assert all(row.get('sessionLocked') is False for row in samples), (name, 'locked or unknown session')
    active = [row for row in samples if row['stage'] in ['ordinary-playing', 'nowplaying', 'fullscreen-monet']]
    foreground = statistics.mean(row.get('ownForeground') is True for row in active)
    assert foreground >= .98, (name, 'foreground lost', foreground)
    ends = {row['stage']: row for row in objects if row['label'] == 'end'}
    for stage in ['nowplaying', 'fullscreen-monet']:
        row = ends[stage]
        assert row.get('lyricLines') == 89 and row['durationMs'] == 215922, (name, stage, 'AIZO lyrics missing or track changed')
        assert row['frameCount'] > row['stageMs'] * .02, (name, stage, 'no sustained rendering')
        if 'trackTitle' in row:
            assert row['trackTitle'] == 'AIZO', (name, stage, 'track changed')
    full = ends['fullscreen-monet']
    assert full['height'] > 709 and full['scopes']['immersive']['texts'] > 20, (name, 'full-screen lyric workload missing')
    measurements = {row['stage']: row for row in summary['stages']}
    report = {'name': name, 'foregroundFraction': foreground, 'stages': []}
    for stage in stages:
        row = dict(measurements[stage])
        frames = ends[stage]
        if stage in ['nowplaying', 'fullscreen-monet']:
            for key in ['frameIntervalP50Ms', 'frameIntervalP95Ms', 'frameCount']:
                row[key] = frames[key]
            row['renderedFramesPerSecond'] = frames['frameCount']/(frames['stageMs']/1000)
        # Static pages render on demand; their long intervals are not frame stalls.
        report['stages'].append(row)
    output['runs'].append(report)
output['ranges'] = {}
for stage in stages:
    rows = [next(row for row in run['stages'] if row['stage'] == stage) for run in output['runs']]
    output['ranges'][stage] = {
        'pwsMedianMiB': [min(row['pws_median'] for row in rows), max(row['pws_median'] for row in rows)],
        'pwsPeakMiB': max(row['pws_peak'] for row in rows),
        'under400MiBSteady': all(row['pws_median'] < 400 for row in rows),
    }
destination = args.results/'foreground-acceptance.json'
destination.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps(output['ranges'], indent=2))
print(destination)
