"""检查裁剪前后的实际 RGBA：允许渲染目标投影造成的稀疏边缘舍入差。"""
import json
from pathlib import Path
import sys
from PIL import Image, ImageChops, ImageStat

root = Path(sys.argv[1])
results = []
for name in ('expanded', 'collapsed', 'compact'):
    before = Image.open(root / f'original-{name}.png').convert('RGBA')
    after = Image.open(root / f'optimized-{name}.png').convert('RGBA')
    assert before.size == after.size
    delta = ImageChops.difference(before, after)
    maximum = max(high for low, high in delta.getextrema())
    changed = sum(any(pixel) for pixel in delta.getdata())
    fraction = changed / (before.width * before.height)
    alpha = delta.getchannel('A').getextrema()[1]
    result = dict(scene=name, size=before.size, maximum=maximum,
                  changedPixels=changed, changedFraction=fraction, alphaDifference=alpha,
                  mean=ImageStat.Stat(delta).mean)
    results.append(result)
    print(json.dumps(result, ensure_ascii=False))
    assert maximum <= 8 and fraction < .001 and alpha == 0, result
(root / 'pixel-comparison.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
