#!/usr/bin/env python3
"""Aurora Spectrum: 300 layered performances for the 126-parameter engine.

No old presets are used as input. Reproducible recipes, explicit voice roles,
center-preserving macros, and measured per-patch trims live alongside the bank.
LFO 3-5 are Matrix-only voices on a ten-slot Sound Matrix."""
import collections
import hashlib
import json
import math
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATEGORIES = ['Pads','Bass','Leads','Keys','Plucks','Arps','Textures','Organs','Brass & Strings','Splits']
NAMES = {
 'Pads': '''Apricot Solstice|Blue Silk Observatory|Cedar Halo|Dawn Through Amber|Emerald Choir|Frosted Linen|Garden Above Clouds|Honeycomb Cathedral|Indigo Lanterns|Juniper Eclipse|Kintsugi Horizon|Lavender Undertow|Moonstone Canopy|Night Ferry Lights|Opaline Distance|Peacock Nebula|Quiet Coral Reef|Rose Quartz Weather|Silver Willow|Tangerine Aurora|Ultraviolet Orchard|Violet Snowfall|Warm Polar Current|Xenon Conservatory|Yellow Moon Velvet|Zinc and Starlight|Afterglow Basilica|Breathing Porcelain|Copper Cloud Atlas|Deepwater Pearls''',
 'Bass': '''Atlas Submarine|Bronze Knuckle|Carbon Rubber|Dune Pressure|Electric Licorice|Feral Circuit|Graphite Grin|Honey Badger|Iron Orchard|Jade Undertow|Kinetic Asphalt|Low Brass Engine|Molten Espresso|Neon Caterpillar|Obsidian Spring|Plum Gravity|Quartz Bulldozer|Rust Velvet|Solar Piston|Tungsten Pulse|Ultraviolet Wobble|Vantablack Anchor|Walnut Thunder|X Ray Elastic|Yellow Jacket|Zebra Voltage|Acid Marigold|Basalt Bow|Chrome Burrow|Deep Blue Torque''',
 'Leads': '''Amber Rocket|Bluebird Relay|Copper Soprano|Dragonfly Ribbon|Electric Saffron|Fire Opal Solo|Glass Falcon|Hologram Trumpet|Iris Jetstream|Jupiter Whistle|Kestrel Chrome|Liquid Vermilion|Mercury Reed|Neon Violinist|Orange Satellite|Prismatic Scream|Quicksilver Flute|Ruby Afterburner|Solar Clarinet|Turquoise Needle|Ultraviolet Cornet|Velour Laser|Wild Tangerine|Xenon Harmonica|Yellow Comet|Zircon Singer|Arcade Firefly|Bending Brass|Crystal Oboe|Desert Siren''',
 'Keys': '''Apricot Felt|Blue Ceramic Piano|Copper Tines|Dappled Celesta|Electric Walnut|Floating Harpsichord|Glass Espresso|Honey Rhodescope|Ivory Rain|Jade Music Box|Kaleidoscope Clav|Lacquered Twilight|Moss Porcelain|Nacre Electric|Ochre Marimba|Paper Wurlitzer|Quartz Grand|Rosewood Ghost|Silver Tack|Tangerine Toyroom|Underwater Upright|Velvet Vibraphone|Willow Hammer|Xylophonic Moon|Yellow Felt Cinema|Zinc Bell Piano|Afterhours Opal|Brocade Dulcimer|Cobalt Chamber|Dewdrop Keyboard''',
 'Plucks': '''Amber Thread|Bamboo Starlings|Coral Koto|Dew on Steel|Electric Acorn|Fuchsia Pizzicato|Glass Thimble|Harp of Cinders|Iridescent Banjo|Jasmine Droplets|Kinetic Kalimba|Lemon Zither|Mica Thumbpiano|Nylon Fireworks|Opal Quills|Peach Mandolin|Quartz Raindrops|Rosegold Pinwheel|Satin Harp|Tinsel Pebbles|Ultraviolet String|Verdigris Bells|Watercolor Plectrum|Xenon Harpwire|Yellow Bamboo|Zircon Needles|Autumn Pinpricks|Bronze Snowflakes|Cerulean Lyre|Dragonfruit Chimes''',
 'Arps': '''Amber Clockwork|Blue Mosaic Steps|Copper Swallows|Dancing Marigolds|Emerald Switchboard|Firefly Counterpoint|Glass Escalator|Honeycomb Ratchet|Indigo Turnstile|Jade Carousel|Kinetic Tulips|Lunar Typewriter|Mango Polyrhythm|Neon Origami|Opal Telegraph|Peacock Sequins|Quartz Pendulum|Rosewater Motors|Saffron Satellites|Tangerine Ticker|Ultraviolet Gears|Violet Metro|Willow Pinball|Xenon Mosaic|Yellow Fractals|Zinc Butterflies|Asymmetric Lanterns|Braided Electrons|Chromatic Dew|Digital Suncatcher''',
 'Textures': '''Ash and Rainbows|Bioluminescent Cave|Coral Radio|Dust in Sunbeams|Emerald Glaciers|Folding Mercury|Glass Kelp Forest|Humming Moths|Ink in Water|Jade Machinery|Kaleidoscope Fog|Lichen Transmissions|Magnetic Petals|Nocturnal Aquarium|Opal Insects|Porcelain Storm|Quicksand Choir|Rustling Prisms|Saltwater Antennas|Tidal Circuitry|Ultraviolet Moss|Volcanic Silk|Whispering Satellites|Xenon Rainforest|Yellow Ghostlight|Zinc Tides|Aurora Fossils|Breathing Rust|Chromatic Clouds|Deep Space Garden''',
 'Organs': '''Amber Rotunda|Blue Velvet Chapel|Copper Drawbars|Dandelion Combo|Emerald Theatre|Farfisa Fireflies|Gospel Honey|Hammond Mirage|Ivory Basilica|Jade Calliope|Kaleidoscope Vox|Lantern Reedhouse|Mahogany Cathedral|Neon Tabernacle|Opal Harmonium|Peacock Pipes|Quartz Positive|Rosewood Gospel|Saffron Chamber|Tangerine Transit|Ultraviolet Abbey|Verdigris Console|Willow Carousel|Xenon Chapel|Yellow Combo Club|Zinc Reed Choir|Afterglow Theatre|Bronze Portative|Cobalt Drawbars|Dusk Processional''',
 'Brass & Strings': '''Amber Concert Hall|Blue Velvet Horns|Copper String Quartet|Dawn Trombone Choir|Emerald Chamber|Flamingo Brass|Golden Bow Ensemble|Hornbeam Orchestra|Iridescent Cellos|Jade Trumpet Section|Kinetic Violas|Lacquered French Horn|Mahogany Low Strings|Nacre Flugelhorns|Ochre Synth Orchestra|Peacock Pizzicato|Quartz Trombone|Rosegold Violins|Saffron Horn Swell|Tangerine String Machine|Ultraviolet Cinema|Velvet Brass Band|Willow Solo Cello|Xenon Chamber Strings|Yellow Ribbon Horns|Zinc Bowed Choir|Autumn Cornets|Brocade String Choir|Cobalt Ensemble|Dusk Muted Brass''',
 'Splits': '''Amber Bass and Rain|Blue Harbor Duet|Copper Left Glass Right|Dawn Organ and Strings|Emerald Groove Garden|Fuchsia Night Duo|Gold Keys Silver Air|Honey Bass Neon Lead|Indigo Chamber Split|Jade Stage Lights|Kinetic Bass Bell|Lunar Trio Room|Mango Funk Station|Neon Left Velvet Right|Opal Cinema Hands|Peacock Jazz Orbit|Quartz Pluck Theatre|Rosewood Bass Choir|Saffron Split Horizon|Tangerine Live Room|Ultraviolet Two Worlds|Violet Arp Cathedral|Walnut Jazz Machine|Xenon Bass Garden|Yellow Stage Comet|Zinc Cinema Duet|Afterglow Companion|Bronze Groove Atlas|Cobalt Piano Sky|Dusk Orchestra Split'''
}

# Four complementary roles for each family; each category has ten families and
# three independently voiced arrangements (foundation, animated, spectral).
FAMILIES = {
 'Pads': [('velvet','choir','air','bell'),('strings','glass','flute','noise'),('reed','bowed','spark','air'),('organ','choir','metal','flute'),('choir','velvet','bell','noise'),('flute','strings','glass','air'),('bowed','reed','spark','choir'),('glass','organ','air','metal'),('velvet','wire','flute','spark'),('strings','choir','mallet','noise')],
 'Bass': [('sub','reed','mallet','air'),('brass','sub','wire','noise'),('growl','sub','digital','air'),('reed','sub','metal','noise'),('acid','sub','bell','air'),('digital','sub','wire','noise'),('bowed','sub','pluck','air'),('velvet','sub','mallet','noise'),('wire','sub','brass','air'),('organ','sub','growl','noise')],
 'Leads': [('reed','velvet','air','bell'),('flute','glass','choir','air'),('brass','reed','wire','air'),('bowed','strings','glass','noise'),('acid','velvet','spark','air'),('growl','reed','metal','noise'),('glass','flute','bell','air'),('wire','brass','choir','air'),('choir','reed','digital','noise'),('organ','flute','spark','air')],
 'Keys': [('felt','tine','noise','air'),('glass','felt','bell','choir'),('tine','reed','mallet','air'),('bell','glass','spark','flute'),('reed','felt','wire','noise'),('pluck','organ','spark','air'),('glass','tine','metal','flute'),('tine','velvet','bell','noise'),('felt','choir','air','mallet'),('mallet','bell','spark','glass')],
 'Plucks': [('pluck','glass','air','bell'),('mallet','flute','noise','spark'),('reed','pluck','glass','air'),('wire','bell','noise','metal'),('tine','mallet','air','spark'),('strings','pluck','glass','noise'),('glass','bell','flute','air'),('pluck','metal','choir','spark'),('digital','mallet','air','bell'),('bell','tine','spark','noise')],
 'Arps': [('pluck','sub','glass','air'),('digital','mallet','bell','velvet'),('reed','pluck','spark','choir'),('mallet','glass','wire','air'),('acid','sub','bell','noise'),('tine','flute','pluck','air'),('glass','digital','spark','velvet'),('wire','sub','mallet','choir'),('organ','pluck','bell','noise'),('bell','reed','glass','air')],
 'Textures': [('noise','choir','metal','sub'),('choir','air','bell','velvet'),('digital','reed','noise','glass'),('air','spark','bowed','organ'),('glass','choir','noise','sub'),('metal','wire','air','velvet'),('flute','bowed','digital','noise'),('reed','air','spark','choir'),('velvet','metal','noise','bell'),('growl','choir','air','glass')],
 'Organs': [('organ','reed','bell','air'),('organ','flute','tine','choir'),('reed','organ','mallet','air'),('wire','organ','bell','noise'),('choir','organ','glass','flute'),('reed','wire','spark','organ'),('organ','brass','bell','choir'),('organ','velvet','tine','air'),('flute','organ','bell','choir'),('reed','flute','glass','air')],
 'Brass & Strings': [('brass','strings','bowed','air'),('brass','reed','choir','noise'),('strings','bowed','glass','flute'),('brass','organ','reed','air'),('bowed','strings','flute','noise'),('brass','wire','choir','air'),('strings','velvet','bowed','spark'),('brass','flute','organ','noise'),('bowed','glass','strings','air'),('brass','reed','bell','choir')],
 'Splits': [('sub','reed','glass','air'),('reed','sub','tine','choir'),('brass','sub','bell','glass'),('organ','reed','strings','bowed'),('acid','sub','pluck','air'),('growl','sub','reed','choir'),('felt','tine','air','strings'),('sub','mallet','wire','brass'),('bowed','sub','flute','glass'),('organ','reed','bell','choir')]
}

# Timbres are components, not presets; envelopes and articulation are composed
# by the category and arrangement below. All oscillator interactions are real DSP.
TIMBRES = {
 'velvet': {1:2,2:1,3:.32,7:3200,36:2,37:7,73:1,74:.1,75:.18},
 'reed': {1:3,2:1,3:.2,34:.31,35:.11,7:4200,79:1,8:.2,21:.08},
 'glass': {44:1,45:6,46:.38,51:1,52:22,53:.24,3:.38,7:8200,70:1,71:.09,72:2.01,93:.1,94:.08},
 'brass': {1:2,2:2,3:.48,4:11,7:2800,8:.21,20:.22,36:2,58:1,59:1,60:220,79:1,73:1,74:.12,75:.2},
 'strings': {1:2,2:3,3:.34,4:7,34:.42,35:.09,7:4600,36:3,37:10,38:.8,58:1,59:3,60:1900,80:0},
 'felt': {1:0,2:4,3:.24,7:3200,70:1,71:.11,72:1.01,73:1,74:.08,75:.15},
 'tine': {1:0,2:0,3:.12,7:10000,70:1,71:.19,72:2.76,58:1,59:1,60:160,73:1,74:.07,75:.13},
 'bell': {44:1,45:22,46:.48,2:0,3:.1,7:11000,70:1,71:.24,72:3.5,93:.06,94:.06},
 'organ': {1:4,2:0,3:.24,5:.08,7:7200,36:1,58:1,59:1,60:80,73:1,74:.09,75:.17},
 'choir': {44:1,45:4,46:.5,51:1,52:5,53:.32,3:.48,47:4,48:.16,7:6800,93:.14,94:.12,95:.08,96:.15,58:1,59:2,60:2100,62:2,63:.18},
 'air': {44:1,45:18,46:.6,51:1,52:16,53:.3,3:.34,6:.025,7:3900,32:1,79:0,93:.08,94:.12,58:1,59:0,60:12000,38:.85},
 'metal': {44:1,45:8,46:.45,51:1,52:10,53:.6,47:3,48:.12,7:7000,70:3,71:.2,72:1.5,73:3,74:.08,75:.12,93:.18},
 'acid': {1:2,2:3,3:.18,34:.23,7:1100,8:.48,79:1,20:.4,73:1,74:.16,75:.28,58:1,59:1,60:60},
 'sub': {1:0,2:1,3:.13,7:700,79:1,5:0,38:0,73:1,74:.08,75:.12},
 'growl': {44:1,45:13,46:.37,51:1,52:7,53:.4,47:2,48:.14,54:4,55:.12,7:2300,79:1,70:2,71:.13,72:1,93:.18,94:.1,73:2,74:.05,75:.15},
 'digital': {44:1,45:15,46:.45,51:1,52:23,53:.2,47:5,48:.55,54:4,55:.17,7:4800,73:4,74:.05,75:.15,77:11,78:.7,94:.15},
 'flute': {1:0,2:1,3:.24,6:.007,7:5800,70:1,71:.04,72:2,58:1,59:1,60:140},
 'pluck': {44:1,45:2,46:.32,51:1,52:20,53:.35,3:.22,7:6400,47:1,48:.22,79:1,20:.3,94:.08},
 'mallet': {1:0,2:4,3:.21,7:6200,70:1,71:.12,72:1.42,58:1,59:2,60:2600,62:2,63:.1},
 'wire': {1:2,2:3,3:.27,39:1,40:7,7:5500,79:1,36:2,37:5,58:1,59:3,60:1400,73:1,74:.07,75:.14},
 'bowed': {44:1,45:17,46:.36,51:1,52:1,53:.57,3:.46,7:4600,47:4,48:.23,36:2,37:6,93:.08,94:.16,58:1,59:3,60:2300},
 'noise': {1:0,2:1,3:.5,6:.25,7:3500,32:2,8:.28,58:1,59:1,60:1200,79:0,80:1},
 'spark': {44:1,45:10,46:.28,51:1,52:22,53:.6,3:.36,7:9500,47:5,48:.3,70:3,71:.1,72:2,93:.06,94:.05},
}
ENVS = {'Pads':(.7,1.2,.85,2.4),'Bass':(.004,.24,.7,.18),'Leads':(.008,.35,.8,.3),
 'Keys':(.003,1.25,.23,.7),'Plucks':(.002,.38,.06,.35),'Arps':(.003,.25,.38,.25),
 'Textures':(1.1,1.8,.82,3.2),'Organs':(.012,.15,.95,.28),'Brass & Strings':(.13,.55,.8,1.1),'Splits':(.006,.5,.72,.55)}
SHAPES = [ [(0,0),(.45,1),(1,.25)],[(0,.3),(.25,1),(.5,.15),(.75,.8),(1,.3)],
 [(0,1),(.1,.1),(.8,1),(1,1)],[(0,0),(.05,1),(.3,.15),(.55,.65),(1,0)],
 [(0,.1),(.24,.1),(.25,.8),(.49,.8),(.5,.35),(.74,.35),(.75,1),(1,1)],
 [(0,0),(.2,.65),(.5,1),(.8,.65),(1,0)] ]

def schema():
    source=(ROOT/'Sources/PluginParameters.hpp').read_text()
    values=re.search(r'defaults\[\] = \{([^}]+)',source)[1]
    defaults=[float(x) for x in values.split(',')]
    specs=re.findall(r'\{"[^"]+",([^,]+),([^,]+),(true|false),(true|false)\}',source.split('inline constexpr Spec globals')[0])
    assert len(defaults)==len(specs)==126
    return defaults,[(float(a),float(b),c=='true',d=='true') for a,b,c,d in specs]
DEFAULTS,SPECS=schema()
FXSPEC=[(0,1,False,False),(30,240,False,False),(0,.6,False,False),(0,.75,False,False),(0,.75,False,False),(0,.6,False,False),(0,1,False,False),(.03,5,False,False),(0,1,False,False),(-.85,.85,False,False),(.03,5,False,False),(0,1,False,False),(0,1,False,False),(.2,8,False,False),(0,7,False,True)]

def route(source=0,destination=0,amount=0,target=4,cc=1):
    return dict(enabled=amount!=0,source=source,destination=destination,target=target,cc=cc,amount=amount)

def motion(v,c,i,l):
    ambient=c in ('Pads','Textures');rhythm=c=='Arps'
    enabled=ambient or (l>=2 and i%3!=0) or rhythm
    target=(4 if v[44] else 3) if l%2 else (6 if v[44] and v[47] else 1)
    ranges=[(0,1),(max(120,v[7]*.65),min(15000,v[7]*1.6)),(0,12),(-.3,.3),(.1,.8),(.1,.8),(.08,.5),(.05,.4)]
    routes=[dict(enabled=enabled and t==target,minimum=a,maximum=b,inverted=(l%2==1)) for t,(a,b) in enumerate(ranges)]
    points=SHAPES[(i+l)%len(SHAPES)]
    return dict(enabled=enabled,loop=ambient or rhythm,seconds=[5,8,12,18,24][(i+l)%5] if ambient else 2.5,
                beats=([2,4,8,16][(i+l)%4] if rhythm else None),grid=16 if rhythm else 0,
                points=[dict(x=x,y=y,curve=(-.25 if n%2==0 else .15)) for n,(x,y) in enumerate(points)],routes=routes)

def make_layer(c,i,l,role):
    v=dict(enumerate(DEFAULTS));v.update({0:1,5:0,6:0,13:[.68,.38,.18,.11][l],14:[-.12,.12,-.35,.35][l],16:.13+.017*(i%9),17:.035,20:.08,21:0,29:.21+.031*(i%7),30:.025,33:1,41:0,44:0,51:0,58:0,68:0,73:0})
    v.update(TIMBRES[role]);a,d,s,r=ENVS[c];variant=i//10;family=i%10
    v.update({9:a*(1+.13*((i+l)%5)),10:d*(.75+.13*((i+2*l)%7)),11:s,12:r*(.8+.1*((i+l)%5))})
    # Upper partials and attacks behave differently from the held body.
    if l==2 and role in ('bell','spark','mallet','tine','pluck'):v.update({9:.002,10:.22+.08*(i%5),11:0,12:.35,15:12})
    if l==3:v.update({9:.35 if c in ('Pads','Textures') else .015,13:.09,15:12 if role not in ('noise','sub') else 0})
    if c in ('Bass','Leads'):v.update({41:2,42:.025+.012*(i%5),43:12 if c=='Leads' and i%4==0 else 2,14:0 if l<2 else .16,12:min(v[12],.45)})
    if c=='Bass':
        v.update({15:-12,13:[.62,.37,.12,.03][l],7:min(v[7],4200 if l==2 else 2400),38:0 if l<2 else .25,17:0 if role=='sub' else .04,30:0,0:0 if l==3 else 1})
        if role=='sub':v.update({7:600,58:0,79:1,36:1})
    if c=='Leads':v.update({13:[.65,.28,.11,.06][l],0:0 if l==3 and variant!=2 else 1})
    if c=='Plucks':v.update({13:[.75,.35,.14,.08][l],11:0 if l<3 else .05,0:0 if l==3 and variant==0 else 1})
    if c=='Organs':
        v.update({15:[0,12,19 if variant==1 else 7,24][l],13:[.62,.27,.12,.08][l],36:1,9:.006 if l<2 else .002,10:.18,11:0 if l==2 else .93,17:.012,30:.025})
    if c=='Brass & Strings':
        if role in ('strings','bowed'):v.update({9:.18+.06*variant,12:1.25,15:-12 if family==2 and l==0 else 0})
        if role=='brass':v.update({9:.035+.04*variant,20:.25,64:.045,65:.32,68:.2,69:0})
    if c=='Arps':
        v.update({22:1 if l<3 else 0,23:[2,1,3,2][(l+variant)%4],24:(family+l)%4,25:1 if l==0 else 2,26:[.42,.58,.72][(i+l)%3],13:[.62,.25,.16,.07][l],15:-12 if l==1 and role=='sub' else 12 if l==2 else 0,36:1})
    if c=='Splits':
        v.update({27:0 if l<2 else 60,28:59 if l<2 else 127,13:[.8,.32,.7,.22][l],15:0 if l<2 else 0,9:.006 if l<2 else .04,11:.75 if l<2 else .6})
        if l<2:v.update({41:2,42:.035,7:min(v[7],3000),38:0})
        if variant==2 and l==2:v.update({22:1,23:2,24:family%3,25:1,26:.65})
    # Independent arrangements: spectral upper voices, rhythmic contours, and
    # different filter interactions—not only random detune or renamed copies.
    if variant==1:
        if l==1 and c not in ('Bass','Organs','Splits'):v[15]=[7,12,-12,0,19][family%5]
        if l!=0 or c not in ('Bass',):v.update({58:1,59:[3,1,2][family%3],60:[850,1400,2700,4300,6200][family%5],62:2,63:.12+.025*family,80:family%2})
        if v[44]:v.update({47:4,48:.18+.02*family,93:.05+.016*family,94:.06+.009*family})
    elif variant==2:
        if l==0 and c not in ('Bass','Organs'):v.update({44:1,45:(family*3+2)%24,46:.22+.043*family,47:5,48:.18+.035*family,93:.05+.012*family,94:.09,51:1,52:(family*5+7)%24,54:4,55:.16})
        if role not in ('sub','noise','air'):v.update({70:[1,2,3][(family+l)%3],71:.045+.018*((family+l)%6),72:[1,1.5,2,2.01,3][(family+l)%5],73:[1,3,4][family%3],74:.05+.012*family,75:.12,77:12,78:.8})
    # Both independent LFOs are useful at the stored sound; vibrato blooms after
    # the attack, while rhythmic timbre follows tempo on rhythmic arrangements.
    sync=c=='Arps' or variant==1
    v.update({81:int(sync),82:[4,5,6,8,9][(family+l)%5],83:int(c not in ('Pads','Textures','Organs')),84:((family+2*l)%8)/8,85:.12 if c=='Leads' else .0,86:.6 if c in ('Leads','Pads','Brass & Strings') else .1,
              87:int(c=='Arps' or (variant==2 and l%2==1)),88:[3,4,5,8,9][(family+2*l)%5],89:int(c in ('Keys','Plucks','Bass')),90:((family+3*l)%7)/7,91:.2 if l==0 else .08,92:1.1 if c in ('Pads','Textures','Brass & Strings') else .3})
    # LFO 3-5 are Matrix-only voices: shape/rate/division vary per family while
    # depth stays full and the Sound Matrix amounts scale the musical result.
    lfo_sync=c=='Arps' or variant==1
    v.update({99:(family+l)%5,100:[.07,.13,.21,.35,.5,.9,1.7,3.1,5.2,7.6][(family*2+l)%10],101:1,
              102:int(lfo_sync),103:[2,3,4,5,8][(family+l)%5],104:int(c=='Arps' and l==0),105:((family+l)%8)/8,106:0,107:0,
              108:(family+2*l)%5,109:[.05,.09,.16,.3,.6,1.1,2.2,4.0,6.3,8.8][(family*3+l)%10],110:1,
              111:int(lfo_sync),112:[1,2,3,4,6][(family+2*l)%5],113:0,114:((family+3*l)%8)/8,115:0,116:0,
              117:(family+3*l)%5,118:[.04,.08,.12,.2,.4,.8,1.5,2.8,4.6,7.2][(family+l*3)%10],119:1,
              120:int(lfo_sync),121:[0,2,4,5,8][(family+l)%5],122:0,123:((family+4*l)%8)/8,124:0,125:0})
    if c=='Bass':v.update({101:.6,110:.6,119:.6})
    v[19]=[0,1,2,0,4][(family+l)%5];v[33]=[1,0,2,4,0][(family+2*l)%5]
    if c=='Leads':v.update({29:4.5+.2*family,31:1,30:.035,91:.2,92:.65})
    if v[44] and i%2:v.update({54:5 if v[51] else 0,55:.22 if v[51] else 0,95:.08,96:.12})
    if v[58]==0 and role!='sub':v.update({58:1,59:3,60:1200+180*family,62:0,80:(l+family)%2})
    if c=='Pads' and family in (0,6) and l==0:v.update({36:8 if variant==2 else 4,37:6+family,38:.85})
    if c=='Textures':v.update({13:[.5,.32,.2,.12][l],64:.7+.13*family,65:1.4,66:.3,67:1.5,68:.13,69:1})
    elif c not in ('Organs',):v.update({64:.008 if c in ('Keys','Plucks','Bass','Arps') else .12,65:.3+.07*family,66:.05,67:.35,68:.18 if l==0 else .07,69:4 if v[70] else 1})
    # Deterministic variation within the musical family, bounded and documented.
    v[46]=min(.85,v[46]+.013*l);v[53]=min(.85,v[53]+.017*family)
    if v[36]>1:v[37]=5+(i+3*l)%11
    return {k:round(value,7) for k,value in v.items()}

def normalized(v,p,shared=False):
    lo,hi,log,_=(FXSPEC if shared else SPECS)[p]
    v=max(lo,min(hi,v));return math.log(v/lo)/math.log(hi/lo) if log else (v-lo)/(hi-lo)

def macros(p):
    names=['Color','Ensemble','Motion','Space','Contour','Release','Width','Echo']
    result={str(i):dict(name=name,routes=[]) for i,name in enumerate(names)}
    def add(m,l,k,span,reverse=False):
        if l>=0 and SPECS[k][3]:return
        v=p['layers'][l]['values'][str(k)] if l>=0 else p['globals'][k] if k<6 else p['fx'][str(k)]
        center=normalized(v,k,l<0);span=min(span,center,1-center)
        if span<=.000001:return
        a,b=center-span,center+span
        result[str(m)]['routes'].append(dict(id=f'm{m}-l{l}-p{k}',target=dict(layer=l,parameter=k),**{'from':b if reverse else a,'to':a if reverse else b}))
    for l,layer in enumerate(p['layers']):
        v=layer['values']
        if not v['0']:continue
        targets={i for i,r in enumerate(p['motion'][l]['routes']) if p['motion'][l]['enabled'] and r['enabled']}
        if 1 not in targets:add(0,l,7,.13)
        if v['44'] and 4 not in targets:add(0,l,46,.2)
        elif not v['44']:add(0,l,3,.14)
        if v['44']:add(0,l,93,.06)
        if v['51']:add(0,l,95,.04)
        add(1,l,13,.14,l==0)
        add(2,l,17,.07);add(2,l,30,.04)
        add(4,l,68,.12);add(4,l,9,.11)
        if v['73']:add(4,l,74,.06)
        add(5,l,12,.13)
        if v['36']>1:add(6,l,38,.18)
    add(2,-1,7,.025);add(3,-1,4,.1);add(3,-1,12,.13);add(3,-1,13,.1)
    add(6,-1,5,.05);add(6,-1,11,.15);add(7,-1,2,.09);add(7,-1,3,.09)
    assert all(v['routes'] for v in result.values())
    return result

def fm_op(wave=0,ratio=1.0,level=0.5,vel=0.6,rates=(180,10,8,40),levels=(1,0.25,0.2,0),
          fixedHz=440.0,fixedMode=0,fine=0.0,keyScale=0,keySync=1,envMode=0,pulseWidth=0.5,
          wtTable=0,wtPos=0.5,wtWarp=0.0):
    return dict(wave=wave,ratio=ratio,fixedHz=fixedHz,fixedMode=fixedMode,fine=fine,
                level=level,vel=vel,keyScale=keyScale,keySync=keySync,envMode=envMode,
                pulseWidth=pulseWidth,wtTable=wtTable,wtPos=wtPos,wtWarp=wtWarp,
                env=dict(rates=list(rates),levels=list(levels)))

def fm_layer(algorithm,feedback,ops,pitch_amount=0.0,pitch_time=0.05,pitch_curve=0.5,carrierMix=0.5):
    return dict(enabled=True,algorithm=algorithm,feedback=feedback,carrierMix=carrierMix,
                pitchEnv=dict(amount=pitch_amount,time=pitch_time,curve=pitch_curve),
                ops={str(i):op for i,op in enumerate(ops)})

def fm_flagships():
    """Spec §8: the flagship FM patches (15 original + 5 pure DX7-style EPs + 5 'DX7 …' EP
    variants) — appended into Aurora100.json. EP-character patches live in category 'FM EP'
    (single FM layer, L3=0 natural decay); marimba/harp/clav/bass/pads stay in 'FM'.
    Core-on-sine (wave policy); ≥10 of the 16 algorithms exercised; every patch routes
    velocity→index (soundMatrix source 9 = Velocity → destination 37+op = Op N level)."""
    def C(ratio=1.0,level=0.85,vel=0.8,rates=(100,6,5,50),levels=(1,0.72,0.68,0),**kw):
        return fm_op(ratio=ratio,level=level,vel=vel,rates=rates,levels=levels,**kw)
    def M(ratio=1.0,level=0.5,vel=0.85,rates=(150,10,8,45),levels=(1,0.28,0.2,0),**kw):
        return fm_op(ratio=ratio,level=level,vel=vel,rates=rates,levels=levels,**kw)
    # name · base family · algorithm · feedback · ops 1-4 · velocity→index op (0-based)
    specs=[
      ('Solar Tine','Keys',4,0.3,[C(),C(fine=0.004,level=0.8,rates=(90,6,5,55)),M(ratio=1,level=0.55),M(ratio=14,level=0.26,vel=0.7,rates=(200,14,10,60),levels=(1,0.14,0.1,0))],2),
      ('Ballad Tine','Keys',5,0.2,[C(rates=(60,5,4,40),levels=(1,0.8,0.75,0)),M(ratio=1,level=0.42,rates=(80,7,6,35),levels=(1,0.4,0.35,0)),M(ratio=2,level=0.3,rates=(50,6,5,30)),C(rates=(70,5,4,45),levels=(1,0.7,0.6,0))],1),
      ('Wurli Coals','Keys',2,0.35,[M(ratio=1,level=0.45,rates=(120,9,7,40)),M(ratio=1,level=0.55),M(ratio=2.99,level=0.3,vel=0.7),C(level=0.9,rates=(110,7,6,55),levels=(1,0.65,0.6,0))],0),
      ('Felt Cinema Tine','Keys',7,0.25,[C(rates=(45,5,4,35),levels=(1,0.75,0.7,0),level=0.8),C(rates=(55,5,4,40),level=0.75),M(ratio=1,level=0.4,rates=(70,7,6,30),levels=(1,0.45,0.4,0)),M(ratio=3.01,level=0.3)],2),
      ('Rhodes Hybrid','Keys',6,0.3,[M(ratio=1,level=0.5,vel=0.8,rates=(140,9,0.9,45),levels=(1,0.3,0,0)),C(level=0.85,rates=(100,6.5,0.22,52),levels=(1,0.58,0,0)),C(fine=-0.003,level=0.8,rates=(80,6,0.2,50),levels=(1,0.54,0,0)),M(ratio=3.5,level=0.28,vel=0.7,rates=(180,12,1.0,50),levels=(1,0.18,0,0))],0,True),
      ('Chrome Clav','Keys',8,0.2,[M(ratio=1,level=0.5,rates=(200,25,18,60),levels=(1,0.1,0.05,0)),M(ratio=3.98,level=0.42,vel=0.75,rates=(220,30,20,70),levels=(1,0.08,0.04,0)),C(rates=(160,18,14,70),levels=(1,0.3,0.2,0),level=0.8),C(rates=(150,16,13,65),levels=(1,0.28,0.18,0),level=0.75)],1),
      ('Glass House EP','Keys',0,0.3,[M(ratio=1,level=0.42,vel=0.7,rates=(90,8,0.8,35),levels=(1,0.42,0,0)),M(ratio=1,level=0.5,rates=(110,9,0.9,40),levels=(1,0.38,0,0)),M(ratio=7,level=0.22,vel=0.65,rates=(210,16,1.2,55),levels=(1,0.12,0,0)),C(level=0.88,rates=(100,6.5,0.24,50),levels=(1,0.6,0,0))],0,True),
      ('Velvet Vibes','Keys',3,0.2,[M(ratio=1,level=0.5,rates=(60,4,3,25),levels=(1,0.55,0.5,0)),M(ratio=2.76,level=0.32,vel=0.7,rates=(55,4,3,22),levels=(1,0.3,0.25,0)),M(ratio=5.4,level=0.18,vel=0.6,rates=(75,5,4,28),levels=(1,0.15,0.1,0)),C(level=0.85,rates=(55,3.5,2.5,22),levels=(1,0.5,0.42,0))],0),
      ('Glass Marimba','Keys',9,0.15,[C(level=0.85,rates=(170,30,0.28,90),levels=(1,0.14,0,0)),C(ratio=2.99,level=0.35,rates=(180,35,0.4,95),levels=(1,0.09,0,0)),C(ratio=9.2,level=0.12,rates=(200,45,0.6,110),levels=(1,0.05,0,0)),M(ratio=3.98,level=0.4,vel=0.8,rates=(230,50,0.8,120),levels=(1,0.06,0,0))],3,True),
      ('Nylon Harp','Keys',10,0.2,[C(level=0.8,rates=(150,12,0.35,60),levels=(1,0.5,0,0)),C(ratio=2,level=0.5,rates=(140,14,0.45,65),levels=(1,0.35,0,0)),C(ratio=3,level=0.25,rates=(160,16,0.6,70),levels=(1,0.22,0,0)),M(ratio=1,level=0.45,vel=0.8,rates=(170,15,0.7,70),levels=(1,0.3,0,0))],3,True),
      ('Copper Harpsichord','Keys',11,0.0,[M(ratio=3,level=0.5,vel=0.85,rates=(240,35,30,90),levels=(1,0.06,0.03,0)),C(ratio=2,level=0.3,rates=(190,25,22,80),levels=(1,0.1,0.06,0)),C(ratio=1.005,level=0.55,rates=(170,22,20,75),levels=(1,0.12,0.08,0)),C(level=0.85,rates=(180,24,20,85),levels=(1,0.12,0.07,0))],0),
      ('Round FM Bass','Bass',13,0.55,[M(ratio=1,level=0.55,vel=0.75,rates=(130,10,8,45),levels=(1,0.35,0.3,0)),M(ratio=1,level=0.45,rates=(110,9,8,40),levels=(1,0.4,0.35,0)),M(ratio=0.5,level=0.35,rates=(90,8,7,35),levels=(1,0.5,0.45,0)),C(level=0.9,rates=(120,7,6,50),levels=(1,0.7,0.65,0))],0),
      ('Click Tine Bass','Bass',14,0.5,[C(level=0.88,rates=(130,8,7,55),levels=(1,0.65,0.6,0)),C(level=0.7,rates=(120,9,8,50),levels=(1,0.55,0.5,0)),M(ratio=1,level=0.5,vel=0.85,rates=(150,10,8,50),levels=(1,0.3,0.25,0)),M(ratio=2,level=0.4,vel=0.7,rates=(190,14,12,60),levels=(1,0.15,0.1,0))],2),
      ('Bell Pad Drift','Pads',12,0.0,[C(level=0.7,rates=(18,2.5,2,14),levels=(1,0.8,0.75,0)),C(ratio=2.01,level=0.4,vel=0.8,rates=(15,2.2,1.8,12),levels=(1,0.6,0.5,0)),C(ratio=4.98,level=0.22,vel=0.7,rates=(12,2,1.6,10),levels=(1,0.4,0.3,0)),C(ratio=7.03,level=0.12,vel=0.6,rates=(10,1.8,1.5,9),levels=(1,0.25,0.18,0))],1),
      ('Evolving Keys','Pads',15,0.6,[M(ratio=1,level=0.45,rates=(30,4,3,18),levels=(1,0.55,0.5,0)),M(ratio=2,level=0.35,vel=0.7,rates=(26,3.5,3,16),levels=(1,0.45,0.4,0)),M(ratio=5.01,level=0.2,vel=0.6,rates=(40,5,4,22),levels=(1,0.3,0.25,0)),C(level=0.85,rates=(24,3,2.5,16),levels=(1,0.7,0.65,0))],0),
      # Owner order 23 Sep 2026: five more DX7-style FM electric pianos — strictly
      # piano, single FM layer (subtractive layers B/C/D disabled), no pad/texture.
      # Trailing True = pure-piano flag.
      ('DX Tine Classic','Keys',4,0.25,[C(fine=0.003,rates=(110,7,0.22,60),levels=(1,0.55,0,0)),C(fine=-0.003,level=0.75,rates=(95,6.5,0.2,55),levels=(1,0.5,0,0)),M(ratio=1,level=0.5,vel=0.8,rates=(140,9,0.9,45),levels=(1,0.3,0,0)),M(ratio=14.02,level=0.22,vel=0.75,rates=(220,16,0.35,70),levels=(1,0.1,0,0))],2,True),
      ('Suitcase 77','Keys',5,0.2,[C(rates=(70,5.5,0.17,45),levels=(1,0.6,0,0)),C(fine=0.002,level=0.8,rates=(65,5,0.16,42),levels=(1,0.56,0,0)),M(ratio=1,level=0.42,vel=0.7,rates=(85,7,0.7,38),levels=(1,0.4,0,0)),M(ratio=2,level=0.3,vel=0.65,rates=(60,6,0.55,32),levels=(1,0.3,0,0))],2,True),
      ('Stage Bark','Keys',2,0.4,[M(ratio=1,level=0.5,vel=0.85,rates=(130,10,1.1,42),levels=(1,0.32,0,0)),M(ratio=1,level=0.45,rates=(115,9,0.9,40),levels=(1,0.34,0,0)),M(ratio=2.99,level=0.32,vel=0.8,rates=(180,12,1.4,55),levels=(1,0.14,0,0)),C(level=0.9,rates=(120,7.5,0.3,58),levels=(1,0.6,0,0))],0,True),
      ('Glass Hammer EP','Keys',6,0.3,[M(ratio=1,level=0.48,vel=0.8,rates=(150,11,0.9,48),levels=(1,0.3,0,0)),C(level=0.85,rates=(105,6.5,0.24,52),levels=(1,0.62,0,0)),C(fine=-0.0035,level=0.78,rates=(88,6,0.22,50),levels=(1,0.58,0,0)),M(ratio=7.04,level=0.3,vel=0.75,rates=(200,14,1.1,62),levels=(1,0.12,0,0))],3,True),
      ('Midnight Tine','Keys',7,0.3,[C(level=0.82,rates=(55,4.5,0.15,32),levels=(1,0.6,0,0)),C(fine=-0.0025,level=0.76,rates=(48,4,0.14,30),levels=(1,0.56,0,0)),M(ratio=1,level=0.36,vel=0.65,rates=(75,6,0.5,30),levels=(1,0.38,0,0)),M(ratio=2.01,level=0.26,vel=0.6,rates=(65,5.5,0.45,28),levels=(1,0.26,0,0))],2,True),
      # Owner order 24 Sep 2026: five "DX7 …" pure EP variants — strictly electric piano
      # (single FM layer, L3=0 natural decay, velocity→index), no pad/texture/brass/string
      # mixing; layering is the owner's job via the future dual-patch. Category 'FM EP'.
      ('DX7 E.Piano 1','Keys',4,0.25,[C(fine=0.002,rates=(105,7,0.24,58),levels=(1,0.58,0,0)),C(fine=-0.002,level=0.78,rates=(95,6.5,0.22,54),levels=(1,0.54,0,0)),M(ratio=1,level=0.5,vel=0.8,rates=(135,9,0.85,44),levels=(1,0.3,0,0)),M(ratio=14,level=0.2,vel=0.7,rates=(210,15,0.4,66),levels=(1,0.1,0,0))],2,True),
      ('DX7 E.Piano 2','Keys',2,0.35,[M(ratio=1,level=0.52,vel=0.85,rates=(140,10,1.0,44),levels=(1,0.34,0,0)),M(ratio=1,level=0.46,rates=(118,9,0.9,40),levels=(1,0.36,0,0)),M(ratio=3.01,level=0.3,vel=0.8,rates=(190,13,1.5,56),levels=(1,0.13,0,0)),C(level=0.9,rates=(125,7.5,0.26,58),levels=(1,0.6,0,0))],0,True),
      ('DX7 Hard Tine','Keys',8,0.3,[M(ratio=1,level=0.55,vel=0.9,rates=(190,16,1.6,60),levels=(1,0.22,0,0)),M(ratio=2.99,level=0.4,vel=0.85,rates=(220,18,1.8,68),levels=(1,0.12,0,0)),C(level=0.88,rates=(160,12,0.3,70),levels=(1,0.5,0,0)),C(fine=0.003,level=0.8,rates=(150,11,0.28,66),levels=(1,0.46,0,0))],0,True),
      ('DX7 Mellow Tine','Keys',7,0.25,[C(level=0.84,rates=(44,3.8,0.16,30),levels=(1,0.6,0,0)),C(fine=-0.002,level=0.78,rates=(38,3.4,0.15,28),levels=(1,0.56,0,0)),M(ratio=1,level=0.3,vel=0.55,rates=(58,4.5,0.4,24),levels=(1,0.3,0,0)),M(ratio=2,level=0.2,vel=0.5,rates=(52,4,0.38,22),levels=(1,0.22,0,0))],2,True),
      ('DX7 Bell Piano','Keys',6,0.28,[M(ratio=1,level=0.46,vel=0.8,rates=(145,10,0.9,46),levels=(1,0.3,0,0)),C(level=0.86,rates=(100,6.5,0.22,52),levels=(1,0.6,0,0)),C(fine=-0.003,level=0.8,rates=(90,6,0.2,48),levels=(1,0.56,0,0)),M(ratio=7.02,level=0.38,vel=0.78,rates=(200,13,0.6,62),levels=(1,0.2,0,0))],0,True),
    ]
    pure_details={
      'DX Tine Classic':'Play with touch; A: classic DX7-style tine piano — bell attack, natural decay to silence while held. Velocity opens the tine bite. X: Color; Y: Ensemble.',
      'Suitcase 77':'Play with touch; A: round suitcase-style FM piano — soft attack, long warm body that decays naturally. Velocity adds gentle bite. X: Color; Y: Ensemble.',
      'Stage Bark':'Dig in; A: punchy stage FM piano — tidy when soft, barks when played hard, decays like a real stage piano. Velocity drives the bark. X: Color; Y: Ensemble.',
      'Glass Hammer EP':'Play with touch; A: glassy hammer FM piano — bright top over a round body, natural decay. Velocity brings the sparkle. X: Color; Y: Ensemble.',
      'Midnight Tine':'Play softly; A: dark late-night FM tine — mellow, close, velvety, long natural decay. Velocity gently wakes the top. X: Color; Y: Ensemble.',
      'Rhodes Hybrid':'Play with touch; A: pure FM Rhodes-style piano — round tine body that decays to silence while held. Velocity adds bite. X: Color; Y: Ensemble.',
      'Glass House EP':'Play with touch; A: pure glassy FM piano — shimmering attack, body decays naturally. Velocity adds glass. X: Color; Y: Ensemble.',
      'Glass Marimba':'Strike and release; A: pure FM marimba — hard glassy mallet hit, fast woody decay to silence. Velocity brightens the bar. X: Color; Y: Ensemble.',
      'Nylon Harp':'Pluck and let ring; A: pure FM nylon harp — soft pluck, strings decay naturally while held. Velocity adds edge. X: Color; Y: Ensemble.',
      'DX7 E.Piano 1':'Play with touch; A: the classic DX7 factory-style EP — bright bell attack, tine body, natural decay to silence. Velocity opens the bite. X: Color; Y: Ensemble.',
      'DX7 E.Piano 2':'Dig in; A: sharper DX7 factory-style EP — more metallic edge and bark, natural decay. Velocity drives the bite. X: Color; Y: Ensemble.',
      'DX7 Hard Tine':'Hit it hard; A: hard-struck DX7 tine — percussive hammer, short punchy tail. Velocity slams the tine. X: Color; Y: Ensemble.',
      'DX7 Mellow Tine':'Play softly; A: mellow DX7 tine — soft felt-like attack, dark warm body, long slow decay. Velocity gently wakes the top. X: Color; Y: Ensemble.',
      'DX7 Bell Piano':'Play with touch; A: bell-forward DX7 piano — glassy chime over a warm body, natural decay. Velocity lifts the chime. X: Color; Y: Ensemble.',
    }
    ep_names={'DX Tine Classic','Suitcase 77','Stage Bark','Glass Hammer EP','Midnight Tine','Rhodes Hybrid','Glass House EP','DX7 E.Piano 1','DX7 E.Piano 2','DX7 Hard Tine','DX7 Mellow Tine','DX7 Bell Piano'}
    out=[]
    for n,spec in enumerate(specs):
        name,base,alg,fb,ops,velop=spec[:6];pure=len(spec)>6 and spec[6]
        p=make_patch(base,n%10,name)
        p['category']='FM EP' if name in ep_names else 'FM';p['id']='fm-'+re.sub('[^a-z0-9]+','-',name.lower())
        p['layers'][0]['fm']=fm_layer(alg,fb,ops)
        p['soundMatrix'][0][2]=route(9,37+velop,0.5)  # velocity→index rides slot 2 (spec §6/§8)
        if pure:
            for l in range(1,4):p['layers'][l]['values']['0']=0
            p['detail']=pure_details[name]
        out.append(p)
    assert len(out)==25 and len({p['name'] for p in out})==25 and len({p['id'] for p in out})==25
    assert len({s[2] for s in specs})>=10,'spec §8: >=10 of 16 algorithms exercised'
    for s in specs:
        if len(s)>6 and s[6]:
            assert all(op['env']['levels'][2]==0 for op in s[4]),'pure EP: op sustain level (L3) must be 0 — real pianos decay to silence while held'
    for p in out:
        fm=p['layers'][0]['fm']
        assert fm['enabled'] and 0<=fm['algorithm']<=15 and p['category'] in ('FM','FM EP')
        assert any(r['source']==9 and 37<=r['destination']<=46 and r['amount']>0 for r in p['soundMatrix'][0])
        for op in fm['ops'].values():
            assert 0.25<=op['ratio']<=16 and 0<=op['level']<=1 and 0<=op['vel']<=1
            assert all(0.02<=r<=300 for r in op['env']['rates'])
            assert all(0<=l<=1 for l in op['env']['levels'])
    return out

def make_patch(c,i,name):
    roles=FAMILIES[c][i%10];layers=[make_layer(c,i,l,role) for l,role in enumerate(roles)]
    ambient=c in ('Pads','Textures');bass=c=='Bass';variant=i//10
    delay=.025 if bass else .16 if c in ('Plucks','Arps') else .08
    reverb=.055 if bass else .27 if ambient else .14
    # 0.20.8: keys 16..36 optional (app fxDefaults fill gaps). Keep classic 7..14; leave new FX at defaults.
    # 20–22 are session EQ on Play (not patch) — never write them into factory fx.
    fx={7:.18+.017*(i%10),8:.35,9:.12,10:.23,11:.55,12:.78 if ambient else .48,13:3.4 if ambient else 1.3,14:[0,4,2,6,5][i%5],16:1,17:375,18:1,19:.65,23:0,24:12,25:3,26:.55,27:20,28:.45,29:.7,30:.55,31:.4,32:0,33:.45,34:.35,35:.7,36:4}
    p=dict(id='spectrum-'+re.sub('[^a-z0-9]+','-',name.lower()),name=name,category=c,
      detail=f"{'Slow chords' if ambient else 'Low single notes' if bass else 'Melodic phrases' if c=='Leads' else 'Hold a chord' if c=='Arps' else 'Left below C4; right from C4' if c=='Splits' else 'Play with touch'}; "+'; '.join(f"{'ABCD'[l]}: {r}" for l,r in enumerate(roles) if layers[l][0])+f". {['Warm body with separate attack and air.','Interlocking motion and parallel filter color.','Spectral formants and textured harmonics.'][variant]} X: Color; Y: Ensemble. Wheel opens color; pressure adds expression.",
      layers=[dict(values={str(k):v for k,v in layer.items()}) for layer in layers],
      globals=[1,[78,90,104,112,120,126,138,96,108,84][i%10],delay,.24+.015*(i%7),reverb,.018 if bass else .1],
      phaserMix=.04 if bass else .12 if c=='Organs' else .06,fx={str(k):v for k,v in fx.items()},macros=[.5]*8,
      motion=[motion(v,c,i,l) for l,v in enumerate(layers)],
      sends=[dict(delay=(.0 if bass and l<2 else [.2,.45,.6,.4][l]),reverb=(.02 if bass and l<2 else [.3,.55,.65,.9][l])) for l in range(4)],
      soundMatrix=[],performanceMatrix=[],xy=dict(x=dict(macro=0,start=0,end=1),y=dict(macro=1,start=0,end=1)))
    for l,v in enumerate(layers):
        # Ten-slot Sound Matrix: six legacy routes plus four Matrix-only LFO 3-5
        # routes to pulse width, wavetable formant/tone/position, character, and
        # filter envelope. Small amounts keep factory sounds musical; a zero
        # amount disables the slot for that layer.
        p['soundMatrix'].append([route(0,12 if v[44] else 0,.07 if v[44] else .025),route(1,13 if v[51] else 2,.06),route(4,0,.15 if c in ('Keys','Organs') else .08),route(5,2,0 if bass else .08),route(3,18 if v[70] else 16,.12),route(2,14 if v[44] and v[47] else 0,.06),
            route(6,22,0 if bass else .05),route(7,29 if v[44] else 36,.05),route(8,13 if v[51] else (12 if v[44] else 34),.06),route(6,30 if v[44] else 35,.04 if l%2==0 else 0)])
    p['performanceMatrix']=[route(0,0,.18),route(1,0,.07),route(2,18 if layers[0][70] else 0,.12,0),route(3,3,.1),route(0,14 if layers[1][44] else 0,.13,1),route(2,13 if layers[3][51] else 2,.06,3)]
    p['customMacros']=macros(p)
    return p

def assemble():
    patches=[make_patch(c,i,name) for c in CATEGORIES for i,name in enumerate(NAMES[c].split('|'))]
    assert len(patches)==300 and all(len(NAMES[c].split('|'))==30 for c in CATEGORIES)
    trims_path=ROOT/'Resources/SpectrumLevelTrims.json'
    trims=json.loads(trims_path.read_text()) if trims_path.exists() else {}
    for p in patches:
        trim=trims.get(p['id'],1)
        for l in p['layers']:l['values']['13']=round(l['values']['13']*trim,7)
        p['customMacros']=macros(p)
    assert len({p['name'].lower() for p in patches})==len({p['id'] for p in patches})==300
    signatures=set()
    for p in patches:
        signature=hashlib.sha256(json.dumps([p['layers'],p['motion']],sort_keys=True).encode()).hexdigest()
        assert signature not in signatures;signatures.add(signature)
        assert len(p['detail'])<=500
        assert all(len(m)==10 for m in p['soundMatrix'])
        for l in p['layers']:
            assert len(l['values'])==126
            for k,v in l['values'].items():
                lo,hi,_,integer=SPECS[int(k)];assert math.isfinite(v) and lo<=v<=hi,(p['name'],k,v,lo,hi)
                assert not integer or v==int(v)
    # Distribute evenly between existing resource containers; user-facing library
    # is one Spectrum bank, not three inherited collections.
    flagships=fm_flagships()
    assert not {p['name'].lower() for p in flagships}&{p['name'].lower() for p in patches}
    for n,file in enumerate(['Aurora100','AuroraPrism100','AuroraNova100']):
        bank=patches[n::3]+(flagships if n==0 else [])
        (ROOT/f'Resources/{file}.json').write_text(json.dumps(bank,indent=2)+'\n')
    (ROOT/'Resources/AuroraSpectrum300.json').write_text(json.dumps(patches,indent=2)+'\n')
    output=ROOT/'Patch Banks';output.mkdir(exist_ok=True)
    with zipfile.ZipFile(output/'Aurora Spectrum 300 Patches.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for p in patches:
            info=zipfile.ZipInfo(f"Aurora Spectrum 300/{p['category']}/{p['name']}.aurora.json",date_time=(2026,9,19,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(info,json.dumps(p,indent=2)+'\n')
    lines=['# Aurora Spectrum — 300 rebuilt performances','','30 sounds per category. X: Color; Y: Ensemble. Every sound has eight macros, performance modulation, and individual layer sends. C/D supply distinct attacks, motion, or upper voices.','']
    for c in CATEGORIES:
        lines += ['## '+c,'','| Sound | Layers | Playing notes |','|---|---|---|']
        lines += [f"| {p['name']} | {''.join('ABCD'[l] for l,v in enumerate(p['layers']) if v['values']['0'])} | {p['detail']} |" for p in patches if p['category']==c]
        lines += ['']
    (output/'Aurora Spectrum 300 Catalog.md').write_text('\n'.join(lines)+'\n')
    stats=collections.Counter(sum(v['values']['0'] for v in p['layers']) for p in patches)
    print(f'Spectrum: {len(patches)} unique sounds, 30 per category; layer counts {dict(stats)}; {len(trims)} measured trims.')

if __name__=="__main__":
    raise SystemExit("Retired: this generator writes the classic factory banks, which are archived in archive/factory-banks and no longer ship. The module stays importable because live generators reuse its tables; build the current bank with scripts/assemble_modx_bank.py.")
