"""Compare the already-loaded chart art against the first restored frame."""
import pathlib,sys
from PIL import Image,ImageChops
p=pathlib.Path(sys.argv[1])
before=Image.open(p/'objects.json.discover-set.png').convert('RGB')
after=Image.open(p/'objects.json.discover-return.0ms.png').convert('RGB')
for box in [(480,315,590,430),(700,315,810,430),(920,315,1030,430)]:
    delta=ImageChops.difference(before.crop(box),after.crop(box))
    maximum=max(x[1] for x in delta.getextrema())
    assert maximum<=2,('Restored artwork must not flash a placeholder',box,maximum)
print('PASS: restored chart covers match on the first captured frame')
