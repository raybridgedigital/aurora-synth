#!/usr/bin/env python3
"""KiMiA MODX bank: 50 single-character performances across 15 Yamaha MODX
main categories (Drum/Perc skipped) + 5 pure FM electric pianos (FM EP).

Rules enforced here:
- 1-2 layers max, exactly one character per patch (no hybrids — layering is
  the future dual-patch's job).
- Every patch features 1-3 insert FX with explicit power toggles (the rest
  are powered off), plus motion/arp/matrix life. No boring sounds.
- Writes Resources/AuroraFX.json (the empty scaffold becomes the new bank).

Validation mirrors SynthModel.sanitized + PluginParameters ranges, and the
output is exercised by Tests/PluginCoreChecks + V1FactoryAudioAudit.
"""
import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rebuild_factory_bank import (
    DEFAULTS, SPECS, TIMBRES, route, motion, macros, normalized,
    fm_op, fm_layer,
)

ROOT = Path(__file__).resolve().parent.parent

# Global (shared + master FX) ranges, index-aligned with enum AuroraGlobal.
# Mirrors scripts/generate_backend.py granges (authoritative DSP clamp is
# SynthEngine::globalValue).
GRANGES = [(0, 1), (30, 240), (0, .6), (0, .75), (0, .75), (0, .6), (0, 1),
           (.03, 5), (0, 1), (-.85, .85), (.03, 5), (0, 1), (0, 1), (.2, 8),
           (0, 7), (0, 24), (0, 1), (1, 2000), (0, 1), (0, 1), (-12, 12),
           (-12, 12), (-12, 12), (0, 1), (-12, 24), (.2, 12), (0, 1), (0, 200),
           (0, .95), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1),
           (.2, 12), (0, 1), (.03, 5), (0, 1), (0, .9), (0, 1), (.03, 8),
           (0, 1), (0, 2), (0, 1), (1, 16), (1, 64), (0, 1), (0, 1), (-60, 0),
           (1, 12), (.1, 100), (5, 1000), (0, 18), (0, 1), (0, 1), (0, 1),
           (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1),
           (0, 1), (0, 1), (0, 1), (0, 1)]
assert len(GRANGES) == 70
GINTEGER = {14, 16, 44, 46, 47, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69}

# Classic FX bed (== SoundPreset.fxDefaults minus session EQ 20-22).
# All ten power toggles default OFF; each recipe powers its featured FX.
FX_BASE = {7: .18, 8: .35, 9: .12, 10: .23, 11: .55, 12: .5, 13: 1.5, 14: 0,
           16: 1, 17: 375, 18: 1, 19: .65, 23: 0, 24: 12, 25: 3, 26: .55,
           27: 20, 28: .45, 29: .7, 30: .55, 31: .4, 32: 0, 33: .45, 34: .35,
           35: .7, 36: 4, 37: 0, 38: .23, 39: .55, 40: .35, 41: 0, 42: 3,
           43: .6, 44: 0, 45: 0, 46: 8, 47: 1, 48: 0, 49: .4, 50: 0, 51: 2,
           52: 5, 53: 120, 54: 0, 55: 0, 56: 0, 57: .5, 58: .5, 59: 0,
           60: 0, 61: 0, 62: 0, 63: 0, 64: 0, 65: 0, 66: 0, 67: 0, 68: 0,
           69: 0}


def base_values():
    v = dict(enumerate(DEFAULTS))
    v.update({0: 1, 5: 0, 6: 0, 13: .6, 14: 0, 16: .13, 17: .035, 20: .08,
              21: 0, 27: 0, 28: 127, 29: .21, 30: .025, 33: 1, 41: 0, 44: 0,
              51: 0, 58: 0, 68: 0, 73: 0})
    return v


def finish_layer(v):
    """Clip one layer to the 126-parameter spec (hard error, not silent)."""
    out = {}
    for k, val in v.items():
        assert 0 <= k < len(SPECS), f'bad layer param {k}'
        lo, hi, _log, integer = SPECS[k]
        assert math.isfinite(val), f'non-finite layer param {k}'
        assert lo <= val <= hi, f'layer param {k}={val} outside [{lo},{hi}]'
        out[k] = round(val) if integer else round(float(val), 7)
    return out


def voice(role, env, cutoff, res=None, trans=0, level=.6, pan=0, extra=None):
    v = base_values()
    v.update(TIMBRES[role])
    a, d, s, r = env
    v.update({7: cutoff, 9: a, 10: d, 11: s, 12: r, 13: level, 14: pan,
              15: trans})
    if res is not None:
        v[8] = res
    if extra:
        v.update(extra)
    return finish_layer(v)


def off_voice():
    v = base_values()
    v[0] = 0
    return finish_layer(v)


# DESIGN RULE (see PATCH-DESIGN-RULES.md): single-energy-attack instruments
# (plucked / struck / hammered) physically cannot hold — sustain is forced to
# 0 here and the ring comes from Decay + Release. Bowed, blown, organ,
# pad/drone and held-synth voices keep their authored sustain.
# Ebow Prayer is Guitar but bowed (infinite sustain) — deliberately absent.
DECAY_ZERO = {
    'Felt & Timber', 'Stage Cedar', 'Tape Parlor', 'Honky Tonk Union',
    'Tine Stage 76', 'Suitcase Warmth', 'Glass Hammer', 'Midnight Felt',
    'Bell Reed 200', 'Clavi Snapper', 'Harpsi Double', 'Nylon Courtyard',
    'Glass Twelve', 'Dulci Wire', 'Pizz Corner', 'Marimba Smoke',
    'Steel Horizon', 'Music Box Ghost', 'Santur Spark', 'Sitar Monsoon',
    'Stab Alley', 'Thunder Sheet', 'Laser Drawer', 'Gate Crasher',
    'Sidechain Ghost', 'Neon Stab', 'Arp Botanica', 'Compactor',
}


def apply_decay_rule(name, layers):
    if name in DECAY_ZERO:
        for v in layers:
            if v[0]:
                v[11] = 0
    return layers


# House level calibration (measured vs GB109 factory bank): lift layer level
# and master so hold-RMS lands in the same band. Level stops epsilon short
# of the rail so macro spans (center +/- span in macros()) never collapse.
LEVEL_LIFT = 1.6
MASTER_LIFT = 1.5


def lift(layers, glob):
    lo13, hi13 = SPECS[13][0], SPECS[13][1]
    for v in layers:
        if v[0]:
            v[13] = round(min(v[13] * LEVEL_LIFT, hi13 - .002), 7)
    glob = list(glob)
    glob[0] = round(min(glob[0] * MASTER_LIFT, GRANGES[0][1]), 7)
    return glob


def fx_chain(featured):
    fx = dict(FX_BASE)
    fx.update(featured)
    for k, val in fx.items():
        assert k == int(k) and ((7 <= k <= 14) or (16 <= k <= 69)), f'bad fx key {k}'
        lo, hi = GRANGES[int(k)]
        assert math.isfinite(val) and lo <= val <= hi, f'fx {k}={val} outside [{lo},{hi}]'
    return {k: (round(v) if int(k) in GINTEGER else round(float(v), 7))
            for k, v in fx.items()}


def sound_matrix_for(layers):
    """10-slot Sound Matrix per layer; light musical routes on live layers."""
    out = []
    for v in layers:
        if not v[0]:
            out.append([route() for _ in range(10)])
            continue
        out.append([
            route(0, 12 if v[44] else 0, .07 if v[44] else .025),
            route(1, 13 if v[51] else 2, .06),
            route(4, 0, .15 if v[41] == 2 else .08),
            route(5, 2, .08),
            route(3, 18 if v[70] else 16, .12),
            route(2, 14 if v[44] and v[47] else 0, .06),
            route(6, 22, .05),
            route(7, 29 if v[44] else 36, .05),
            route(8, 13 if v[51] else (12 if v[44] else 34), .06),
            route(6, 30 if v[44] else 35, .04),
        ])
    return out


def perf_matrix(layers):
    return [route(0, 0, .18), route(1, 0, .07),
            route(2, 18 if layers[0][70] else 0, .12, 0),
            route(3, 3, .1),
            route(0, 14 if layers[1][44] else 0, .13, 1),
            route(2, 13 if layers[3][51] else 2, .06, 3)]


def ensure_macros(p, cm):
    """Top up any macro left empty so CustomMacro.valid always holds."""
    for m in range(8):
        if cm[str(m)]['routes']:
            continue
        v = float(p['layers'][0]['values']['7'])
        lo, hi, _log, _integer = SPECS[7]
        center = (v - lo) / (hi - lo)
        span = min(.06, center, 1 - center)
        assert span > .000001, f'macro {m}: no headroom on cutoff'
        a, b = center - span, center + span
        cm[str(m)]['routes'].append(
            dict(id=f'm{m}-l0-p7', target=dict(layer=0, parameter=7),
                 **{'from': a, 'to': b}))
    return cm


def assemble_patch(pid, name, category, detail, layers, glob, phaser, fx,
                   sends, motion_cat, force_motion=False, fm0=None):
    assert len(detail) <= 500, name
    assert len(layers) in (1, 2)
    full = layers + [off_voice()] * (4 - len(layers))
    strlayers = [{'values': {str(k): val for k, val in v.items()}} for v in full]
    if fm0 is not None:
        strlayers[0]['fm'] = fm0
    mo = [motion(v, motion_cat, len(name) % 10, l) for l, v in
          [(l, full[l]) for l in range(4)]]
    if force_motion:
        mo[0]['enabled'] = True
        mo[0]['loop'] = True
        mo[0]['seconds'] = 11
    p = dict(id=pid, name=name, category=category, detail=detail,
             layers=strlayers, globals=list(glob), phaserMix=phaser,
             fx={str(k): val for k, val in fx.items()},
             macros=[.5] * 8, motion=mo, sends=sends,
             soundMatrix=sound_matrix_for(full),
             performanceMatrix=perf_matrix(full),
             xy=dict(x=dict(macro=0, start=0, end=1),
                     y=dict(macro=1, start=0, end=1)))
    p['customMacros'] = ensure_macros(p, macros(p))
    return p


def sends4(delay, reverb, shimmer):
    return [dict(delay=delay, reverb=reverb, shimmer=shimmer,
                 shimmerBypass=False) for _ in range(4)]


# Recipe: (name, layers, env-notes...) — layers built inline below.
# Each entry: dict(name, cat, voices=[(role, env, cutoff, opts...)],
#   glob, phaser, fx, sends, motion_cat, force_motion, detail)
R = []


def add(name, cat, voices, glob, fx, detail, phaser=0, sends=None,
        motion_cat='Leads', force_motion=False):
    R.append(dict(name=name, cat=cat, voices=voices, glob=glob, fx=fx,
                  detail=detail, phaser=phaser,
                  sends=sends or sends4(.3, .4, .3), motion_cat=motion_cat,
                  force_motion=force_motion))


# ------------------------------- PIANO (4) -------------------------------
add('Felt & Timber', 'Piano',
    [dict(role='felt', env=(.012, 1.3, .06, 1.8), cutoff=1700, level=.68)],
    glob=[.6, 96, 0, .3, .34, 0],
    fx={62: 1, 12: .55, 13: 2.6},
    detail='Play softly; A: intimate felt grand — hammers close, strings bloom behind. X: Color; Y: Ensemble.',
    sends=sends4(.1, .7, .2), motion_cat='Keys')
add('Stage Cedar', 'Piano',
    [dict(role='felt', env=(.004, 1.1, .07, 1.2), cutoff=4600, res=.12, level=.62),
     dict(role='bell', env=(.002, .7, .05, .9), cutoff=8000, trans=12, level=.16)],
    glob=[.62, 110, .12, .35, .2, .08],
    fx={61: 1, 16: 1, 17: 320, 62: 1, 12: .4, 13: 1.2},
    detail='Dig in; A: bright stage grand, B: octave shimmer an octave up. Slap delay on the tail. X: Color; Y: Ensemble.',
    sends=sends4(.5, .5, .4), motion_cat='Keys')
add('Tape Parlor', 'Piano',
    [dict(role='felt', env=(.006, .9, .06, 1.0), cutoff=2200, level=.64)],
    glob=[.6, 88, 0, .3, .22, 0],
    fx={62: 1, 12: .35, 13: 1.4, 67: 1, 45: .5, 46: 8, 47: 3,
        66: 1, 41: .35, 42: .5, 43: .5},
    detail='Worn cassette upright — gentle crush plus a slow wow wobble. Play late-night chords. X: Color; Y: Ensemble.',
    sends=sends4(.1, .5, .1), motion_cat='Keys')
add('Honky Tonk Union', 'Piano',
    [dict(role='felt', env=(.003, .7, .07, .7), cutoff=3800, res=.2, level=.62,
          extra={4: .22})],
    glob=[.64, 128, .1, .3, .16, .1],
    fx={62: 1, 12: .3, 13: .9, 63: 1},
    detail='Detuned barroom upright, slightly drunk and proud of it. Single notes honk, chords grin. X: Color; Y: Ensemble.',
    sends=sends4(.3, .4, .1), motion_cat='Keys')

# ------------------------------ KEYBOARD (4) -----------------------------
add('Clavi Snapper', 'Keyboard',
    [dict(role='pluck', env=(.002, .3, .08, .3), cutoff=4200, res=.3, level=.6)],
    glob=[.6, 104, .08, .3, .1, 0],
    fx={61: 1, 16: 1, 17: 210, 68: 1, 56: .7, 57: .8, 58: .6},
    detail='Bitey clav with an envelope-follower wah — dig in and it quacks. Ghost-note friendly. X: Color; Y: Ensemble.',
    sends=sends4(.4, .25, .1), motion_cat='Keys')
add('Harpsi Double', 'Keyboard',
    [dict(role='pluck', env=(.002, .5, .05, .4), cutoff=6500, level=.5),
     dict(role='mallet', env=(.002, .4, .05, .35), cutoff=7000, trans=12, level=.22)],
    glob=[.58, 112, .14, .35, .14, .06],
    fx={61: 1, 16: 1, 17: 260, 62: 1, 12: .35, 13: 1.0},
    detail='Quilled harpsichord with an octave double — baroque lines, short slapback. X: Color; Y: Ensemble.',
    sends=sends4(.5, .35, .2), motion_cat='Keys')
add('Mello Flute Keys', 'Keyboard',
    [dict(role='flute', env=(.03, .4, .7, .5), cutoff=3200, level=.6)],
    glob=[.58, 92, .1, .3, .26, .12],
    fx={61: 1, 16: 0, 17: 420, 62: 1, 12: .5, 13: 2.0, 63: 1},
    detail='Breathy flute-keys for slow melodies — long phrases, lots of air. X: Color; Y: Ensemble.',
    sends=sends4(.4, .6, .3), motion_cat='Keys')
add('Dulci Wire', 'Keyboard',
    [dict(role='mallet', env=(.002, .45, .06, .5), cutoff=5800, level=.58)],
    glob=[.6, 100, .16, .35, .2, .08],
    fx={61: 1, 16: 1, 17: 300, 60: 1, 23: .3, 25: 2.5, 28: .4, 62: 1,
        12: .4, 13: 1.3},
    detail='Hammered dulcimer with a breath of shimmer — fast runs sparkle. X: Color; Y: Ensemble.',
    sends=sends4(.45, .4, .55), motion_cat='Keys')

# -------------------------------- ORGAN (3) ------------------------------
add('Sunday Pipes', 'Organ',
    [dict(role='organ', env=(.03, .3, .95, .5), cutoff=5200, level=.6)],
    glob=[.62, 84, 0, .3, .4, .05],
    fx={62: 1, 12: 1, 13: 6},
    detail='Full chapel pipes under a cathedral ceiling. Hold big chords and listen upward. X: Color; Y: Ensemble.',
    sends=sends4(.05, .9, .2), motion_cat='Organs', force_motion=True)
add('Gospel Shout', 'Organ',
    [dict(role='organ', env=(.008, .2, .9, .3), cutoff=6000, level=.62,
          extra={36: 1})],
    glob=[.64, 116, .08, .3, .12, 0],
    fx={61: 1, 16: 1, 17: 240, 66: 1, 41: .8, 42: 5, 43: .8, 44: 2},
    detail='Shouting combo organ through a spinning rotary — fast Leslie, play rhythmic stabs. X: Color; Y: Ensemble.',
    sends=sends4(.4, .3, .1), motion_cat='Organs')
add('Chapel Dust', 'Organ',
    [dict(role='organ', env=(.05, .5, .85, 1.2), cutoff=1200, level=.6)],
    glob=[.58, 72, .14, .4, .42, 0],
    fx={61: 1, 16: 0, 17: 520, 62: 1, 12: .9, 13: 5, 60: 1, 23: .25,
        25: 4, 28: .35},
    detail='Dusty chapel organ dissolving into shimmer — sparse hymn fragments. X: Color; Y: Ensemble.',
    sends=sends4(.3, .8, .6), motion_cat='Organs', force_motion=True)

# ------------------------------- GUITAR (3) ------------------------------
add('Nylon Courtyard', 'Guitar',
    [dict(role='pluck', env=(.002, .55, .04, .5), cutoff=3400, level=.62)],
    glob=[.6, 96, .12, .3, .2, .05],
    fx={61: 1, 16: 1, 17: 280, 62: 1, 12: .35, 13: 1.1},
    detail='Warm nylon fingerpicking in a small courtyard. Thumb bass, singing treble. X: Color; Y: Ensemble.',
    sends=sends4(.4, .45, .15), motion_cat='Plucks')
add('Glass Twelve', 'Guitar',
    [dict(role='wire', env=(.002, .5, .06, .5), cutoff=5200, level=.5),
     dict(role='wire', env=(.002, .45, .05, .45), cutoff=6800, trans=12, level=.3)],
    glob=[.6, 108, .14, .35, .24, .14],
    fx={61: 1, 16: 1, 17: 340, 62: 1, 12: .45, 13: 1.6, 63: 1,
        60: 1, 23: .22, 25: 3, 28: .3},
    detail='Twelve-string shimmer — octave courses ringing through chorus and air. Strum wide open. X: Color; Y: Ensemble.',
    sends=sends4(.45, .5, .5), motion_cat='Plucks')
add('Ebow Prayer', 'Guitar',
    [dict(role='flute', env=(.6, 1.2, .9, 1.5), cutoff=2600, level=.6)],
    glob=[.58, 80, .16, .35, .3, 0],
    fx={61: 1, 16: 0, 17: 460, 62: 1, 12: .55, 13: 2.4, 64: 1},
    detail='Infinite-bow guitar note that never wants to land — slow phaser sweep carries it. One note is enough. X: Color; Y: Ensemble.',
    sends=sends4(.35, .65, .3), motion_cat='Plucks', force_motion=True,
    phaser=.5)

# -------------------------------- BASS (4) -------------------------------
add('Sub Marine', 'Bass',
    [dict(role='sub', env=(.004, .2, .75, .2), cutoff=700, level=.7,
          extra={41: 2, 15: -12})],
    glob=[.66, 100, 0, .3, .06, 0],
    fx={},
    detail='Clean deep-sea sub — mono, round, felt more than heard. Leave room below it. X: Color; Y: Ensemble.',
    sends=sends4(0, .15, 0), motion_cat='Bass')
add('Acid Garden', 'Bass',
    [dict(role='acid', env=(.003, .22, .5, .22), cutoff=1100, res=.5, level=.62,
          extra={41: 2, 42: .035})],
    glob=[.64, 126, .2, .4, .08, 0],
    fx={61: 1, 16: 1, 17: 300, 18: 1},
    detail='Resonant acid line with glide — write it a semitone too low, slide home. Ping-pong repeats. X: Color; Y: Ensemble.',
    sends=sends4(.6, .2, .1), motion_cat='Bass')
add('Fretless Rain', 'Bass',
    [dict(role='wire', env=(.01, .3, .65, .35), cutoff=2400, level=.6,
          extra={41: 2, 42: .05, 15: -12})],
    glob=[.62, 92, .12, .3, .2, .12],
    fx={61: 1, 16: 0, 17: 380, 62: 1, 12: .4, 13: 1.5, 63: 1},
    detail='Singing fretless that slides between every note — mwah for days. Legato lines only. X: Color; Y: Ensemble.',
    sends=sends4(.4, .45, .2), motion_cat='Bass')
add('Compactor', 'Bass',
    [dict(role='growl', env=(.002, .5, .6, .4), cutoff=2300, res=.3, level=.62,
          extra={41: 2})],
    glob=[.66, 110, .06, .3, .06, 0],
    fx={69: 1, 50: -18, 51: 4, 54: 4},
    detail='Punchy picked bass through a hard-working compressor — every note lands flat and loud. X: Color; Y: Ensemble.',
    sends=sends4(.15, .15, 0), motion_cat='Bass')

# ------------------------------ STRINGS (3) ------------------------------
add('Solo Thread', 'Strings',
    [dict(role='bowed', env=(.25, .4, .8, .8), cutoff=4200, level=.6)],
    glob=[.6, 84, .1, .3, .3, .1],
    fx={61: 1, 16: 0, 17: 440, 62: 1, 12: .55, 13: 2.2, 63: 1},
    detail='One violin, close-miked and emotional. Slow bows, heavy vibrato. X: Color; Y: Ensemble.',
    sends=sends4(.35, .6, .25), motion_cat='Strings', force_motion=True)
add('Amber Section', 'Strings',
    [dict(role='strings', env=(.15, .5, .8, 1.1), cutoff=3600, level=.58,
          extra={36: 3, 37: 10, 38: .8})],
    glob=[.6, 88, .08, .3, .32, .12],
    fx={62: 1, 12: .6, 13: 2.6, 63: 1},
    detail='Full string section in warm unison — swells and sustains, no soloists. X: Color; Y: Ensemble.',
    sends=sends4(.25, .65, .25), motion_cat='Strings', force_motion=True)
add('Pizz Corner', 'Strings',
    [dict(role='pluck', env=(.002, .22, .02, .28), cutoff=5000, level=.58)],
    glob=[.6, 104, .1, .3, .18, .05],
    fx={61: 1, 16: 1, 17: 230, 62: 1, 12: .3, 13: .8},
    detail='Dry pizzicato section, playful and precise. Short notes, quick rhythms. X: Color; Y: Ensemble.',
    sends=sends4(.35, .4, .1), motion_cat='Strings')

# ------------------------------- BRASS (3) -------------------------------
add('Copper Shout', 'Brass',
    [dict(role='brass', env=(.02, .3, .75, .35), cutoff=3400, res=.2, level=.6)],
    glob=[.62, 112, .12, .35, .14, .06],
    fx={61: 1, 16: 1, 17: 250},
    detail='Bright solo brass with attitude — short phrases, big accents. X: Color; Y: Ensemble.',
    sends=sends4(.45, .35, .1), motion_cat='Leads')
add('Flugel Dusk', 'Brass',
    [dict(role='brass', env=(.06, .4, .7, .6), cutoff=1400, level=.6)],
    glob=[.6, 84, .1, .3, .3, .08],
    fx={61: 1, 16: 0, 17: 430, 62: 1, 12: .5, 13: 2.0},
    detail='Mellow flugelhorn at last light — soft attacks, long goodbyes. X: Color; Y: Ensemble.',
    sends=sends4(.35, .6, .2), motion_cat='Leads')
add('Stab Alley', 'Brass',
    [dict(role='brass', env=(.004, .16, .1, .22), cutoff=3800, res=.25, level=.6),
     dict(role='brass', env=(.004, .14, .08, .2), cutoff=3000, trans=-12, level=.3)],
    glob=[.64, 120, .14, .35, .1, .12],
    fx={61: 1, 16: 1, 17: 270, 63: 1, 67: 1, 45: .3, 46: 10, 47: 2},
    detail='Gritty brass stab with an octave underbelly and a dirty edge. Hit it and run. X: Color; Y: Ensemble.',
    sends=sends4(.45, .3, .1), motion_cat='Leads')

# ----------------------------- WOODWIND (3) ------------------------------
add('Breath Flute', 'Woodwind',
    [dict(role='flute', env=(.05, .35, .7, .5), cutoff=3900, level=.58,
          extra={6: .18})],
    glob=[.58, 88, .1, .3, .28, .08],
    fx={61: 1, 16: 0, 17: 410, 62: 1, 12: .5, 13: 2.0},
    detail='Airy bamboo flute — as much breath as tone. Phrases that wander off. X: Color; Y: Ensemble.',
    sends=sends4(.35, .6, .25), motion_cat='Woodwinds', force_motion=True)
add('Reed Confession', 'Woodwind',
    [dict(role='reed', env=(.02, .3, .75, .4), cutoff=3000, level=.6)],
    glob=[.6, 92, .08, .3, .22, .1],
    fx={62: 1, 12: .45, 13: 1.8, 63: 1},
    detail='Warm clarinet telling secrets — soft tonguing, round middle register. X: Color; Y: Ensemble.',
    sends=sends4(.25, .55, .2), motion_cat='Woodwinds')
add('Oboe Lantern', 'Woodwind',
    [dict(role='reed', env=(.015, .3, .8, .45), cutoff=2800, res=.25, level=.58)],
    glob=[.6, 96, .1, .3, .24, .05],
    fx={62: 1, 12: .45, 13: 1.8, 68: 1, 56: .45, 57: 0, 58: .55},
    detail='Nasal double-reed glowing through a fixed vowel filter — ancient and reedy. X: Color; Y: Ensemble.',
    sends=sends4(.3, .55, .2), motion_cat='Woodwinds')

# ----------------------------- SYN LEAD (4) ------------------------------
add('Neon Suture', 'Syn Lead',
    [dict(role='wire', env=(.008, .3, .7, .3), cutoff=5200, res=.2, level=.56,
          extra={36: 8, 37: 11, 38: .85, 41: 2, 42: .03})],
    glob=[.6, 118, .24, .4, .14, .1],
    fx={61: 1, 16: 1, 17: 340, 18: 1, 63: 1},
    detail='Supersaw mono lead stitched wide — glide into every note, let the ping-pong answer. X: Color; Y: Ensemble.',
    sends=sends4(.6, .35, .2), motion_cat='Leads')
add('Mono Ribbon', 'Syn Lead',
    [dict(role='reed', env=(.01, .35, .75, .3), cutoff=3600, res=.3, level=.58,
          extra={1: 3, 41: 2, 42: .06})],
    glob=[.6, 104, .2, .35, .16, .12],
    fx={61: 1, 16: 1, 17: 360, 63: 1, 64: 1},
    detail='Singing mono ribbon — square-wave heart, endless glide, phaser swirling behind. X: Color; Y: Ensemble.',
    sends=sends4(.55, .4, .2), motion_cat='Leads', phaser=.35)
add('Glass Fang', 'Syn Lead',
    [dict(role='metal', env=(.005, .28, .6, .3), cutoff=6200, level=.5,
          extra={41: 2},
          fm=dict(algorithm=8, feedback=.35))],
    glob=[.58, 122, .2, .35, .12, .08],
    fx={61: 1, 16: 1, 17: 310, 67: 1, 45: .35, 46: 9, 47: 2},
    detail='Metallic FM fang over a hard edge — glassy, vicious, with crushed sparkle. X: Color; Y: Ensemble.',
    sends=sends4(.5, .3, .15), motion_cat='Leads')
add('Satin Laser', 'Syn Lead',
    [dict(role='wire', env=(.02, .4, .65, .4), cutoff=4400, level=.56,
          extra={41: 2, 42: .05})],
    glob=[.6, 100, .22, .35, .2, .1],
    fx={61: 1, 16: 0, 17: 400, 62: 1, 12: .4, 13: 1.5},
    detail='Soft sci-fi laser lines — gentle glide, slow PWM breathing underneath. X: Color; Y: Ensemble.',
    sends=sends4(.55, .5, .25), motion_cat='Leads', force_motion=True)

# ----------------------------- PAD/CHOIR (4) -----------------------------
add('Slow Honey', 'Pad/Choir',
    [dict(role='velvet', env=(.9, 1.4, .85, 2.6), cutoff=2800, level=.55)],
    glob=[.58, 82, .12, .35, .34, .14],
    fx={61: 1, 16: 0, 17: 500, 62: 1, 12: .6, 13: 3.0, 63: 1},
    detail='Warm analog honey poured very slowly — hold one chord and disappear into it. X: Color; Y: Ensemble.',
    sends=sends4(.35, .7, .3), motion_cat='Pads', force_motion=True)
add('Choir Loft', 'Pad/Choir',
    [dict(role='choir', env=(.5, 1.2, .85, 2.2), cutoff=5200, level=.55)],
    glob=[.58, 78, .1, .3, .4, .08],
    fx={62: 1, 12: .85, 13: 4.5},
    detail='Distant choir in a stone loft — vowels drifting, no words. Sing with it. X: Color; Y: Ensemble.',
    sends=sends4(.2, .85, .3), motion_cat='Pads', force_motion=True)
add('Glass Drift', 'Pad/Choir',
    [dict(role='glass', env=(.7, 1.5, .8, 2.8), cutoff=6800, level=.45),
     dict(role='glass', env=(.9, 1.6, .75, 3.0), cutoff=8200, trans=12, level=.2)],
    glob=[.56, 76, .14, .35, .36, .06],
    fx={61: 1, 16: 0, 17: 540, 62: 1, 12: .65, 13: 3.4, 60: 1, 23: .4,
        25: 5, 28: .5},
    detail='Ice crystals drifting through cathedral shimmer — high, weightless, endless. X: Color; Y: Ensemble.',
    sends=sends4(.35, .7, .7), motion_cat='Pads', force_motion=True)
add('Black Moss', 'Pad/Choir',
    [dict(role='sub', env=(1.1, 1.8, .85, 3.0), cutoff=900, level=.6,
          extra={15: -12})],
    glob=[.6, 70, .1, .35, .3, 0],
    fx={62: 1, 12: .7, 13: 4, 64: 1},
    detail='Dark subterranean bed that breathes through a slow phaser — beautiful dread. X: Color; Y: Ensemble.',
    sends=sends4(.2, .7, .2), motion_cat='Pads', force_motion=True,
    phaser=.4)

# ----------------------------- SYN COMP (3) ------------------------------
add('Gate Crasher', 'Syn Comp',
    [dict(role='pluck', env=(.002, .2, .15, .22), cutoff=4800, res=.25, level=.56,
          extra={22: 1, 23: 2, 24: 1, 25: 1, 26: .55})],
    glob=[.62, 124, .18, .35, .1, .08],
    fx={61: 1, 16: 1, 17: 300},
    detail='Gated rhythmic comp — hold a chord, the gate does the funk. Tight and hype. X: Color; Y: Ensemble.',
    sends=sends4(.5, .25, .1), motion_cat='Arps')
add('Sidechain Ghost', 'Syn Comp',
    [dict(role='velvet', env=(.01, .3, .5, .3), cutoff=2600, level=.55,
          extra={22: 1, 23: 2, 24: 0, 25: 1, 26: .6})],
    glob=[.6, 122, .1, .3, .16, .05],
    fx={66: 1, 41: .9, 42: 2.6, 43: .9, 62: 1, 12: .4, 13: 1.2},
    detail='Pumping dance comp that breathes around an invisible kick — four-on-the-floor required. X: Color; Y: Ensemble.',
    sends=sends4(.3, .45, .15), motion_cat='Arps')
add('Neon Stab', 'Syn Comp',
    [dict(role='digital', env=(.003, .18, .12, .25), cutoff=5600, level=.55,
          extra={22: 1, 23: 3, 24: 2, 25: 1, 26: .5})],
    glob=[.62, 128, .2, .35, .12, .14],
    fx={61: 1, 16: 1, 17: 280, 63: 1},
    detail='Bright digital stab-chords with chorus glitter — 80s rooftop at midnight. X: Color; Y: Ensemble.',
    sends=sends4(.5, .35, .15), motion_cat='Arps')

# --------------------------- CHROMATIC PERC (3) --------------------------
add('Music Box Ghost', 'Chromatic Perc',
    [dict(role='bell', env=(.002, 1.4, .05, 1.8), cutoff=9000, trans=12, level=.5)],
    glob=[.56, 92, .2, .4, .24, .05],
    fx={61: 1, 16: 1, 17: 420, 60: 1, 23: .35, 25: 4, 28: .45, 62: 1,
        12: .45, 13: 1.6},
    detail='A haunted music box two octaves up — tiny hammers, endless shimmer tail. Play sparse. X: Color; Y: Ensemble.',
    sends=sends4(.5, .45, .6), motion_cat='Keys')
add('Marimba Smoke', 'Chromatic Perc',
    [dict(role='mallet', env=(.002, .5, .08, .6), cutoff=4200, level=.58)],
    glob=[.6, 100, .12, .3, .18, .05],
    fx={61: 1, 16: 1, 17: 260, 62: 1, 12: .35, 13: 1.0},
    detail='Warm wooden marimba bars in a smoky room — round attack, gentle room. X: Color; Y: Ensemble.',
    sends=sends4(.4, .45, .15), motion_cat='Keys')
add('Steel Horizon', 'Chromatic Perc',
    [dict(role='metal', env=(.002, .8, .06, 1.0), cutoff=7000, level=.5)],
    glob=[.58, 104, .16, .35, .26, .12],
    fx={61: 1, 16: 0, 17: 380, 62: 1, 12: .5, 13: 2.2, 63: 1},
    detail='Resonant steel bars on the horizon — bright strike, long metallic bloom. X: Color; Y: Ensemble.',
    sends=sends4(.45, .55, .3), motion_cat='Keys')

# ------------------------------ SOUND FX (3) -----------------------------
add('Fog Horn Bay', 'Sound FX',
    [dict(role='brass', env=(1.2, 1.0, .9, 2.0), cutoff=900, level=.62,
          extra={15: -12})],
    glob=[.62, 70, .1, .3, .42, 0],
    fx={62: 1, 12: .9, 13: 6},
    detail='Harbor foghorn rolling over the water — lean on one low note and wait. X: Color; Y: Ensemble.',
    sends=sends4(.15, .9, .2), motion_cat='Textures', force_motion=True)
add('Laser Drawer', 'Sound FX',
    [dict(role='wire', env=(.002, .35, .05, .3), cutoff=7500, res=.4, level=.5)],
    glob=[.56, 132, .18, .4, .08, .05],
    fx={61: 1, 16: 1, 17: 180, 65: 1, 37: .5, 38: 4, 39: .8, 40: .7},
    detail='One zap from the cutlery drawer of the future — short, rude, flanged. X: Color; Y: Ensemble.',
    sends=sends4(.4, .2, .1), motion_cat='Textures')
add('Thunder Sheet', 'Sound FX',
    [dict(role='noise', env=(.05, 2.2, .1, 2.8), cutoff=1400, level=.85,
          extra={6: .5}),
     dict(role='sub', env=(.08, 1.8, .2, 2.4), cutoff=500, trans=-12,
          level=.4)],
    glob=[.62, 72, .08, .3, .4, 0],
    fx={62: 1, 12: .8, 13: 5, 69: 1, 50: -24, 51: 3, 54: 6},
    detail='Shaken thunder sheet over subterranean rumble in a canyon — distant at first, then everywhere. Strike once. X: Color; Y: Ensemble.',
    sends=sends4(.15, .85, .2), motion_cat='Textures', force_motion=True)

# ----------------------------- MUSICAL FX (3) ----------------------------
add('Arp Botanica', 'Musical FX',
    [dict(role='pluck', env=(.003, .3, .3, .4), cutoff=5200, level=.5,
          extra={22: 1, 23: 2, 24: 3, 25: 2, 26: .55})],
    glob=[.58, 108, .26, .4, .22, .1],
    fx={61: 1, 16: 1, 17: 360, 60: 1, 23: .35, 25: 3.5, 28: .45, 62: 1,
        12: .45, 13: 1.8},
    detail='A garden that arpeggiates itself — two-octave vines through shimmer and echo. Hold and wander. X: Color; Y: Ensemble.',
    sends=sends4(.6, .5, .6), motion_cat='Arps')
add('Granular Pond', 'Musical FX',
    [dict(role='glass', env=(.4, 1.6, .7, 2.4), cutoff=6000, level=.48)],
    glob=[.56, 80, .16, .35, .3, .08],
    fx={62: 1, 12: .6, 13: 3.2, 60: 1, 23: .5, 24: 7, 25: 6, 28: .6,
        66: 1, 41: .4, 42: .4, 43: .5},
    detail='Pebbles of glass audio dropped in a still pond — shimmer ripples, slow pan current. X: Color; Y: Ensemble.',
    sends=sends4(.3, .65, .7), motion_cat='Textures', force_motion=True)
add('Sweep Chapel', 'Musical FX',
    [dict(role='velvet', env=(.3, 2.0, .8, 2.5), cutoff=3600, res=.35, level=.52)],
    glob=[.58, 84, .14, .35, .32, .1],
    fx={62: 1, 12: .55, 13: 2.8, 64: 1},
    detail='Eight-second filter tide rolling through a chapel — one chord, endless motion. X: Color; Y: Ensemble.',
    sends=sends4(.3, .7, .3), motion_cat='Textures', force_motion=True,
    phaser=.45)

# ------------------------------- ETHNIC (3) ------------------------------
add('Sitar Monsoon', 'Ethnic',
    [dict(role='wire', env=(.004, .5, .12, .6), cutoff=4400, res=.45, level=.55),
     dict(role='wire', env=(.01, .6, .12, .7), cutoff=2200, trans=-12, level=.25)],
    glob=[.6, 96, .12, .3, .2, .1],
    fx={61: 1, 16: 1, 17: 290, 62: 1, 12: .4, 13: 1.4, 63: 1},
    detail='Buzzing sitar over its own drone string — ornaments and slides welcome. X: Color; Y: Ensemble.',
    sends=sends4(.4, .45, .2), motion_cat='Plucks')
add('Shakuhachi Mist', 'Ethnic',
    [dict(role='flute', env=(.08, .5, .65, .7), cutoff=3100, level=.56,
          extra={6: .22})],
    glob=[.58, 82, .1, .3, .3, .06],
    fx={61: 1, 16: 0, 17: 430, 62: 1, 12: .55, 13: 2.4},
    detail='Bamboo breath fading in and out of fog — start notes from silence. X: Color; Y: Ensemble.',
    sends=sends4(.3, .65, .25), motion_cat='Textures', force_motion=True)
add('Santur Spark', 'Ethnic',
    [dict(role='mallet', env=(.002, .4, .06, .55), cutoff=7200, level=.54)],
    glob=[.58, 116, .2, .4, .18, .08],
    fx={61: 1, 16: 1, 17: 250, 62: 1, 12: .35, 13: 1.0},
    detail='Seventy-two strings struck with tiny hammers — rapid dulcimer runs ignite. X: Color; Y: Ensemble.',
    sends=sends4(.5, .4, .2), motion_cat='Keys')


# ------------------------------- FM EP (5) -------------------------------
# Pure electric pianos: single FM layer (B/C/D off), natural decay (every op
# sustain level L3 == 0), velocity -> FM index. Distinct algorithms/ratios.
def ep_ops(tine_ratio, tine_level, body_level, bite_ratio, bite_level,
           dark=False):
    C = dict(rates=[110, 7, .22, 60], levels=[1, .55, 0, 0])
    M = dict(rates=[140, 9, .9, 45], levels=[1, .3, 0, 0])
    if dark:
        C = dict(rates=[48, 4, .15, 30], levels=[1, .58, 0, 0])
        M = dict(rates=[70, 6, .5, 30], levels=[1, .36, 0, 0])
    return [
        fm_op(ratio=1.0, level=.85, vel=.8, **C),
        fm_op(ratio=1.0, level=.8, vel=.8, fine=.003, **C),
        fm_op(ratio=1.0, level=body_level, vel=.8, **M),
        fm_op(ratio=tine_ratio, level=tine_level, vel=.75,
              rates=[200, 14, 1.0, 60], levels=[1, .12, 0, 0]),
    ]


def pack_fm(enabled, algorithm, feedback, ops, carrier_mix=.5):
    """Shape fm_op() dicts into the FmPatch JSON payload."""
    return dict(
        enabled=enabled, algorithm=algorithm, feedback=feedback,
        carrierMix=carrier_mix, pitchEnv=dict(amount=0, time=.05, curve=.5),
        ops={str(i): dict(
            wave=o['wave'], ratio=o['ratio'],
            fixedHz=o.get('fixedHz', 440.0), fixedMode=o.get('fixedMode', 0),
            fine=o.get('fine', 0.0), level=o['level'], vel=o['vel'],
            keyScale=o.get('keyScale', 0), keySync=o.get('keySync', 1),
            envMode=o.get('envMode', 0), pulseWidth=o.get('pulseWidth', .5),
            wtTable=o.get('wtTable', 0), wtPos=o.get('wtPos', .5),
            wtWarp=o.get('wtWarp', 0.0),
            env=dict(rates=list(o['env']['rates']),
                     levels=list(o['env']['levels'])))
            for i, o in enumerate(ops)})


EP_SPECS = [
    ('Tine Stage 76', 4, .3, dict(tine_ratio=14, tine_level=.24,
                                  body_level=.5, bite_ratio=0, bite_level=0),
     'Play with touch; A: classic stage tine — bell attack, singing body, natural decay. Velocity opens the bite. X: Color; Y: Ensemble.'),
    ('Suitcase Warmth', 5, .2, dict(tine_ratio=1, tine_level=.3,
                                    body_level=.42, bite_ratio=0, bite_level=0),
     'Play soft chords; A: round suitcase piano — pillowy attack, warm endlessly-decaying body. X: Color; Y: Ensemble.'),
    ('Glass Hammer', 6, .3, dict(tine_ratio=3.01, tine_level=.34,
                                 body_level=.48, bite_ratio=0, bite_level=0),
     'Strike firmly; A: glassy hammer EP — bright percussive top over a deep body. Velocity brings the sparkle. X: Color; Y: Ensemble.'),
    ('Midnight Felt', 7, .3, dict(tine_ratio=2.01, tine_level=.2,
                                  body_level=.32, bite_ratio=0, bite_level=0,
                                  dark=True),
     'Play at midnight; A: dark felted tine — muted, close, velvety, long slow decay into silence. X: Color; Y: Ensemble.'),
    ('Bell Reed 200', 2, .35, dict(tine_ratio=7.02, tine_level=.3,
                                   body_level=.46, bite_ratio=0, bite_level=0),
     'Play with touch; A: bell-forward reed piano — chime riding a warm reed body, decaying naturally. X: Color; Y: Ensemble.'),
]


def slug(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def build():
    patches = []
    # 50 MODX-category patches
    for e in R:
        layers = []
        fm_specs = []
        for vspec in e['voices']:
            spec = dict(vspec)
            fm_specs.append(spec.pop('fm', None))
            ex = spec.pop('extra', None)
            layers.append(voice(spec.pop('role'), spec.pop('env'),
                                spec.pop('cutoff'), res=spec.pop('res', None),
                                trans=spec.pop('trans', 0),
                                level=spec.pop('level', .6),
                                pan=spec.pop('pan', 0), extra=ex))
        assert not spec, f"unconsumed voice keys in {e['name']}: {spec}"
        pid = 'mx-' + slug(e['name'])
        fx = fx_chain(e['fx'])
        if e['cat'] not in ('Sound FX', 'Musical FX'):
            # House rule: delay lives only in FX-flavored categories.
            fx[61] = 0
        layers = apply_decay_rule(e['name'], layers)
        glob = lift(layers, list(e['glob']))
        for i, val in enumerate(glob):
            lo, hi = GRANGES[i]
            assert lo <= val <= hi, (e['name'], i, val)
        p = assemble_patch(pid, e['name'], e['cat'], e['detail'], layers,
                           glob, e['phaser'], fx, e['sends'],
                           e['motion_cat'], e['force_motion'])
        # Glass Fang carries an FM bite on layer 0 (kept: single character).
        if fm_specs[0] is not None:
            fs = fm_specs[0]
            ops = [fm_op(ratio=1, level=.4, vel=.7,
                         rates=[90, 8, .8, 40], levels=[1, .4, 0, 0]),
                   fm_op(ratio=2.99, level=.35, vel=.75,
                         rates=[120, 10, 1.0, 50], levels=[1, .2, 0, 0]),
                   fm_op(level=.7, rates=[80, 6, .5, 40],
                         levels=[1, .5, .4, 0]),
                   fm_op(ratio=7, level=.2, vel=.6,
                         rates=[200, 14, 1.2, 60], levels=[1, .1, 0, 0])]
            p['layers'][0]['fm'] = pack_fm(True, fs['algorithm'],
                                           fs['feedback'], ops)
        patches.append(p)
    # 5 FM EP patches
    for idx, (name, alg, fb, opspec, detail) in enumerate(EP_SPECS):
        v = base_values()
        v.update(TIMBRES['felt'])
        # Slightly distinct subtractive beds so the five never share a render
        # hash, even in harnesses that don't drive the FM engine.
        v.update({7: 2600 + [-200, 150, 350, -350, 50][idx],
                  9: .005, 10: 1.2, 11: .06, 12: 1.0,
                  13: .5 + [-.03, 0, .03, -.01, .02][idx], 15: 0})
        v = finish_layer(v)
        layers = [v, off_voice(), off_voice(), off_voice()]
        ops = ep_ops(**opspec)
        fm = pack_fm(True, alg, fb, ops)
        for op in fm['ops'].values():
            assert op['env']['levels'][2] == 0, 'pure EP must decay (L3=0)'
        pid = 'mxep-' + slug(name)
        # Pianos: no delay (house rule — delay lives in FX-flavored categories).
        fx = fx_chain({62: 1, 12: .45, 13: 1.8})
        glob = lift(apply_decay_rule(name, [v]), [.55, 100, .14, .3, .22, .06])
        p = assemble_patch(pid, name, 'FM EP', detail, [v], glob, 0, fx,
                           sends4(.4, .5, .2), 'Keys')
        p['layers'][0]['fm'] = fm
        # velocity -> FM index rides slot 2 (spec: source 9, destination 37+op)
        p['soundMatrix'][0][2] = route(9, 39, .5)
        patches.append(p)
    return patches


def main():
    patches = build()
    assert len(patches) == 55, len(patches)
    # Keep new ids/names distinct from the retired GB109 bank (archived, not shipped).
    gb = json.loads((ROOT / 'archive/factory-banks/v0.25.0/AuroraGB109.json').read_text())
    taken_ids = {x['id'] for x in gb}
    taken_names = {x['name'].lower() for x in gb}
    seen_ids, seen_names = set(), set()
    cats = {}
    for p in patches:
        assert p['id'] not in taken_ids, f"id collision: {p['id']}"
        assert p['name'].lower() not in taken_names, f"name collision: {p['name']}"
        assert p['id'] not in seen_ids and p['name'].lower() not in seen_names
        seen_ids.add(p['id'])
        seen_names.add(p['name'].lower())
        cats[p['category']] = cats.get(p['category'], 0) + 1
        assert 1 <= len(p['layers'][0]['values']) and p['layers'][0]['values']['0'] == 1
        live = sum(1 for l in p['layers'] if l['values']['0'] == 1)
        assert 1 <= live <= 2, (p['name'], live)
        assert len(p['customMacros']) == 8
        assert all(v['routes'] for v in p['customMacros'].values()), p['name']
        if p['name'] in DECAY_ZERO:
            for l in p['layers']:
                if l['values']['0'] == 1:
                    assert l['values']['11'] == 0, \
                        f"single-strike patch holds sustain: {p['name']}"
    print('category counts:', cats)
    assert sum(v for k, v in cats.items() if k != 'FM EP') == 50
    assert cats.get('FM EP') == 5
    (ROOT / 'Resources/AuroraFX.json').write_text(
        json.dumps(patches, indent=2) + '\n')
    print(f'AuroraFX: {len(patches)} patches written, '
          f'{sum(1 for p in patches if sum(1 for l in p["layers"] if l["values"]["0"] == 1) == 1)} single-layer, '
          f'{sum(1 for p in patches if sum(1 for l in p["layers"] if l["values"]["0"] == 1) == 2)} dual-layer.')


if __name__ == '__main__':
    main()
