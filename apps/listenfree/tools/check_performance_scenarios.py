"""Validate completed native browsing and immersive lifecycle scenarios."""
import argparse
import statistics
import json
import pathlib
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('base', type=pathlib.Path)
parser.add_argument('--browsing', default='browsing-functional')
parser.add_argument('--stress', default='acceptance-stress-functional')
parser.add_argument('--foreground', action='store_true')
args = parser.parse_args()
base = args.base

def ends(name):
    rows = json.loads((base/name/'objects.json').read_text(encoding='utf-8'))
    assert rows[-1]['label'] == 'finished', (name, 'incomplete run')
    end = {row['stage']: row for row in rows if row['label'] == 'end'}
    if args.foreground:
        summary = json.loads((base/name/'summary.json').read_text(encoding='utf-8'))
        samples = [json.loads(line) for line in (base/name/'samples.jsonl').read_text().splitlines()]
        assert summary['exit'] == 0 and summary['renderLoop'] == 'threaded' and summary['renderReadbackMs'] == 0
        assert all(row['sessionLocked'] is False for row in samples), (name, 'locked')
        active = [row for row in samples if row['stage'] != 'starting']
        assert statistics.mean(row['ownForeground'] for row in active) >= .98, (name, 'foreground lost')
        if name == args.stress:
            for stage in ['nowplaying', 'monet', 'diorama', 'claddagh', 'fume', 'mv', 'mv-resume']:
                row = end[stage]
                assert row['lyricLines'] == 89 and row['durationMs'] == 215922, (name, stage, 'incomplete lyric workload')
                assert row['frameCount'] > row['stageMs'] * .02, (name, stage, 'no sustained rendering')
    return end

browse = ends(args.browsing)
for index in range(3):
    assert any(view['name'] == 'songTableList' and view.get('count', 0) > 0
               for view in browse[f'playlist-{index}']['visibleViews']), ('playlist empty', index)
    assert any(view['name'] == 'discoverScroll'
               for view in browse[f'discover-return-{index}']['visibleViews'])
for stage in ['mosaic', 'mosaic-pan-6' if 'mosaic-pan-6' in browse else 'mosaic-pan']:
    counts = browse[stage]['counts']
    assert counts.get('mosaicImages', 0) > 0 and counts.get('mosaicImagesNotReady', 0) == 0, stage
artist = next(group for group in browse['artist-hero']['backgrounds'] if group['name'] == 'artistBackdrop')
assert any(layer['ready'] and layer['source'].startswith('https://') for layer in artist['layers']), 'Online artist hero not loaded'
if args.foreground:
    for stage in ['songs', 'songs-return', 'cooldown']:
        row = browse[stage]
        assert row.get('nativeLyricLines') == 89 and row['trackTitle'] == 'AIZO', (stage, 'track changed during browsing')
    # The scripted chain must remain on the song page throughout cooldown.
    for row in json.loads((base/args.browsing/'objects.json').read_text(encoding='utf-8')):
        if row['stage'] == 'cooldown':
            assert row.get('trackTitle') == 'AIZO' and row.get('nativeLyricLines') == 89, ('cooldown', 'external track change')
            assert any(page['route'] == 'library/songs' and page['visible'] for page in row['navigationPages']), ('cooldown', 'external navigation')
song_count = lambda row: max(view.get('count', 0) for view in row['visibleViews'])
assert song_count(browse['songs']) == song_count(browse['songs-return']) > 0

stress = ends(args.stress)
for style in ['monet', 'diorama', 'claddagh', 'fume']:
    assert stress[style]['immersive'] and stress[style]['pvStyle'] == style, style
for visual in ['spectrum', 'ambient']:
    assert stress[visual]['sampling'] and stress[visual]['visualization'] == visual, visual
assert not stress['visual-off']['sampling']
for stage in ['queue', 'queue-scroll']:
    assert 0 < stress[stage]['discSectors'] <= 11, stage
assert stress['queue-close'].get('discSectors', 0) == 0
assert stress['mv']['videoPlayer'] and stress['mv']['videoWidth'] == 1280
assert stress['mv-pause']['videoState'] == 2 and stress['mv-resume']['videoState'] == 1
assert not stress['mv-clear']['videoPlayer']
for index in range(1, 7):
    assert stress[f'enter-{index}']['immersive'], index
    closed = stress[f'exit-{index}']
    assert not closed['immersive'] and not closed['serviceActive'] and not closed['videoPlayer'], index
assert not stress['cooldown']['immersive'] and not stress['cooldown']['sampling']
print('PASS: three playlists, mosaic, loaded online artist hero, return; styles, visualizers, queue, MV and six enter/exit cycles')
