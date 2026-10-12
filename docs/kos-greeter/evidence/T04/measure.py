"""Reproduce manual measurement tables and vector overlays; no raster modification."""
import csv
from pathlib import Path
from xml.sax.saxutils import escape
ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
# Bounds [x0,y0,x1,y1], half-open, manually read visible edges, not font/layout metrics.
SAMPLES = [
 ('A', 'tahoe-apple-lockscreen.jpg', 980, 653, (154,83,826,520), 3, [
 ('date',(465,125,515,136)),('clock',(434,140,547,188)),
 ('avatar',(479,445,501,467)),('name',(470,474,510,482)),('hint',(452,490,527,496))]),
 ('B', 'tahoe-multiuser.png', 2880, 1800, (0,0,2880,1800), 6, [
 ('date',(1329,172,1549,216)),('clock',(1208,246,1670,430)),
 ('avatar1',(1260,1363,1352,1455)),('name1',(1370,1395,1547,1423)),
 ('avatar2',(1260,1481,1352,1573)),('name2',(1370,1513,1612,1541))])]
with (OUT/'measurements.csv').open('w') as f:
 w=csv.writer(f);w.writerow(['source','element','x0','y0','x1','y1','width','height','anchor_x','anchor_y','normalized_cx','normalized_cy','edge_error_px'])
 for sid,file,iw,ih,screen,error,boxes in SAMPLES:
  sx,sy,ex,ey=screen; sw,sh=ex-sx,ey-sy
  svg=[f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {iw} {ih}" width="{iw}" height="{ih}">', '<title>Research annotation — manual approximate bounds, not product assets</title>',f'<image width="{iw}" height="{ih}" xlink:href="../../assets/references/{file}"/>',f'<rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" fill="none" stroke="#ff3860" stroke-width="2"/>']
  for label,(x0,y0,x1,y1) in boxes:
   cx,cy=(x0+x1)/2,(y0+y1)/2
   w.writerow([sid,label,x0,y0,x1,y1,x1-x0,y1-y0,cx,cy,f'{(cx-sx)/sw:.6f}',f'{(cy-sy)/sh:.6f}',error])
   svg += [f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" fill="none" stroke="#ffeb00" stroke-width="2"/>',f'<text x="{x1+5}" y="{y0}" font-family="sans-serif" font-size="{12 if sid=="A" else 28}" fill="#ffeb00" stroke="#000" stroke-width="0.4">{escape(label)}</text>']
  svg += ['</svg>'];(OUT/f'annotated-{sid}.svg').write_text('\n'.join(svg))
