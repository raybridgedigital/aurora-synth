#!/usr/bin/env python3
"""Compile individually authored Nova performances, validate and package them."""
import hashlib
import json
import math
import re
import zipfile
from collections import Counter
from pathlib import Path
from assemble_prism_bank import DEFAULTS, RANGES, INTEGER, CATEGORIES, route
from assemble_patch_bank import checked
from nova_atmospheres import DESIGNS as ATMOSPHERES
from nova_performances import DESIGNS as PERFORMANCES
from nova_rhythmic import DESIGNS as RHYTHMIC

ROOT = Path(__file__).resolve().parent.parent
GLOBAL_RANGES = [(0,1),(30,240),(0,.6),(0,.75),(0,.75),(0,.6),(0,1),(.03,5),(0,1),(-.85,.85),(.03,5),(0,1),(0,1),(.2,8),(0,7)]
ENVELOPES = {
    'pad':(.8,1.6,.85,2.6), 'texture':(1.2,2,.8,3),
    'bass':(.003,.25,.62,.18), 'lead':(.008,.3,.8,.25),
    'keys':(.004,1.15,.18,.7), 'pluck':(.001,.36,.02,.3),
    'arp':(.003,.2,.3,.18), 'organ':(.018,.12,.95,.28),
    'brass':(.07,.42,.76,.6), 'string':(.24,.8,.8,1.4),
}
SENDS = {'bass':(0,.04),'lead':(.48,.3),'keys':(.36,.46),'pluck':(.65,.5),'arp':(.6,.28),'pad':(.4,.9),'texture':(.6,1),'organ':(.2,.6),'brass':(.2,.45),'string':(.3,.8)}

def shape(name):
    shapes = {
        'Swell':[(0,0,-.25),(1,1)], 'Fade Out':[(0,1,.35),(1,0)],
        'Triangle':[(0,0),(.5,1),(1,0)],
        'Sine':[(i/12,(1-math.cos(i/12*2*math.pi))/2) for i in range(13)],
        'Pulse':[(0,1),(.49,1),(.5,0),(.99,0),(1,1)],
        'Pluck':[(0,0),(.025,1,-.6),(.6,.05),(1,0)],
        'Double Swell':[(0,0,.2),(.35,1),(.5,.15,.2),(.85,1),(1,0)],
        'Staircase':[(0,0),(.24,0),(.25,.33),(.49,.33),(.5,.66),(.74,.66),(.75,1),(1,1)],
        'Heartbeat':[(0,0),(.12,1),(.22,0),(.32,.65),(.44,0),(1,0)],
        'Bounce':[(0,1,-.4),(.3,0),(.43,.65,-.4),(.65,0),(.75,.35,-.4),(.9,0),(.95,.12),(1,0)],
        'Ripple':[(0,.5),(.14,.8),(.28,.3),(.42,1),(.56,.1),(.7,.75),(.84,.35),(1,.5)],
        'Duck & Rise':[(0,1),(.06,.05,.4),(.8,1),(1,1)],
        'Ratchet':[(0,0),(.02,1,-.4),(.24,0),(.25,0),(.27,.85,-.4),(.49,0),(.5,0),(.52,.7,-.4),(.74,0),(.75,0),(.77,.55,-.4),(1,0)],
        'Bloom':[(0,0,.55),(.48,.85,-.4),(.65,1),(.78,1,.45),(1,0)],
        'Sample & Hold':[(0,.25),(.15,.25),(.16,.9),(.32,.9),(.33,.4),(.49,.4),(.5,.7),(.65,.7),(.66,.1),(.82,.1),(.83,1),(.99,1),(1,.25)],
    }
    shapes['Descending Steps']=[(p[0],1-p[1]) for p in shapes['Staircase']]
    return [dict(x=round(p[0],7),y=round(p[1],7),curve=p[2] if len(p)>2 else 0) for p in shapes[name]]

def motion(recipe):
    ranges=[(0,1),(400,6000),(0,12),(-1,1),(0,1),(0,1),(0,1),(0,1)]
    routes=[dict(enabled=False,minimum=a,maximum=b,inverted=False) for a,b in ranges]
    for destination,values in recipe.get('motion',{}).items():
        a,b,*inverse=values
        routes[int(destination)]=dict(enabled=True,minimum=a,maximum=b,inverted=bool(inverse and inverse[0]))
    return dict(enabled=bool(recipe.get('motion')),loop=recipe.get('loop',False),seconds=recipe.get('seconds',4),
                beats=recipe.get('beats'),grid=16 if recipe.get('beats') else 0,points=shape(recipe.get('shape','Swell')),routes=routes)

def layer(recipe,index):
    role=recipe['role'];v=dict(enumerate(DEFAULTS))
    v.update({0:1,3:.35,4:3,5:0,6:0,7:recipe['cutoff'],8:.16,13:recipe['level'],14:recipe.get('pan',0),15:12*recipe.get('octave',0),
              16:.11+index*.047,17:.018,18:0,19:0,20:.12,21:.035,29:.19+index*.081,30:.02,31:2,33:2,
              34:.37,35:0,36:recipe.get('unison',1),37:8,38:.55,43:2,
              44:1,45:recipe['t1'],46:recipe['pos'],47:1,48:.14,49:0,50:.18,
              51:1,52:recipe['t2'],53:1-recipe['pos']*.7,54:0,55:0,56:.17,57:.15})
    v.update(zip((9,10,11,12),ENVELOPES[role]))
    if role in ('bass','lead'):v.update({41:2,42:.035 if role=='bass' else .075,50:0,57:0})
    if role=='bass':v.update({17:0,30:0,20:.25,38:0})
    if role in ('keys','pluck','arp'):v.update({50:0,57:0,20:.32})
    if role=='arp':v.update({22:1,23:2,24:0,25:2,26:.55})
    if role in ('pad','string','texture'):v.update({50:.7,57:.8})
    if 'classic' in recipe:v.update({1:recipe['classic'],2:recipe['classic'],44:0,51:0,35:.12 if recipe['classic']==3 else 0})
    v.update({27:recipe.get('key_low',0),28:recipe.get('key_high',127)})
    v.update({int(k):value for k,value in recipe.get('params',{}).items()})
    # A warp envelope must address an active warp algorithm.
    for target,mode in ((6,47),(7,54)):
        if target in recipe.get('motion',{}) and v[mode]==0:v[mode]=1
    return {'values':{str(k):round(value,7) for k,value in v.items()}}

def normalized(parameter,value,shared=False):
    low,high=(GLOBAL_RANGES if shared else RANGES)[parameter]
    value=max(low,min(high,value))
    return math.log(value/low)/math.log(high/low) if not shared and parameter in (7,9,10,12,16,29) else (value-low)/(high-low)

def macros(patch,recipes,names):
    """Eight disjoint macro assignments; all authored values are their midpoints."""
    result={i:dict(name=n,routes=[]) for i,n in enumerate([*names,'Drift','Room','Contour','Release','Width','Echo'])}
    def add(m,layer,p,width,reverse=False):
        value=patch['layers'][layer]['values'][str(p)] if layer>=0 else (patch['globals'][p] if p<6 else patch['phaserMix'] if p==6 else patch['fx'][str(p)])
        center=normalized(p,value,layer<0);span=min(width,center,1-center)
        if span<.00001:return
        a,b=center-span,center+span
        result[m]['routes'].append(dict(id=f'nova-m{m}-l{layer}-p{p}',target=dict(layer=layer,parameter=p),**{'from':b if reverse else a,'to':a if reverse else b}))
    def from_saved(m,targets):
        # A dry patch starts this macro at zero, so an effect can be introduced
        # without an audible jump when the saved position is touched.
        patch['macros'][m]=0
        result[m]['routes']=[]
        for p,maximum in targets:
            current=patch['globals'][p] if p<6 else patch['fx'][str(p)]
            result[m]['routes'].append(dict(id=f'nova-m{m}-shared-p{p}',target=dict(layer=-1,parameter=p),**{'from':normalized(p,current,True),'to':normalized(p,maximum,True)}))
    for i,recipe in enumerate(recipes):
        v=patch['layers'][i]['values'];shadow=set(recipe.get('motion',{}))
        if v['44'] and 4 not in shadow:add(0,i,46,.27)
        elif v['47'] and v['44'] and 6 not in shadow:add(0,i,48,.12)
        elif not v['44']:add(0,i,34,.2)
        else:add(0,i,3,.25)
        if 1 not in shadow:add(0,i,7,.14)
        add(1,i,13,min(.18,v['13']*.6),reverse=len(recipes)>1 and i==0)
        add(2,i,16,.12);add(2,i,29,.12)
        add(4,i,20,.09)
        if 0 not in shadow:add(4,i,9,.1)
        add(5,i,12,.13)
        if recipe['role']!='bass' and v['36']>1:add(6,i,38,.22)
    add(2,-1,7,.09)
    add(3,-1,4,.16);add(3,-1,12,.18);add(3,-1,13,.12)
    add(7,-1,2,.13);add(7,-1,3,.13)
    add(6,-1,5,.1);add(6,-1,11,.2)
    if patch['globals'][2]==0:from_saved(7,[(2,.18),(3,.35)])
    if patch['globals'][4]==0:from_saved(3,[(4,.25),(12,.65),(13,2.5)])
    if patch['globals'][5]==0 and not any(r['target']['layer']>=0 for r in result[6]['routes']):from_saved(6,[(5,.16),(11,.7)])
    if not result[4]['routes']:add(4,0,8,.13)
    return {str(k):v for k,v in result.items()}

def assemble():
    designs=ATMOSPHERES+PERFORMANCES+RHYTHMIC
    assert len(designs)==100
    patches=[]
    for d in designs:
        recipes=d['layers'];assert 1<=len(recipes)<=4
        layers=[layer(r,i) for i,r in enumerate(recipes)]
        while len(layers)<4:layers.append({'values':{str(i):v if i else 0 for i,v in enumerate(DEFAULTS)}})
        ambient=d['category'] in ('Pads','Textures');bass=d['category']=='Bass'
        fx={2:.1 if bass else .18,3:.28,4:.12 if bass else .34 if ambient else .22,5:.035 if bass else .1,6:.045 if bass else .12,7:.16,8:.48,9:.12,10:.19,11:.55,12:.7 if ambient else .45,13:3 if ambient else 1.6,14:4}
        fx.update({int(k):v for k,v in d.get('fx',{}).items()})
        sounds=[]
        for i,r in enumerate(recipes):
            wt=layers[i]['values']['44']>0
            sounds.append([route(0,12,.055) if wt else route(0,0,.025),route(1,13,-.04) if wt else route(1,3,.035),route(2,0,.05),route(),route(),route()])
        while len(sounds)<4:sounds.append([route() for _ in range(6)])
        # Performance assignments target specific active layers, including classic voices.
        wt_index=next((i for i in range(len(recipes)) if layers[i]['values']['44']),0)
        perf=[route(0,12 if layers[wt_index]['values']['44'] else 0,.23,wt_index),route(1,0,.08),route(2,14 if layers[wt_index]['values']['44'] else 0,.12,wt_index),route(),route(),route()]
        sends=[dict(zip(('delay','reverb'),r.get('sends',SENDS[r['role']]))) for r in recipes]
        if fx[2]==0 and not any(s['delay'] for s in sends):sends[0]['delay']=.2
        if fx[4]==0 and not any(s['reverb'] for s in sends):sends[0]['reverb']=.25
        sends += [dict(delay=0,reverb=0) for _ in range(4-len(sends))]
        motion_=[motion(r) for r in recipes]+[motion({}) for _ in range(4-len(recipes))]
        patch=dict(id='nova-'+re.sub('[^a-z0-9]+','-',d['name'].lower()).strip('-'),name=d['name'],category=d['category'],
                   detail=d['detail']+f" Nova collection · X: {d['xy_names'][0]} (timbre); Y: {d['xy_names'][1]} (layer balance). Wheel adds color; pressure adds edge.",
                   layers=layers,globals=[.25,d['tempo'],fx[2],fx[3],fx[4],fx[5]],macros=[.5]*8,phaserMix=fx[6],fx={str(k):v for k,v in fx.items() if k>=7},
                   soundMatrix=sounds,performanceMatrix=perf,motion=motion_,sends=sends,
                   xy=dict(x=dict(macro=0,start=0,end=1),y=dict(macro=1,start=0,end=1)))
        patch['customMacros']=macros(patch,recipes,d['xy_names'])
        patches.append(patch)
    validate(patches)
    patches.sort(key=lambda p:(CATEGORIES.index(p['category']),p['name'].casefold()))
    (ROOT/'Resources/AuroraNova100.json').write_text(json.dumps(patches,indent=2)+'\n')
    output=ROOT/'Patch Banks'
    with zipfile.ZipFile(output/'Aurora Nova 100 Patches.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for p in patches:
            info=zipfile.ZipInfo(f"Aurora Nova 100/{p['category']}/{p['id']}.aurora.json",date_time=(2026,9,17,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(info,json.dumps(p,indent=2)+'\n')
    lines=['# Aurora Nova — 100 new performances','','Search **Nova** in the Aurora sound library. Ten patches per category; requires Aurora 0.15 or newer. Every performance has eight custom macros, an assigned XY pad, independent motion envelopes and layer FX sends. No external samples required.','','X explores timbre; Y changes the balance between the layers (single-layer voices change body level). The remaining macros are Drift, Room, Contour, Release, Width and Echo. Initial macro positions reproduce the authored sound. C/D are used where they add a distinct musical voice.','']
    for category in CATEGORIES:
        lines += ['## '+category,'','| Patch | Layers | Playing notes |','|---|---|---|']
        for p in patches:
            if p['category']==category:lines.append(f"| {p['name']} | {sum(l['values']['0'] for l in p['layers'])} | {p['detail']} |")
        lines.append('')
    (output/'Aurora Nova 100 Catalog.md').write_text('\n'.join(lines)+'\n')
    print('Assembled Nova: 100 individually authored performances, 800 custom macros, ten categories.')
    print('Layer usage: '+str(Counter(sum(l['values']['0'] for l in p['layers']) for p in patches)))

def validate(patches):
    assert Counter(p['category'] for p in patches)==Counter({c:10 for c in CATEGORIES})
    existing=json.loads((ROOT/'Resources/Aurora100.json').read_text())+json.loads((ROOT/'Resources/AuroraPrism100.json').read_text())
    assert len({p['name'].casefold() for p in existing+patches})==300,'Duplicate name'
    assert len({p['id'] for p in existing+patches})==300,'Duplicate ID'
    fingerprints=set()
    for p in patches:
        fingerprint=hashlib.sha256(json.dumps([p['layers'],p['motion']],sort_keys=True).encode()).hexdigest()
        assert fingerprint not in fingerprints,p['name']+': duplicate sound';fingerprints.add(fingerprint)
        assert any(m['enabled'] for m in p['motion'])
        assert sum(l['values']['36'] for l in p['layers'] if l['values']['0'])<=5,p['name']+': excessive unison'
        for l in p['layers']:
            assert len(l['values'])==58
            for k,v in l['values'].items():checked(v,RANGES[int(k)],p['name']+'/'+k,int(k) in INTEGER)
            assert l['values']['27']<=l['values']['28']
        for i,v in enumerate(p['globals']):checked(v,GLOBAL_RANGES[i],p['name']+'/global'+str(i))
        for k,v in p['fx'].items():checked(v,GLOBAL_RANGES[int(k)],p['name']+'/fx'+k,int(k)==14)
        checked(p['phaserMix'],(0,1),p['name']+'/phaser')
        for sends in p['sends']:
            for v in sends.values():checked(v,(0,1),p['name']+'/send')
        for m in p['motion']:
            checked(m['seconds'],(.1,60),p['name']+'/duration')
            if m['beats'] is not None:checked(m['beats'],(.25,32),p['name']+'/beats')
            assert 2<=len(m['points'])<=16 and m['points'][0]['x']==0 and m['points'][-1]['x']==1
            for a,b in zip(m['points'],m['points'][1:]):assert b['x']-a['x']>=.0001
            for point in m['points']:
                checked(point['y'],(0,1),'point');checked(point['curve'],(-1,1),'curve')
            for r,bounds in zip(m['routes'],[(0,1),(30,18000),(-24,24),(-1,1)]+[(0,1)]*4):
                checked(r['minimum'],bounds,p['name']+'/motion');checked(r['maximum'],bounds,p['name']+'/motion');assert r['minimum']<=r['maximum']
        targets=set()
        for macro in p['customMacros'].values():
            assert macro['name'] and 1<=len(macro['routes'])<=16
            for r in macro['routes']:
                checked(r['from'],(0,1),'macro');checked(r['to'],(0,1),'macro')
                key=(r['target']['layer'],r['target']['parameter'])
                assert key not in targets,p['name']+': overlapping macros';targets.add(key)

if __name__=='__main__':assemble()
