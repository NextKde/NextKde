#!/usr/bin/env python3
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'companion'))
from measurement import analyze


def rows(labels, periods=None):
    periods = periods or [10] * len(labels)
    pts = 0
    result = []
    for i, (label, duration) in enumerate(zip(labels, periods)):
        result.append(dict(frame=i, pts_ms=pts, duration_ms=duration, **{'class': label}))
        pts += duration
    return result


class Measurement(unittest.TestCase):
    def test_separate_runs_and_variable_timing(self):
        report = analyze(rows(['black_content', 'black_content', 'background', 'black_content', 'no_signal', 'unknown'], [10, 20, 10, 30, 10, 10]), 1, 239.998)
        black = report['classes']['black_content']
        self.assertEqual((black['frame_count'], black['run_count'], black['sampled_total_ms']), (3, 2, 60))
        self.assertEqual(black['median_run_ms'], 30)
        self.assertEqual(report['classes']['no_signal']['frame_count'], 1)
        self.assertTrue(report['undersampled'])
        self.assertFalse(report['zero_black_frames_proven'])
        self.assertEqual(report['boundary_uncertainty_ms'], 62)
    def test_absence_is_not_proof(self):
        report = analyze(rows(['background']), 1, 60)
        self.assertIsNone(report['classes']['black_content']['max_run_ms'])
        self.assertFalse(report['zero_black_frames_proven'])
    def test_invalid_data(self):
        bad = [[], rows(['invalid']), rows(['background'], [-1]), rows(['background'], [float('nan')])]
        gap = rows(['background', 'background']); gap[1]['pts_ms'] += 1; bad.append(gap)
        missing = rows(['background']); missing[0]['frame'] = 1; bad.append(missing)
        for data in bad:
            with self.subTest(data=data), self.assertRaises(ValueError):
                analyze(data, 1, 60)
        for exposure, hz in [(0, 60), (1, 0), (float('inf'), 60)]:
            with self.assertRaises(ValueError): analyze(rows(['background']), exposure, hz)


if __name__ == '__main__': unittest.main()
