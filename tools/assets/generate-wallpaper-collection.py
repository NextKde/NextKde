#!/usr/bin/env python3
"""Bake the original Stilllight collection. Requires Pillow and NumPy only offline.

The desktop loads the resulting plates; none of this terrain/cloud generation
runs in the shell. All coordinates, including the animated masks, use a 16:9
artboard. Seeds are fixed so rebuilding doesn't change a user's wallpaper.
"""
from pathlib import Path
import argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
W, H = 2560, 1440
X, Y = np.meshgrid(np.linspace(0, 1, W, dtype=np.float32),
                   np.linspace(0, 1, H, dtype=np.float32))


def rgb(value):
    return np.array(tuple(bytes.fromhex(value.lstrip('#'))), dtype=np.float32) / 255


def smooth(a, b, value):
    t = np.clip((value - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def noise(seed, octaves=6, scale=4):
    rng = np.random.default_rng(seed)
    result = np.zeros((H, W), dtype=np.float32)
    weight = 0
    for i in range(octaves):
        s = scale * 2**i
        grid = rng.random((s, int(s * W / H) + 1), dtype=np.float32)
        layer = np.asarray(Image.fromarray(grid).resize((W, H), Image.Resampling.BICUBIC))
        amplitude = 0.52**i
        result += layer * amplitude
        weight += amplitude
    return result / weight


def gradient(stops):
    result = np.empty((H, W, 3), dtype=np.float32)
    for i in range(3):
        result[:, :, i] = np.interp(Y[:, 0], [s[0] for s in stops],
                                     [rgb(s[1])[i] for s in stops])[:, None]
    return result


def glow(canvas, x, y, rx, ry, color, power):
    light = np.exp(-((X-x)/rx)**2-((Y-y)/ry)**2) * power
    canvas += light[:, :, None] * rgb(color)


def stars(canvas, seed, count=550):
    rng = np.random.default_rng(seed)
    image = Image.new('RGB', (W, H))
    draw = ImageDraw.Draw(image)
    for _ in range(count):
        x, y = rng.uniform(0, W), rng.uniform(0, H*.63)
        r = rng.choice([.45, .65, 1, 1.5], p=[.45,.35,.17,.03])
        strength = rng.uniform(.15,.65) * (1 - y/H*.7)
        c = tuple(int(v*strength) for v in (175,209,240))
        draw.ellipse((x-r,y-r,x+r,y+r), fill=c)
    canvas += np.asarray(image, dtype=np.float32)/255


def ridge(seed, level, amplitude, roughness=.55):
    rng = np.random.default_rng(seed)
    x = np.linspace(0, 1, W)
    profile = np.full(W, level, dtype=np.float32)
    for octave, n in enumerate([7,17,43,107,269]):
        knots = rng.uniform(-1,1,n)
        profile += np.interp(x,np.linspace(0,1,n),knots)*amplitude*roughness**octave
    return profile[None,:]


def mountains(canvas, mask, seed, level, amplitude, top, bottom, snow=False):
    profile = ridge(seed, level, amplitude)
    depth = np.maximum(0, Y-profile)
    region = smooth(-.0007,.0007,Y-profile)
    tex = noise(seed+100,5,12)
    # Long diagonal strata and broken gullies give the still image detail at 4K.
    strata = np.sin(X*83 + Y*37 + tex*12)*.5+.5
    relief = .76 + .24*tex + .16*strata
    ramp = smooth(0,.32,depth)
    col = rgb(top)[None,None,:]*(1-ramp[:,:,None]) + rgb(bottom)[None,None,:]*ramp[:,:,None]
    col = col*relief[:,:,None]
    if snow:
        facets = np.sin(X*61-Y*19+tex*10)*.5+.5
        cap = (1-smooth(.008,.075,depth+(.5-tex)*.09)) * smooth(.18,.68,facets)
        col = col*(1-cap[:,:,None]*.86) + rgb('#c5e6e6')*cap[:,:,None]*.86
    canvas[:] = canvas*(1-region[:,:,None]) + col*region[:,:,None]
    mask[:] *= 1-region
    return profile


def aurora():
    canvas = gradient([(0,'#040e22'),(.4,'#12374a'),(.68,'#588a93'),(1,'#0a2235')])
    sky = np.ones((H,W),dtype=np.float32)
    stars(canvas,11,900)
    glow(canvas,.72,.43,.46,.22,'#389c8a',.10)
    for j in range(3):
        curve = .20+j*.064+.085*np.sin(X*5.5+j*.6)+.038*np.sin(X*11-1)
        curtain = np.exp(-np.maximum(0,curve-Y)/(0.10+j*.025))*smooth(-.004,.012,curve-Y)
        filament = .60+.22*np.sin(X*156+j+np.sin(X*17)*4)+.12*np.sin(X*393)
        envelope = smooth(.00,.15,X)*(1-smooth(.78,1.1,X))
        light = curtain*filament*envelope*(.30-j*.055)
        canvas += light[:,:,None]*rgb(['#38e1b3','#20b9cc','#5a59b5'][j])
        edge = np.exp(-((Y-curve)/.0045)**2)*envelope*.18
        canvas += edge[:,:,None]*rgb('#72f3d0')
    mountains(canvas,sky,42,.65,.055,'#557788','#23394e',True)
    mountains(canvas,sky,30,.73,.12,'#356079','#0d243c',True)
    mountains(canvas,sky,35,.88,.08,'#284454','#0a1b2d',True)
    # Quiet foreground ice catches a little of the upper sky.
    ice = smooth(.89,1,Y)*(.5+.5*np.sin(X*4))
    canvas += ice[:,:,None]*rgb('#1a3143')*.3
    return canvas, np.stack([sky,sky*0,sky*0],axis=2)


def eclipse():
    canvas = gradient([(0,'#050913'),(.55,'#100f19'),(1,'#221a23')])
    stars(canvas,21,650)
    cx,cy,r=.64,.43,.219
    dx=(X-cx)*W/H; dy=Y-cy
    distance=np.sqrt(dx*dx+dy*dy)
    angle=np.arctan2(dy,dx)
    corona=np.exp(-np.maximum(0,distance-r)/.042)*smooth(r-.001,r+.004,distance)
    filaments=(.53+.23*np.sin(angle*39+np.sin(angle*11)*2)+.12*np.sin(angle*113))
    corona*=filaments
    canvas+=corona[:,:,None]*rgb('#f5be79')*.8
    halo=np.exp(-((distance-r)/.16)**2)*smooth(r,r+.04,distance)
    canvas+=halo[:,:,None]*rgb('#a76b56')*.12
    rim=np.exp(-((distance-r)/.0016)**2)
    canvas+=rim[:,:,None]*rgb('#fff1cf')*.9
    disk=1-smooth(r-.001,r+.001,distance)
    canvas=canvas*(1-disk[:,:,None])+rgb('#060b16')*disk[:,:,None]
    glow(canvas,cx-r/(W/H)*.72,cy+r*.69,.022,.022,'#fff0c9',1.15)
    sky=np.ones((H,W),dtype=np.float32)
    mountains(canvas,sky,76,.91,.022,'#352937','#101321')
    mountains(canvas,sky,77,.98,.04,'#191b29','#090e19')
    return canvas,np.stack([sky,sky*0,sky*0],axis=2)


def cloudsea():
    canvas=gradient([(0,'#171c49'),(.30,'#55527d'),(.51,'#e89c8f'),(.63,'#f5ba8a'),(1,'#272c59')])
    glow(canvas,.70,.49,.43,.29,'#f6a67c',.12)
    sun=np.sqrt(((X-.70)*W/H)**2+(Y-.49)**2)
    disk=1-smooth(.041,.042,sun)
    canvas=canvas*(1-disk[:,:,None])+rgb('#ffe2ac')*disk[:,:,None]
    glow(canvas,.70,.49,.075,.075,'#f3b571',.22)
    sky=np.ones((H,W),dtype=np.float32)
    mountains(canvas,sky,97,.66,.025,'#aa7f94','#55517a')
    # Bake overlapping soft cumulus domes, far to near. Lighting is evaluated
    # only in each dome's bounding box; the desktop never renders these blobs.
    cloud=np.zeros((H,W),dtype=np.float32)
    rng=np.random.default_rng(131)
    for row in range(36):
        depth=row/35
        baseline=.645+depth**1.5*.46
        radius=.012+depth**1.5*.085
        for cx in np.arange(-radius,1+radius,radius*1.15):
            cx+=rng.uniform(-.3,.3)*radius
            cy=baseline+rng.uniform(-.28,.28)*radius
            rx=radius*rng.uniform(.9,1.65)
            ry=radius*rng.uniform(.35,.72)
            x0=max(0,int((cx-rx*1.1)*W));x1=min(W,int((cx+rx*1.1)*W)+1)
            y0=max(0,int((cy-ry*1.1)*H));y1=min(H,int((cy+ry*1.1)*H)+1)
            if x0>=x1 or y0>=y1: continue
            xx=(X[y0:y1,x0:x1]-cx)/rx
            yy=(Y[y0:y1,x0:x1]-cy)/ry
            rr=xx*xx+yy*yy
            alpha=1-smooth(.70,1.05,rr)
            z=np.sqrt(np.maximum(0,1-rr))
            illumination=np.clip(-yy*.52+xx*.16+z*.65,0,1)
            shadow=rgb('#545475')*(1-depth*.28)
            bright=rgb('#f1bcac')*(1-depth*.15)
            color=shadow+(bright-shadow)*illumination[:,:,None]
            patch=canvas[y0:y1,x0:x1]
            patch[:]=patch*(1-alpha[:,:,None])+color*alpha[:,:,None]
            cloud[y0:y1,x0:x1]=np.maximum(cloud[y0:y1,x0:x1],alpha)
    sky*=1-cloud
    return canvas,np.stack([sky,cloud,cloud],axis=2)


def coast():
    canvas=gradient([(0,'#103d63'),(.45,'#167c96'),(.8,'#4ac4be'),(1,'#8cdbca')])
    n=noise(172,6,7)
    waterdetail=noise(173,6,22)
    canvas+=(waterdetail-.5)[:,:,None]*rgb('#277b91')*.16
    # A diagonal island sweeps into a sheltered, luminous bay.
    shore=.10+.52*(1-X)**1.8+.047*np.sin(X*7+1)+.015*np.sin(X*23)
    shore+=.006*np.sin(X*71)+.003*np.sin(X*151+.8)+.0015*np.sin(X*337)
    landdepth=Y-shore-.29
    land=smooth(-.001,.001,landdepth)
    shallow=np.exp(-((landdepth+.045)/.060)**2)*(1-land)
    canvas=canvas*(1-shallow[:,:,None]*.6)+rgb('#7ee3d5')*shallow[:,:,None]*.6
    sand=smooth(-.004,.004,landdepth)*(1-smooth(.025,.055,landdepth))
    canopy=noise(174,4,75)
    gy,gx=np.gradient(canopy)
    relief=np.clip(.5+(canopy-.5)*1.4-gx*35-gy*40,0,1)
    landcolor=rgb('#16493e')[None,None,:]+relief[:,:,None]*rgb('#4b7151')
    landcolor*=.8+n[:,:,None]*.4
    canvas=canvas*(1-land[:,:,None])+landcolor*land[:,:,None]
    canvas=canvas*(1-sand[:,:,None])+rgb('#eee0bc')*sand[:,:,None]
    foam=np.exp(-((landdepth+.008)/.002)**2)*.6
    canvas+=foam[:,:,None]*rgb('#def6e9')
    # A tiny sailboat makes the scale legible without cluttering the desktop.
    image=Image.fromarray(np.uint8(np.clip(canvas,0,1)*255))
    draw=ImageDraw.Draw(image)
    bx,by=int(W*.70),int(H*.43)
    draw.polygon([(bx,by-15),(bx-11,by+8),(bx,by+6)],fill='#eff5e3')
    draw.polygon([(bx+2,by-11),(bx+2,by+6),(bx+10,by+7)],fill='#d0e6df')
    draw.line([(bx-9,by+12),(bx+10,by+12)],fill='#174f62',width=2)
    canvas=np.asarray(image,dtype=np.float32)/255
    water=1-land
    return canvas,np.stack([water*0,water,shallow],axis=2)


def valley():
    canvas=gradient([(0,'#071a30'),(.36,'#214551'),(.67,'#6f9c91'),(1,'#0a252e')])
    stars(canvas,217,650)
    glow(canvas,.67,.25,.20,.23,'#79afba',.10)
    d=np.sqrt(((X-.67)*W/H)**2+(Y-.25)**2)
    moon=1-smooth(.032,.033,d)
    canvas=canvas*(1-moon[:,:,None])+rgb('#d6e5cf')*moon[:,:,None]
    sky=np.ones((H,W),dtype=np.float32)
    mountains(canvas,sky,202,.62,.045,'#5c8384','#345d65')
    mountains(canvas,sky,210,.70,.075,'#315c64','#173f4c')
    mountains(canvas,sky,215,.82,.065,'#20464c','#102e38')
    # A silver river winds through the valley and widens towards the viewer.
    river_x=.59+.10*np.sin((Y-.58)*8)
    river_width=.001+np.maximum(0,Y-.58)**2*.14
    water=np.exp(-((X-river_x)/river_width)**4)*smooth(.65,.72,Y)
    rivercolor=rgb('#659a9b')*(1-smooth(.7,1,Y)[:,:,None]*.45)
    canvas=canvas*(1-water[:,:,None])+rivercolor*water[:,:,None]
    mist=np.exp(-((Y-.74)/.06)**2)*(.5+.5*np.sin(X*6))
    canvas+=mist[:,:,None]*rgb('#477b7a')*.14
    image=Image.fromarray(np.uint8(np.clip(canvas,0,1)*255))
    draw=ImageDraw.Draw(image)
    rng=np.random.default_rng(231)
    # Individually drawn silhouettes are baked, never hundreds of QML objects.
    for side in [0,1]:
        for _ in range(150):
            x=rng.uniform(-.02,.35) if side==0 else rng.uniform(.85,1.02)
            base=.88+.13*rng.random()+.05*np.sin(x*12)
            height=rng.uniform(.025,.12)*(1 if side==0 else .75)
            px=x*W; py=base*H; ph=height*H
            c=tuple(int(v) for v in (8+rng.random()*5,27+rng.random()*7,35+rng.random()*7))
            draw.line([(px,py-ph),(px,py+3)],fill=c,width=2)
            for k in range(6):
                t=k/6
                yy=py-ph+t*ph*.83
                hw=ph*(.08+t*.17)
                draw.polygon([(px,yy),(px-hw,yy+ph*.28),(px+hw,yy+ph*.28)],fill=c)
    canvas=np.asarray(image,dtype=np.float32)/255
    return canvas,np.stack([sky,water,mist],axis=2)


SCENES={'starfield':aurora,'blackhole':eclipse,'weather':cloudsea,'underwater':coast,'forest':valley}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('themes',nargs='*',choices=list(SCENES),default=list(SCENES))
    args=parser.parse_args()
    for name in args.themes:
        canvas,mask=SCENES[name]()
        # Gentle lens shading and sub-byte dither preserve long smooth gradients.
        vignette=1-.13*np.clip(((X-.5)*1.1)**2+((Y-.48)*.85)**2,0,1)
        canvas*=vignette[:,:,None]
        rng=np.random.default_rng(800)
        canvas+=(rng.random((H,W,1),dtype=np.float32)-.5)/255
        plate=Image.fromarray(np.uint8(np.clip(canvas,0,1)*255))
        directory=ROOT/'shared/qml/wallpapers/themes'/name/'assets'
        directory.mkdir(parents=True,exist_ok=True)
        plate.save(directory/'stilllight.jpg',quality=94,subsampling=0,progressive=False)
        plate.resize((640,360),Image.Resampling.LANCZOS).save(directory/'preview.png',optimize=True)
        Image.fromarray(np.uint8(np.clip(mask,0,1)*255)).resize((1280,720),Image.Resampling.LANCZOS).save(directory/'motion-mask.png',optimize=True)
        print(f'{name}: plate + motion mask + preview',flush=True)


if __name__=='__main__':
    main()
