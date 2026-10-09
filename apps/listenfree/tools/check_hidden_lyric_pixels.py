"""Compare complete paused return frames, including the first displayed frame."""
import argparse
import json
from PIL import Image, ImageChops, ImageStat

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('baseline')
parser.add_argument('optimized')
parser.add_argument('--output')
args = parser.parse_args()
from pathlib import Path
results = []
for style in ['monet', 'fume']:
    for delay in ['0ms', '16ms', '50ms', '100ms', '250ms', '']:
        suffix = f'.{delay}' if delay else ''
        name = f'objects.json.{style}-return{suffix}.png'
        images = [Image.open(Path(path)/name).convert('RGB') for path in [args.baseline, args.optimized]]
        assert images[0].size == images[1].size
        difference = ImageChops.difference(*images)
        maximum = max(value[1] for value in difference.getextrema())
        results.append({'style': style, 'delay': delay or '2500ms', 'maximum': maximum,
                        'mean': sum(ImageStat.Stat(difference).mean)/3})
        assert maximum <= 2, (name, maximum, 'return frame changed')
if args.output:
    Path(args.output).write_text(json.dumps(results, indent=2), encoding='utf-8')
print('PASS: 12 complete return frames, maximum channel difference <= 2/255')
