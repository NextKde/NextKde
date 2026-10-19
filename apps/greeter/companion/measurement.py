#!/usr/bin/env python3
"""Offline analysis of externally recorded, manually classified frames (T13)."""
import argparse
import csv
import json
import math
import statistics
from pathlib import Path

CLASSES = {'background', 'no_signal', 'black_content', 'wrong_placeholder', 'frozen_old_frame', 'unknown'}


def analyze(rows, exposure_ms, display_hz):
    if not math.isfinite(exposure_ms) or exposure_ms <= 0 or not math.isfinite(display_hz) or display_hz <= 0:
        raise ValueError('positive finite exposure_ms and display_hz required')
    frames = []
    for index, row in enumerate(rows):
        pts, duration = float(row['pts_ms']), float(row['duration_ms'])
        if int(row['frame']) != index or row['class'] not in CLASSES:
            raise ValueError('frames must be contiguous from 0 and classes must be explicit')
        if not math.isfinite(pts) or pts < 0 or not math.isfinite(duration) or duration <= 0:
            raise ValueError('invalid frame timing')
        if frames and abs(pts - (frames[-1]['pts_ms'] + frames[-1]['duration_ms'])) > 0.001:
            raise ValueError('missing, overlapping or discontinuous frames')
        frames.append(dict(frame=index, pts_ms=pts, duration_ms=duration, classification=row['class']))
    if not frames:
        raise ValueError('no frames: unmeasured is not zero')
    periods = [f['duration_ms'] for f in frames]
    uncertainty = 2 * (max(periods) + exposure_ms)
    result = {}
    for label in sorted(CLASSES):
        runs = []
        for f in frames:
            if f['classification'] == label:
                if runs and runs[-1]['last_frame'] == f['frame'] - 1:
                    runs[-1]['last_frame'] = f['frame']
                    runs[-1]['sampled_ms'] += f['duration_ms']
                else:
                    runs.append(dict(first_frame=f['frame'], last_frame=f['frame'], pts_ms=f['pts_ms'], sampled_ms=f['duration_ms']))
        durations = [r['sampled_ms'] for r in runs]
        result[label] = dict(frame_count=sum(r['last_frame'] - r['first_frame'] + 1 for r in runs),
                             run_count=len(runs), sampled_total_ms=sum(durations),
                             max_run_ms=max(durations) if durations else None,
                             median_run_ms=statistics.median(durations) if durations else None, runs=runs)
    return dict(evidence_kind='manual_external_video_classification', frame_count=len(frames),
                observed_interval_ms=[frames[0]['pts_ms'], frames[-1]['pts_ms'] + frames[-1]['duration_ms']],
                max_sample_period_ms=max(periods), exposure_ms=exposure_ms, display_hz=display_hz,
                display_period_ms=1000 / display_hz,
                boundary_uncertainty_ms=uncertainty,
                undersampled=max(periods) > 1000 / display_hz,
                zero_black_frames_proven=False, classes=result,
                limitation='Sampled duration is not scanout duration; absent classes may occur between samples. No DRM cause inferred.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('frames', type=Path, help='CSV: frame,pts_ms,duration_ms,class; one row per decoded frame')
    parser.add_argument('--exposure-ms', required=True, type=float)
    parser.add_argument('--display-hz', required=True, type=float)
    args = parser.parse_args()
    try:
        with args.frames.open(newline='') as stream:
            report = analyze(list(csv.DictReader(stream)), args.exposure_ms, args.display_hz)
    except (ValueError, KeyError, OSError) as error:
        parser.error(str(error))
    print(json.dumps(report, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
