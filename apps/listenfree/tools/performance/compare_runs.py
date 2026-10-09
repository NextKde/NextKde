"""Summarize identical foreground cases while preserving all raw measurements."""
import argparse
import json
import pathlib
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('baseline', type=pathlib.Path)
parser.add_argument('optimized', type=pathlib.Path)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()

def read(path):
    summary = json.loads((path/'summary.json').read_text(encoding='utf-8'))
    objects = json.loads((path/'objects.json').read_text(encoding='utf-8'))
    case = json.loads((path/'case.json').read_text(encoding='utf-8'))
    samples = [json.loads(line) for line in (path/'samples.jsonl').read_text(encoding='utf-8').splitlines()]
    assert summary['exit'] == 0 and summary['finished'] and objects[-1]['label'] == 'finished'
    assert summary['renderLoop'] == 'threaded' and summary['renderReadbackMs'] == 0
    assert all(row['sessionLocked'] is False for row in samples)
    active = [row for row in samples if row['stage'] != 'starting']
    foreground = statistics.mean(row['ownForeground'] for row in active)
    assert foreground >= .98, (str(path), foreground)
    return case, {row['stage']: row for row in summary['stages']}, {row['stage']: row for row in objects if row['label'] == 'end'}, foreground

before, a, ao, af = read(args.baseline)
after, b, bo, bf = read(args.optimized)
for key in ['steps', 'width', 'height', 'track', 'profile', 'renderLoop', 'renderReadbackMs']:
    first, second = before[key], after[key]
    if key == 'steps':
        # A read-only assertion does not change the actions or their timing.
        first = [{k: v for k, v in step.items() if k != 'expectedLyricLines'} for step in first]
        second = [{k: v for k, v in step.items() if k != 'expectedLyricLines'} for step in second]
    assert first == second, ('different input', key)
if 'songs' in ao:
    assert ao['songs']['nativeLyricLines'] == bo['songs']['nativeLyricLines'] == 89
if 'songs-return' in ao:
    for stage in ['songs-return', 'cooldown']:
        for end in [ao, bo]:
            assert end[stage]['trackTitle'] == 'AIZO' and end[stage]['nativeLyricLines'] == 89, (stage, 'external track change')
result = {'baseline': args.baseline.name, 'optimized': args.optimized.name,
          'foregroundFractions': [af, bf], 'stages': []}
for stage in a.keys() & b.keys():
    if stage not in ao or stage not in bo:
        continue
    first, second = a[stage], b[stage]
    row = {'stage': stage, 'baseline': first, 'optimized': second,
           'pwsSavedMiB': first['pws_median']-second['pws_median'],
           'pwsSavedPercent': (1-second['pws_median']/first['pws_median'])*100}
    for key in ['lyricLines', 'durationMs']:
        if stage in ['nowplaying','monet','diorama','claddagh','fume','mv','mv-resume']:
            assert ao[stage][key] == bo[stage][key], ('different lyric workload', stage, key)
            assert ao[stage]['lyricLines'] == 89
    for label, frames in [('baseline', ao[stage]), ('optimized', bo[stage])]:
        row[label] = dict(row[label])
        for key in ['frameCount', 'stageMs', 'frameIntervalP50Ms', 'frameIntervalP95Ms', 'frameIntervalP99Ms', 'frameIntervalMaxMs']:
            if key in frames:
                row[label][key] = frames[key]
        if stage in ['nowplaying','monet','diorama','claddagh','fume','mv','mv-resume']:
            assert frames['frameCount'] > frames['stageMs']*.02, ('no sustained rendering', stage, label)
    result['stages'].append(row)
order = {step['name']: i for i, step in enumerate(before['steps'])}
result['stages'].sort(key=lambda row: order[row['stage']])
args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
for row in result['stages']:
    print(f"{row['stage']}: {row['baseline']['pws_median']:.1f} -> {row['optimized']['pws_median']:.1f} MiB; saved {row['pwsSavedPercent']:.1f}%")
