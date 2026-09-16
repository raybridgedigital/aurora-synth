#!/usr/bin/env python3
"""Author and package Prism: 100 additional factory performances for Aurora 0.9."""
import hashlib
import json
import re
import zipfile
from collections import Counter
from pathlib import Path
from assemble_patch_bank import DEFAULTS as CLASSIC_DEFAULTS, RANGES as CLASSIC_RANGES, INTEGER as CLASSIC_INTEGER, checked

ROOT = Path(__file__).resolve().parent.parent
CATEGORIES = ['Pads','Bass','Leads','Keys','Plucks','Arps','Textures','Organs','Brass & Strings','Splits']
# Name | primary table | secondary table | position | warp mode | cutoff | playing character
# Table pairs and musical identities are authored individually, not shuffled preset copies.
DESIGNS = {
'Pads': '''Opal Weather|0|16|.28|1|2100|Soft spectral clouds; hold widely spaced chords and open the wheel.
Cathedral of Ice|5|18|.61|0|5100|A luminous choir over frozen air; let the long release overlap.
Saffron Sky|2|19|.42|1|1700|Amber warmth with a drifting dusk overtone; play low fifths.
Velour Eclipse|1|7|.19|0|1100|A dark hollow cushion with a slow-moving vowel center.
Pearl Current|16|22|.72|3|3800|Silvery motion under a soft tine shimmer; sparse major sevenths bloom.
Moonlit Orchard|23|4|.35|1|2900|Flute air meets a distant choir; use the wheel for a wider vowel.
Rose Quartz Halo|3|17|.52|0|3300|A rounded pulse bed with an organ-like upper halo.
Blue Hour Cinema|19|0|.81|1|1500|Slow cinematic swells with a dark foundation and brightening wheel.
Porcelain Clouds|18|5|.47|3|4600|Delicate airy harmonics that unfold without a sharp attack.
Solar Linen|2|16|.66|2|2700|Warm woven harmonics with restrained sync edges and spacious tails.''',
'Bass': '''Basalt Engine|20|12|.22|1|650|A compact round foundation with acid teeth; play short low octaves.
Rubber Comet|21|3|.58|1|1200|Elastic talking bass with a short glide between connected notes.
Chrome Undertow|15|20|.67|3|1800|A gritty digital upper edge anchored by a centered sine sub.
Cellar Pulse|3|1|.31|0|470|Dry narrow pulse bass for steady eighth-note lines.
Acid Marmalade|12|21|.76|1|2100|Resonant citrus bite; wheel motion bends the harmonic edge.
Graphite Growl|14|6|.49|3|1400|Folded grit and a reed growl; leave space between low notes.
Submarine Velvet|20|0|.12|0|360|A restrained deep bass for gentle accompaniment; very little room.
Voltage Slug|13|3|.88|2|2600|A cutting sync bass with a fast envelope and brief glide.
Maroon Circuit|7|21|.44|1|900|Hollow woody bass with a rounded attack and vowel inflection.
Neon Taproot|2|15|.63|3|1600|Bright root notes with a grainy crown; velocity adds bite.''',
'Leads': '''Laser Calligraphy|13|10|.71|2|6500|A sharp singing line with sync edge; connect notes for glide.
Apricot Ribbon|0|21|.36|1|2800|Rounded legato melody with a gently bending harmonic ribbon.
Glass Falcon|10|5|.64|0|8800|Clear high-register calls with a choral trace in the tail.
Vermilion Talkbox|6|4|.54|1|4300|A forward vowel solo; the wheel opens its mouth.
Liquid Antenna|14|23|.27|3|5100|Folded liquid overtones riding a breathy foundation.
Orbiting Reed|6|1|.18|0|3400|A compact reed melody with subtle pitch movement.
Silver Lasso|11|13|.79|2|7300|Metallic sync lead for wide interval jumps and short bends.
Honeycomb Solo|3|0|.46|1|2400|Soft-edged pulse melody with warm filter articulation.
Ultraviolet Kite|15|18|.83|3|9100|An electric airy lead; wheel pressure reveals digital grain.
Singing Copper|8|7|.57|0|5600|Bell-metal color softened into a sustained hollow solo.''',
'Keys': '''Felt Observatory|22|0|.21|0|2200|A quiet synthetic felt key with a soft tine afterglow.
Prism Suitcase|22|2|.59|1|3900|Compact electric-key color; play syncopated midrange chords.
Glasshouse Rhodes|10|22|.43|0|6200|Glassy synthetic keys with a rounded body and spacious decay.
Wooden Mercury|6|21|.32|1|2700|Woody reed keys with a rubbery strike and quick release.
Celesta Transit|9|23|.71|0|8900|Bright toy-celesta points that sparkle in the upper register.
Amber Wurli Dream|1|14|.38|3|3100|Warm slightly folded electric keys for mellow chord stabs.
Raindrop Terminal|18|10|.82|1|7400|Airy droplets with a clean attack and short echo.
Tape Conservatory|17|0|.24|0|1800|Dark organ-tine keys with gentle stereo drift.
Ceramic Lounge|11|22|.56|3|4900|A ceramic strike over soft tines; try sparse minor ninths.
Starlight Clavinet|3|12|.69|1|5600|Short bright pulse keys with a nasal spectral bite.''',
'Plucks': '''Origami Koto|6|10|.33|1|5400|A papery reed-metal pluck; leave the small echo to answer.
Diamond Dew|10|18|.77|0|11200|Tiny crystalline points for high arpeggiated figures.
Cactus Harp|12|23|.45|1|4600|A dry prickly attack that softens into breathy harmonics.
Rubber Kalimba|21|22|.29|3|3200|Rounded thumb-piano-like plucks with a rubbery low body.
Bronze Fireflies|11|8|.62|0|6900|Warm bell-metal flashes with brief ringing tails.
Paper Marimba|1|6|.16|0|2400|Muted woody pulses for tight rhythmic accompaniment.
Hologram Strings|13|16|.86|2|8300|Bright synthetic string plucks with shimmering delayed outlines.
Coral Pizzicato|2|9|.41|1|4100|A soft bowed-color pluck for playful midrange phrases.
Clockwork Seeds|15|3|.68|3|6100|Grainy percussive seeds that reveal more edge at higher velocity.
Snowglass Harp|5|10|.51|0|9600|Delicate choir-glass plucks with a luminous fading resonance.''',
'Arps': '''Tesseract Steps|13|10|.64|2|6700|An ascending geometric pattern; hold a triad and move the wheel.
Peach Sequencer|0|21|.34|1|2800|A soft bouncing sequence with rounded rubber harmonics.
Crystal Turnstile|10|9|.81|0|9100|Descending glass steps with a clear metallic afterimage.
Midnight Conveyor|15|1|.22|3|1600|Dark digital machinery; low minor chords create a steady pulse.
Vowel Carousel|4|6|.57|1|3900|A turning vocal sequence whose mouth moves independently of the notes.
Tin Rocket Parade|8|13|.73|2|7200|Fast metal-edged launches with a crisp gate and sync accents.
Moss Code|17|23|.26|0|2300|Gentle organ-flute patterns with a leafy soft attack.
Lemon Staircase|12|3|.48|1|4800|Acid-colored steps with a narrow pulse center.
Satellite Beads|18|22|.69|3|5800|Airy beads alternating through the held chord and octaves.
Prismatic Dominoes|2|11|.91|0|8100|Bright falling dominoes of bronze and warm spectrum.''',
'Textures': '''Radio Aurora|15|18|.66|3|5100|A slowly shifting digital haze; hold one note and listen to its grain.
Glacier Breath|18|5|.23|0|2600|Cold breath around a distant choir; low fifths create space.
Rust Garden|11|14|.74|3|3400|Weathered metallic harmonics with slow folded movement.
Ghosts in Glass|5|10|.54|1|6200|A glass choir moving between hollow and luminous colors.
Ocean of Wires|13|16|.38|2|4400|Soft electrical turbulence over a smooth atmospheric floor.
Insect Lanterns|12|9|.87|3|7600|Small restless spectral flickers inside a sustained texture.
Velvet Radio Fog|7|19|.17|1|1300|Low hollow fog with a slowly rotating vowel shadow.
Magnetic Snow|18|15|.79|0|8700|Air and digital dust with irregular filter movement.
Temple of Satellites|17|8|.45|2|3100|Organ pillars with distant metallic partials and a long room.
Bioluminescent Ink|16|4|.61|1|4200|A luminous vocal wash that changes color under the wheel.''',
'Organs': '''Bamboo Chapel|23|17|.31|0|3900|Flute pipes and frozen ranks; hold close chords for a gentle chapel.
Neon Drawbars|17|3|.68|1|6300|Bright synthetic ranks with a lively chorus and wheel-driven color.
Reed Cathedral|6|1|.49|0|4500|Full reed-organ color with a woody low register.
Copper Gospel|8|17|.58|3|5700|Metal-tinted organ stabs with a warm sustained floor.
Moon Pump Organ|7|0|.19|1|1900|A dark breathing organ for quiet sustained harmony.
Ice Harmonium|5|23|.72|0|7100|High airy ranks blended with a crystalline choir.
Transistor Orchard|3|15|.44|3|3400|Compact electric-organ grit with a slightly nasal top.
Solar Basilica|2|17|.83|2|8200|Brilliant spectral pipes for open voicings and broad chord changes.
Willow Reeds|6|23|.27|0|2700|Soft reed and flute stops with a calm stereo shimmer.
Violet Vox|4|7|.56|1|4800|A vowel-colored organ that opens into a talking choir.''',
'Brass & Strings': '''Copper Cinematheque|2|8|.63|1|4300|A synthetic brass swell with a copper edge and broad ensemble body.
Silken Violas|1|16|.28|0|2400|Soft ensemble strings for midrange legato chords.
Solar Trombone|3|11|.46|2|3200|Round low brass with a controlled sync rasp on strong notes.
Glass Violins|10|0|.71|0|7600|Luminous synthetic strings with fine glass harmonics.
Ochre Horns|0|6|.37|1|2800|Warm rounded horns with a gentle reed-shaped formant.
Chrome Chamber|14|17|.59|3|5200|A small electric string ensemble with folded metallic tension.
Velvet Cello Choir|7|19|.21|0|1600|Dark cello-like harmony blended with a distant vocal layer.
Radiant Fanfare|12|2|.84|2|6800|Bright synthetic brass attacks for short triumphant chords.
Paper String Quartet|1|23|.42|1|3600|A dry delicate string color with a breathy upper line.
Bronze Horizon Ensemble|11|16|.67|3|4700|Broad bronze-edged ensemble swells that fade into a soft cloud.''',
'Splits': '''Basement and Stars|20|10|.28|0|900|Below C4: deep round bass. C4 and above: clear glass keys.
Rubber and Rain|21|18|.57|1|1500|Below C4: elastic bass. Above: airy droplet plucks.
Cellar and Cathedral|3|5|.36|0|800|Below C4: dry pulse bass. Above: a slow luminous choir pad.
Acid and Ivory|12|22|.73|1|2200|Below C4: resonant acid bass. Above: soft electric keys.
Reed and Ribbon|6|0|.41|1|1300|Below C4: woody bass. Above: a smooth gliding lead.
Graphite and Glass|14|9|.62|3|1800|Below C4: folded gritty bass. Above: ringing celesta-like keys.
Sub and Satellites|20|13|.19|2|650|Below C4: centered sub bass. Above: a sparkling arpeggiator.
Maroon and Moonlight|7|16|.48|0|1100|Below C4: hollow bass. Above: an evolving atmospheric pad.
Copper and Clouds|8|19|.66|3|1700|Below C4: metallic bass pulse. Above: soft cinematic clouds.
Root and Willow|2|23|.33|1|1000|Below C4: warm bass. Above: a gentle flute-organ voice.'''
}
DEFAULTS = CLASSIC_DEFAULTS + [0,.5,0,1,8,.6,0,0,0,0,2] + [0]*14
RANGES = CLASSIC_RANGES + [(0,4),(.05,.95),(0,1),(1,4),(0,30),(0,1),(0,1),(0,36),(0,2),(0,2),(0,24)] + [(0,1),(0,24),(0,1),(0,3),(0,1),(0,1),(0,1)]*2
INTEGER = CLASSIC_INTEGER | {33,36,39,41,43,44,45,47,51,52,54}

def route(source=0,destination=0,amount=0,target=4):
    return dict(enabled=amount!=0,source=source,destination=destination,target=target,cc=1,amount=round(amount,4))

def voice(category,index,t1,t2,position,warp,cutoff):
    v=dict(enumerate(DEFAULTS))
    v.update({0:1,3:[.24,.38,.52,.66,.43][index%5],4:[3,7,0,11,5][index%5],5:0,6:0,7:cutoff,8:.1+.025*(index%4),13:.66,16:[.073,.11,.19,.29,.43][index%5],17:.015,18:0,19:index%3,20:.15,21:.025,29:[.13,.23,.37,.61,.89][index%5],30:.025,31:2,33:(index+1)%4,34:.28+.045*index,36:1,37:5+index,38:.55,43:2,44:1,45:t1,46:position,47:warp,48:0 if warp==0 else .16+.035*(index%6),49:0,50:.12,51:1,52:t2,53:round(1-position*.72,3),54:(warp+1)%4,55:.12,56:.17,57:.2})
    envelope={
        'Pads':(.55+.14*index,1.4,.82,2.1+.16*index),
        'Bass':(.002,.13+.027*index,.42+.035*(index%5),.09+.016*index),
        'Leads':(.007+.003*(index%4),.3,.76,.19+.037*index),
        'Keys':(.004+.002*(index%3),.65+.17*index,.13+.035*(index%4),.35+.09*index),
        'Plucks':(.001,.15+.054*index,.015,.19+.033*index),
        'Arps':(.002,.11+.024*index,.22,.12+.018*index),
        'Textures':(1.1+.18*index,2.2,.84,2.8+.2*index),
        'Organs':(.015+.008*(index%3),.15,.93,.14+.023*index),
        'Brass & Strings':(.09+.04*index,.55,.78,.55+.13*index),
        'Splits':(.003,.22,.63,.18),
    }[category]
    v.update(zip([9,10,11,12],envelope))
    if category in ['Pads','Brass & Strings']:
        v.update({36:2,38:.78,50:.7,57:.85,20:.22,13:.7})
    if category=='Bass':v.update({15:-12,5:.22,41:2,42:.018+.008*(index%5),50:0,57:0,20:.38,21:.08+.015*(index%4),8:.23+.05*(index%5),30:0})
    if category=='Leads':v.update({41:2,42:.028+.012*(index%5),43:7 if index in [0,6] else 2,20:.27,36:2 if index%3==0 else 1,21:.08})
    if category=='Keys':v.update({20:.32,50:0,57:0,21:.035})
    if category=='Plucks':v.update({20:.5,50:0,57:0,8:.2})
    if category=='Arps':v.update({22:1,23:[2,1,2,0,1,2,0,2,1,2][index],24:index%4,25:2 if index%3 else 1,26:.38+.055*(index%7),20:.36,50:0,57:0})
    if category=='Textures':v.update({6:.025+.008*(index%5),16:.031+.014*index,29:.067+.023*index,19:4 if index in [0,5,7] else 0,17:.06,30:.13,36:2,38:.85,50:1,57:1,13:.63})
    if category=='Organs':v.update({20:0,17:.015,30:.08,50:0,57:0,5:.1})
    return {str(k):round(value,5) for k,value in v.items()}

def assemble():
    patches=[]
    for category in CATEGORIES:
        for i,line in enumerate(DESIGNS[category].splitlines()):
            name,a,b,pos,warp,cutoff,detail=line.split('|')
            a,b,warp=int(a),int(b),int(warp);pos,cutoff=float(pos),float(cutoff)
            primary=voice(category,i,a,b,pos,warp,cutoff)
            active=[primary]
            if category in ['Pads','Textures','Brass & Strings']:
                upper=voice(category,(i+3)%10,b,a,min(.94,pos+.13),0,cutoff*1.35)
                primary['13']=.49;upper.update({'13':.20,'15':12 if category!='Brass & Strings' else 0,'14':.25,'36':1,'9':min(6,primary['9']*1.4),'12':primary['12']+.3})
                primary['14']=-.12;active.append(upper)
            if category=='Splits':
                primary=voice('Bass',i,a,20,pos,warp,cutoff);primary.update({'28':59,'13':.64})
                topCategory=['Keys','Plucks','Pads','Keys','Leads','Keys','Arps','Pads','Pads','Organs'][i]
                upper=voice(topCategory,i,b,22 if i%2==0 else 0,pos,0,3200+i*470)
                upper.update({'27':60,'13':.57,'15':0});active=[primary,upper]
            layers=[{'values':v} for v in active]
            while len(layers)<4:layers.append({'values':{str(k):value if k else 0 for k,value in enumerate(DEFAULTS)}})
            ambient=category in ['Pads','Textures']
            dry=category=='Bass'
            globals_=[.25,[84,96,108,116,124,132,92,102,112,128][i],0 if dry else (.19 if ambient else .10+.015*(i%4)),.27+.025*(i%4),.035 if dry else (.31 if ambient else .13+.018*(i%5)),0 if dry else .08+.018*(i%4)]
            sound=[]
            for j in range(4):
                slots=[route() for _ in range(6)]
                if j<len(active):
                    slots[0]=route(0,12,.12+.025*(i%5) if ambient else .04+.013*(i%4))
                    slots[1]=route(1,13,-.09-.017*(i%4))
                    slots[2]=route(2,14,.16 if category in ['Keys','Plucks','Bass','Arps'] else .07)
                    if category=='Textures':slots[3]=route(1,0,.08)
                sound.append(slots)
            performance=[route(0,12,.26),route(1,0,.12),route(2,14,.22),route(),route(),route()]
            patch=dict(id='prism-'+re.sub('[^a-z0-9]+','-',name.lower()).strip('-'),name=name,category=category,detail=detail+' Prism collection · wheel scans the wave; velocity opens the filter.',layers=layers,globals=globals_,macros=[.5]*8,phaserMix=0 if dry else (.11 if i in [2,5,8] else 0),fx={'7':.08+.033*i,'8':.6,'9':.18,'10':.13+.021*i,'11':.7,'12':.72 if ambient else .4,'13':3.2 if ambient else .85+.12*i,'14':[0,1,4,2,0,6,1,4,2,0][i]},soundMatrix=sound,performanceMatrix=performance)
            patches.append(patch)
    assert len(patches)==100 and Counter(p['category'] for p in patches)==Counter({c:10 for c in CATEGORIES})
    old=json.loads((ROOT/'Resources/Aurora100.json').read_text())
    assert len({p['id'] for p in old+patches})==200
    assert len({p['name'].casefold() for p in old+patches})==200
    signatures=set()
    for p in patches:
        for layer in p['layers']:
            assert len(layer['values'])==58
            for k,v in layer['values'].items():checked(v,RANGES[int(k)],p['name']+'/'+k,int(k) in INTEGER)
        signature=hashlib.sha256(json.dumps([p['layers'],p['soundMatrix'],p['globals'][1:]],sort_keys=True).encode()).hexdigest()
        assert signature not in signatures;signatures.add(signature)
    patches.sort(key=lambda p:(CATEGORIES.index(p['category']),p['name']))
    (ROOT/'Resources/AuroraPrism100.json').write_text(json.dumps(patches,indent=2)+'\n')
    output=ROOT/'Patch Banks';output.mkdir(exist_ok=True)
    with zipfile.ZipFile(output/'Aurora Prism 100 Patches.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for p in patches:archive.writestr(f"Aurora Prism 100/{p['category']}/{p['id']}.aurora.json",json.dumps(p,indent=2)+'\n')
    lines=['# Aurora Prism — 100 new patches','','Ten sounds in each of ten categories. All appear under **Aurora** alongside your existing sounds. Search “Prism” to browse this collection. Requires Aurora 0.9 or newer.','','Move the mod wheel to scan the primary wave; velocity opens the filter and channel pressure adds warp. Splits divide at MIDI 60 (C4). Layer octaves preserve the authored register. These are synthesized interpretations rather than acoustic samples.','']
    for category in CATEGORIES:
        lines += ['## '+category,'','| Patch | Playing notes |','|---|---|']
        lines += [f"| {p['name']} | {p['detail'].split(' Prism collection')[0]} |" for p in patches if p['category']==category]
        lines.append('')
    (output/'Aurora Prism 100 Catalog.md').write_text('\n'.join(lines)+'\n')
    print('Assembled Prism: 100 unique performances, ten categories, 24 factory wavetables.')

if __name__=='__main__':assemble()
