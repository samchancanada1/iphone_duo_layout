#!/usr/bin/env python3
"""Render original, illustrative package artwork. Requires Pillow; no native captures.
Usage: python3 tool/generate_media.py [output-directory]
Fonts: system Avenir Next (macOS), or DejaVu Sans (Linux). No fonts are bundled.
"""
from pathlib import Path
from functools import lru_cache
import math
import argparse
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', nargs='?', type=Path, default=Path(__file__).resolve().parents[1] / 'doc/media')
parser.add_argument('--qa', action='store_true', help='Also render static animation keyframes for inspection.')
args = parser.parse_args()
OUT = args.output
OUT.mkdir(parents=True, exist_ok=True)
BG = '#F2F1EA'
INK = '#183B39'
MUTED = '#667C76'
TEAL = '#167D71'
PALE = '#DFEBE3'
LINE = '#CDD8CF'
ORANGE = '#ECA663'
PAPER = '#FCFDF9'
S = 2

@lru_cache(None)
def font(size, weight='regular'):
    p = Path('/System/Library/Fonts/Avenir Next.ttc')
    if p.exists():
        return ImageFont.truetype(str(p), round(size*S), index={'regular':7,'medium':5,'bold':0,'demi':2}[weight])
    for folder in ['/usr/share/fonts/truetype/dejavu','/usr/share/fonts/dejavu']:
        p = Path(folder) / ('DejaVuSans-Bold.ttf' if weight in ('bold','demi') else 'DejaVuSans.ttf')
        if p.exists(): return ImageFont.truetype(str(p),round(size*S))
    raise RuntimeError('Install Avenir Next or DejaVu Sans to generate artwork.')

class Canvas:
    def __init__(self,w,h,bg=BG):
        self.w,self.h=w,h
        self.im=Image.new('RGB',(w*S,h*S),bg)
        self.d=ImageDraw.Draw(self.im)
    def box(self,xy,fill,r=0,stroke=None,width=1):
        coords=tuple(round(n*S) for n in xy)
        if r: self.d.rounded_rectangle(coords,round(r*S),fill,stroke,round(width*S))
        else: self.d.rectangle(coords,fill,stroke,round(width*S))
    def text(self,xy,value,size=20,color=INK,weight='regular',anchor='la'):
        self.d.text(tuple(round(n*S) for n in xy),value,font=font(size,weight),fill=color,anchor=anchor)
    def line(self,points,fill=LINE,width=1):
        self.d.line([(round(x*S),round(y*S)) for x,y in points],fill,width=round(width*S),joint='curve')
    def ellipse(self,xy,fill,stroke=None,width=1):
        self.d.ellipse(tuple(round(n*S) for n in xy),fill,stroke,round(width*S))
    def poly(self,points,fill):
        self.d.polygon([(round(x*S),round(y*S)) for x,y in points],fill)
    def finish(self):
        return self.im.resize((self.w,self.h),Image.Resampling.LANCZOS)


def pill(c,x,y,text,fill=PALE,color=TEAL,size=13,pad=12,height=28):
    w=c.d.textlength(text,font=font(size,'demi'))/S+2*pad
    c.box((x,y,x+w,y+height),fill,r=height/2)
    c.text((x+pad,y+(height-size)/2-3),text,size,color,'demi')
    return w

def centered_pill(c,center,y,value,fill=PALE,color=TEAL):
    width=c.d.textlength(value,font=font(11,'demi'))/S+24
    return pill(c,center-width/2,y,value,fill,color,11,height=25)

def icon(c,x,y,kind,size=22,color=TEAL):
    # All icons are original vector primitives, independent of SF Symbols.
    a=size/22
    if kind=='grid':
        for dx in [0,12]:
            for dy in [0,12]: c.box((x+dx*a,y+dy*a,x+(dx+8)*a,y+(dy+8)*a),None,r=2*a,stroke=color,width=1.6*a)
    elif kind=='plus':
        c.line([(x+11*a,y+2*a),(x+11*a,y+20*a)],color,2*a)
        c.line([(x+2*a,y+11*a),(x+20*a,y+11*a)],color,2*a)
    elif kind=='more':
        for dx in [3,11,19]: c.ellipse((x+(dx-1.5)*a,y+9.5*a,x+(dx+1.5)*a,y+12.5*a),color)
    elif kind=='search':
        c.ellipse((x+1*a,y+1*a,x+15*a,y+15*a),None,color,1.8*a)
        c.line([(x+14*a,y+14*a),(x+21*a,y+21*a)],color,1.8*a)
    elif kind=='bookmark':
        c.line([(x+5*a,y+21*a),(x+5*a,y+2*a),(x+17*a,y+2*a),(x+17*a,y+21*a),(x+11*a,y+16*a),(x+5*a,y+21*a)],color,1.6*a)
    elif kind=='back': c.line([(x+14*a,y+3*a),(x+6*a,y+11*a),(x+14*a,y+19*a)],color,2*a)


def landscape(c,x,y,w,h):
    # Abstract original terrain illustration; no external photo assets.
    c.box((x,y,x+w,y+h),'#D7E8E2',r=12)
    c.ellipse((x+w*.68,y+h*.11,x+w*.86,y+h*.11+w*.18),'#F9CF89')
    c.poly([(x,y+h*.66),(x+w*.23,y+h*.2),(x+w*.51,y+h*.72),(x+w*.7,y+h*.45),(x+w,y+h*.8),(x+w,y+h),(x,y+h)],'#A5C6B8')
    c.poly([(x,y+h*.83),(x+w*.31,y+h*.52),(x+w*.62,y+h*.82),(x+w*.85,y+h*.52),(x+w,y+h*.67),(x+w,y+h),(x,y+h)],'#4C9784')
    c.poly([(x,y+h),(x,y+h*.91),(x+w*.32,y+h*.76),(x+w*.65,y+h*.97),(x+w*.83,y+h*.85),(x+w,y+h*.88),(x+w,y+h)],'#236A5D')
    c.line([(x+w*.4,y+h),(x+w*.48,y+h*.88),(x+w*.58,y+h*.86),(x+w*.57,y+h*.78)],'#F3DEBA',max(2,w/95))


def note(c,x,y,w,h,scale=1):
    # Content is responsive to the available pane width, just like a Flutter widget.
    p=18*scale
    c.box((x,y,x+w,y+h),PAPER,r=18*scale)
    landscape(c,x+p,y+p,w-2*p,h*.53)
    c.text((x+p,y+h*.58),'Ridge loop',23*scale,INK,'demi')
    c.text((x+p,y+h*.58+34*scale),'A little room to explore.',12*scale,MUTED)
    if h>210*scale:
        c.line([(x+p,y+h-55*scale),(x+w-p,y+h-55*scale)],LINE)
        c.text((x+p,y+h-42*scale),'6.4 km',13*scale,INK,'demi')
        c.text((x+w-p,y+h-42*scale),'Saved route',12*scale,MUTED,anchor='ra')


def route_list(c,x,y,w,h,scale=1):
    c.box((x,y,x+w,y+h),PAPER,r=18*scale)
    p=18*scale
    c.text((x+p,y+p),'Your collection',18*scale,INK,'demi')
    c.text((x+p,y+p+27*scale),'Three places. One weekend.',11*scale,MUTED)
    rowh=min(70*scale,(h-80*scale)/3)
    for i,(title,sub,color) in enumerate([('Ridge loop','6.4 km · Hiking','#BAD5C7'),('Coastal path','3.2 km · Walking','#C7DCD9'),('Forest trail','8.1 km · Hiking','#D8DDC0')]):
        yy=y+75*scale+i*(rowh+5*scale)
        if i==0: c.box((x+10*scale,yy-5*scale,x+w-10*scale,yy+rowh-2*scale),PALE,r=10*scale)
        c.box((x+p,yy+7*scale,x+p+35*scale,yy+42*scale),color,r=8*scale)
        c.line([(x+p+6*scale,yy+33*scale),(x+p+15*scale,yy+18*scale),(x+p+29*scale,yy+34*scale)],TEAL,2*scale)
        c.text((x+p+47*scale,yy+8*scale),title,13*scale,INK,'demi')
        c.text((x+p+47*scale,yy+29*scale),sub,10*scale,MUTED)


def device(c,x,y,w,h,span=0,overlay=False,sidebar=False):
    # A schematic app viewport, not a representation of final Apple hardware.
    k=w/750
    c.box((x+5*k,y+12*k,x+w+5*k,y+h+12*k),'#D6DCD3',r=37*k)
    c.box((x,y,x+w,y+h),INK,r=36*k)
    c.box((x+6*k,y+6*k,x+w-6*k,y+h-6*k),'#E9EEE6',r=31*k)
    ix=x+20*k; iy=y+20*k; iw=w-40*k
    camera=(x+w/2-25*k,y+10*k,x+w/2+25*k,y+20*k)
    c.box(camera,'#183B39',r=6*k)
    c.text((ix+8*k,iy+5*k),'FIELD NOTES',13*k,INK,'bold')
    if not sidebar:
        for i,kind in enumerate(['search','bookmark','more']): icon(c,x+w-(116-i*33)*k,iy+10*k,kind,17*k)
    else:
        c.box((x+10*k,y+59*k,x+57*k,y+h-22*k),'#D1E5DC',r=17*k)
        for i,kind in enumerate(['grid','plus','bookmark','more']): icon(c,x+23*k,y+(81+i*57)*k,kind,20*k)
    top=y+62*k; hh=h-83*k
    left=ix+(49*k if sidebar else 0)
    total=iw-(49*k if sidebar else 0)
    gap=18*k
    pw=(total-gap)*.50
    primaryw=pw+(total-pw)*span
    # Clip each pane inside the viewport while the primary expands.
    note(c,left,top,primaryw,hh,k)
    if span<1:
        sx=left+primaryw+gap
        remaining=total-primaryw-gap
        if remaining>3:
            layer=Canvas(round(w),round(h),'#E9EEE6')
            route_list(layer,0,0,(total-gap)*.50,hh,k)
            c.im.paste(layer.im.crop((0,0,round(max(0,remaining)*S),round(hh*S))),(round(sx*S),round(top*S)))
    if overlay:
        mid=x+w/2
        c.box((mid-7*k,y+54*k,mid+7*k,y+h-19*k),ORANGE,r=5*k)
        c.box((camera[0]-5*k,camera[1]-4*k,camera[2]+5*k,camera[3]+4*k),None,r=9*k,stroke=ORANGE,width=3*k)


def footer(c,w,h):
    c.line([(44,h-45),(w-44,h-45)],LINE)
    c.text((44,h-32),'ILLUSTRATED PREVIEW  /  EXPERIMENTAL',11,MUTED,'demi')
    c.text((w-44,h-32),'Not a simulator capture',11,MUTED,anchor='ra')


def hero():
    c=Canvas(1440,900)
    c.text((64,44),'iphone_duo_layout',22,INK,'bold')
    pill(c,1160,44,'FLUTTER × iOS',size=13)
    c.line([(64,94),(1376,94)],LINE)
    c.text((64,137),'More room.',68,INK,'bold')
    c.text((64,218),'Same Flutter app.',68,INK,'bold')
    c.text((67,327),'Layout adaptation for iPhone Duo.',25,MUTED,'medium')
    c.text((67,386),'Split or span your content.',23,INK,'demi')
    c.text((67,425),'Bridge native regions, hinge data',20,MUTED)
    c.text((67,455),'and system toolbar capabilities.',20,MUTED)
    for i,(n,t) in enumerate([('01','Split / span'),('02','Reserved regions'),('03','Native toolbars')]):
        yy=559+i*64
        c.ellipse((68,yy+5,96,yy+33),PALE)
        c.text((82,yy+10),n,11,TEAL,'bold',anchor='ma')
        c.text((111,yy+5),t,20,INK,'medium')
    device(c,638,406,724,373)
    pill(c,1020,345,'TWO WIDGETS · ONE APP',size=13)
    c.line([(652,376),(948,376)],LINE,2)
    c.ellipse((647,371,657,381),TEAL)
    footer(c,1440,900)
    c.finish().save(OUT/'hero.png',optimize=True)


def modes():
    c=Canvas(1440,1010)
    c.text((56,35),'Two layouts. Your Flutter content.',40,INK,'bold')
    c.text((58,96),'One app window, with two configurable presentation modes.',20,MUTED)
    for x,num,title,sub,span in [(56,'01','Split','Primary + secondary widgets',0),(754,'02','Span','Primary widget fills the container',1)]:
        pill(c,x,163,num,size=13)
        c.text((x+51,157),title,28,INK,'demi')
        c.text((x,211),sub,18,MUTED)
        device(c,x,263,630,343,span=span)
        c.box((x,648,x+630,756),INK,r=15)
        c.text((x+24,668),'NativeArrangementMode.'+title.lower(),21,'#D7F0DD','medium')
        c.text((x+24,707),'Native geometry, Flutter content' if not span else 'Flutter fills the available container',16,'#B3C9BF')
    c.line([(57,804),(1383,804)],LINE)
    c.text((58,835),'Built around native capabilities',23,INK,'demi')
    c.text((58,879),'Reserved regions',19,TEAL,'demi')
    c.text((503,879),'Hinge state & angle',19,TEAL,'demi')
    c.text((960,879),'System toolbar hosting',19,TEAL,'demi')
    footer(c,1440,1010)
    c.finish().save(OUT/'layout-modes.png',optimize=True)


def ease(t): return t*t*(3-2*t)

def animation_frame(t):
    # Intentional motion design, not a claim of native animation synchronization.
    # 0–3 split, 3–6 span, 6–9 regions, 9–12 toolbar, 12–13 reset.
    phase=0 if t<3 else 1 if t<6 else 2 if t<9 else 3 if t<12 else 0
    if t<2.4: span=0
    elif t<3.1: span=ease((t-2.4)/.7)
    elif t<5.4: span=1
    elif t<6.1: span=1-ease((t-5.4)/.7)
    else: span=0
    c=Canvas(1000,710)
    titles=['Two widgets. One app.','One widget. More room.','Make room for reserved areas.','Let iOS host the controls.']
    subtitles=['Split · native layout results position Flutter content','Span · primary content fills the available container','Reserved regions · division and occlusion','System toolbar · content and actions supplied by Flutter']
    c.text((44,30),'LAYOUT EXPLORER',12,TEAL,'bold')
    c.text((44,65),titles[phase],36,INK,'bold')
    c.text((46,120),subtitles[phase],17,MUTED)
    for i,name in enumerate(['SPLIT','SPAN','REGIONS','TOOLBAR']):
        x=45+i*230
        c.box((x,166,x+217,200),TEAL if i==phase else '#E4E8DF',r=9)
        c.text((x+109,173),name,12,PAPER if i==phase else MUTED,'demi',anchor='ma')
    device(c,99,229,802,369,span,phase==2,phase==3)
    if phase==0:
        centered_pill(c,304,616,'primary')
        centered_pill(c,696,616,'secondary')
    elif phase==1:
        centered_pill(c,500,616,'primary · full container')
    elif phase==2:
        centered_pill(c,500,616,'division + occlusion',ORANGE,INK)
    else:
        centered_pill(c,500,616,'title · icons · actions · overflow')
    footer(c,1000,710)
    return c.finish()


def gif():
    frames=[];duration=[]
    # Hold finished layouts, spend frames on only the illustrative transition.
    timeline=[(0,2000)]+[(2.4+i*.07,70) for i in range(11)]+[(3.2,2100)]+[(5.4+i*.07,70) for i in range(11)]+[(6.2,2500),(9.2,2500),(12.2,700)]
    rgb=[animation_frame(t) for t,_ in timeline]
    # A single palette keeps static text and backgrounds stable throughout GIF.
    sheet=Image.new('RGB',(500,355*4))
    for i,index in enumerate([0,12,24,25]): sheet.paste(rgb[index].resize((500,355)),(0,i*355))
    palette=sheet.quantize(colors=128,method=Image.Quantize.MEDIANCUT)
    for im,(_,ms) in zip(rgb,timeline):
        frames.append(im.quantize(palette=palette,dither=Image.Dither.NONE));duration.append(ms)
    frames[0].save(OUT/'layout-preview.gif',save_all=True,append_images=frames[1:],duration=duration,loop=0,optimize=True,disposal=1)
    # QA frames are generated only on request; they aren't package assets.
    if args.qa:
        for title,t in [('split',0),('span',3.2),('regions',6.2),('toolbar',9.2)]:
            animation_frame(t).save(OUT/(title+'-qa.png'))

hero();modes();gif()
for p in sorted(OUT.glob('*')):
    if p.suffix in ('.png','.gif'): print(p.name, p.stat().st_size, 'bytes')
