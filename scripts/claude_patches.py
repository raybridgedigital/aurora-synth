#!/usr/bin/env python3
"""Claude-designed factory patches (name suffix " -CL" until the owner approves them).

Imported by scripts/assemble_modx_bank.py, which appends these after the 55 original
AuroraFX patches (those stay byte-identical). Every parameter is set by name from a
neutral layer: no hidden LFO wobble, filter envelope or drive unless a patch asks for it.

House rules applied here (PATCH-DESIGN-RULES.md):
- 1-2 layers (A, or A + B); layers C and D stay off.
- All ten effects are set up for the sound; only Reverb may ship on. Sound FX alone may
  ship other effects on.
- Struck and plucked sounds hold no sustain (layer sustain 0; every FM op L3 = 0).
- Master level is calibrated per patch (claude_levels.json, written from bench
  measurements) so new patches sit at one loudness.
"""
import json
import math
import re
from pathlib import Path

from rebuild_factory_bank import DEFAULTS, SPECS, motion, normalized

ROOT = Path(__file__).resolve().parent.parent
LEVELS = Path(__file__).resolve().parent / 'claude_levels.json'

# ----------------------------------------------------------------- layer params
P = dict(
    enabled=0, wave1=1, wave2=2, blend=3, detune=4, sub=5, noise=6, cutoff=7, res=8,
    attack=9, decay=10, sustain=11, release=12, level=13, pan=14, transpose=15,
    lfo1_rate=16, lfo1_depth=17, lfo1_dest=18, lfo1_shape=19, filter_env=20, drive=21,
    arp=22, arp_rate=23, arp_mode=24, arp_oct=25, arp_gate=26, key_low=27, key_high=28,
    lfo2_rate=29, lfo2_depth=30, lfo2_dest=31, filter_type=32, lfo2_shape=33,
    pw=34, pwm=35, unison=36, uni_detune=37, spread=38, sync=39, sync_tune=40,
    voice_mode=41, glide=42, bend=43,
    wt1=44, wt1_table=45, wt1_pos=46, wt1_warp_mode=47, wt1_warp=48, wt1_phase=49, wt1_random=50,
    wt2=51, wt2_table=52, wt2_pos=53, wt2_warp_mode=54, wt2_warp=55, wt2_phase=56, wt2_random=57,
    f2=58, f2_type=59, f2_cutoff=60, f2_res=61, f_routing=62, f_balance=63,
    mod_attack=64, mod_decay=65, mod_sustain=66, mod_release=67, mod_amount=68, mod_dest=69,
    osc_mod=70, osc_mod_amount=71, osc_mod_ratio=72,
    char=73, char_drive=74, char_mix=75, char_tone=76, char_bits=77, char_rate=78,
    f1_slope=79, f2_slope=80,
    lfo1_sync=81, lfo1_div=82, lfo1_retrig=83, lfo1_phase=84, lfo1_delay=85, lfo1_fade=86,
    lfo2_sync=87, lfo2_div=88, lfo2_retrig=89, lfo2_phase=90, lfo2_delay=91, lfo2_fade=92,
    wt1_formant=93, wt1_tone=94, wt2_formant=95, wt2_tone=96, arp_swing=97, arp_vel=98,
    lfo3_shape=99, lfo3_rate=100, lfo3_depth=101, lfo3_sync=102, lfo3_div=103,
    lfo3_retrig=104, lfo3_phase=105, lfo3_delay=106, lfo3_fade=107,
    lfo4_shape=108, lfo4_rate=109, lfo4_depth=110, lfo4_sync=111, lfo4_div=112,
    lfo4_retrig=113, lfo4_phase=114, lfo4_delay=115, lfo4_fade=116,
    lfo5_shape=117, lfo5_rate=118, lfo5_depth=119, lfo5_sync=120, lfo5_div=121,
    lfo5_retrig=122, lfo5_phase=123, lfo5_delay=124, lfo5_fade=125,
)
# Waves: 0 sine, 1 triangle, 2 saw, 3 pulse, 4 harmonic. Filter: 0 LP, 1 HP, 2 BP, 3 notch.
# LFO dest: 0 cutoff, 1 pitch, 2 pan, 3 amplitude. Voice: 0 poly, 1 mono, 2 legato.
# Mod env dest: 0 cutoff, 1 filter 2, 2 pitch, 3 osc mod, 4 character, 5 WT1 pos, 6 WT2 pos.
# Character: 0 off, 1 warm, 2 clip, 3 fold, 4 crush. Osc mod: 0 off, 1 phase, 2 FM, 3 ring.
# LFO division: 0 4 bars ... 4 1/4, 5 1/8, 6 1/16, 7 1/32, 8 1/8 dotted, 9 1/8 triplet.

NEUTRAL = {
    'wave1': 2, 'wave2': 1, 'blend': 0, 'detune': 0, 'sub': 0, 'noise': 0,
    'cutoff': 18000, 'res': 0, 'attack': .002, 'decay': 1.0, 'sustain': 1, 'release': .3,
    'level': .6, 'pan': 0, 'transpose': 0,
    'lfo1_rate': .5, 'lfo1_depth': 0, 'lfo1_dest': 0, 'lfo1_shape': 0,
    'filter_env': 0, 'drive': 0, 'arp': 0,
    # LFO 2 runs at a vocal vibrato rate: the mod wheel's built-in vibrato follows its phase.
    'lfo2_rate': 5.2, 'lfo2_depth': 0, 'lfo2_dest': 1, 'lfo2_shape': 0,
    'filter_type': 0, 'pw': .5, 'pwm': 0, 'unison': 1, 'uni_detune': 8, 'spread': .5,
    'sync': 0, 'sync_tune': 0, 'voice_mode': 0, 'glide': 0, 'bend': 2,
    'wt1': 0, 'wt2': 0, 'f2': 0, 'mod_amount': 0, 'osc_mod': 0, 'osc_mod_amount': 0,
    'char': 0, 'f1_slope': 0, 'f2_slope': 0,
}


def layer(**kw):
    """One layer from the neutral base; keyword names from P (unknown names are errors)."""
    v = dict(enumerate(DEFAULTS))
    merged = dict(NEUTRAL)
    merged.update(kw)
    v[0] = 1
    for name, val in merged.items():
        assert name in P, f'unknown layer parameter {name}'
        v[P[name]] = val
    out = {}
    for k, val in v.items():
        lo, hi, _log, integer = SPECS[k]
        assert math.isfinite(val) and lo <= val <= hi, f'layer param {k}={val} outside [{lo},{hi}]'
        out[k] = round(val) if integer else round(float(val), 7)
    return out


def off_layer():
    v = layer()
    v[0] = 0
    return v


# ------------------------------------------------------------------- FM layers
def op(ratio=1.0, level=.5, vel=.7, rates=(1000, 3, .5, 8), levels=(1, .6, 0, 0),
       fine=0.0, wave=0, ks=0, fixed=None, mode=2):
    """One FM operator. Level: carriers = amplitude; modulators = index (1.0 = 10 cycles,
    about 63 radians, so EP-style indices of 1-2 rad are levels near 0.02-0.03). Rate/level
    envelope (rates 0.02-1000): rises are linear, a full-scale rise takes 1/rate s; in mode 2
    (exponential, the default here) falls run at 96 dB per 1/rate s, so a 60 dB fall takes
    0.625/rate s (use fall_rate()); mode 0 falls are linear too. L3 is the held level."""
    assert all(.02 <= r <= 1000 for r in rates), rates
    return dict(wave=wave, ratio=ratio, fixedHz=fixed or 440.0, fixedMode=1 if fixed else 0,
                fine=fine, level=level, vel=vel, keyScale=ks, keySync=1, envMode=mode,
                pulseWidth=.5, wtTable=0, wtPos=.5, wtWarp=0.0,
                env=dict(rates=list(rates), levels=list(levels)))


def fall_rate(db, seconds):
    """Exponential-mode rate that falls `db` decibels in `seconds`."""
    return round(min(1000, max(.02, db / 96 / seconds)), 5)


def index_level(radians):
    """FM level that gives `radians` of peak phase deviation at full envelope/velocity."""
    return round(radians / (2 * math.pi * 10), 5)


def fm(algorithm, feedback, ops, carrier_mix=.5, pitch=(0.0, .05, .5)):
    assert len(ops) == 4
    return dict(enabled=True, algorithm=algorithm, feedback=feedback, carrierMix=carrier_mix,
                pitchEnv=dict(amount=pitch[0], time=pitch[1], curve=pitch[2]),
                ops={str(i): o for i, o in enumerate(ops)})


# FM algorithms (Sources/FmEngine.cpp): 4 EP Twin = op2->op0, op3->op1 (two pairs, fb op2);
# 12 Pure Additive = four carriers; 14 Twin Feedback = EP Twin with fb on op3;
# 9 Triple Crown = op3->op0 + carriers op1, op2 (fb op3); 13 Deep Feedback chain.
EP_TWIN, TRIPLE_CROWN, POST_STACK, PURE_ADDITIVE, TWIN_FEEDBACK = 4, 9, 10, 12, 14

# ---------------------------------------------------------------- mod matrices
SRC = dict(lfo1=0, lfo2=1, amp_env=2, mod_env=3, key=4, random=5, lfo3=6, lfo4=7, lfo5=8,
           velocity=9, pressure=10)
DST = {n: i for i, n in enumerate([
    'cutoff', 'pitch', 'pan', 'amplitude', 'blend', 'drive', 'lfo1_depth', 'lfo2_depth',
    'chorus', 'phaser', 'reverb', 'delay', 'wt1_pos', 'wt2_pos', 'wt1_warp', 'wt2_warp',
    'f2_cutoff', 'f2_res', 'osc_mod', 'char_drive', 'f_balance', 'res', 'pw', 'detune',
    'sub', 'noise', 'uni_detune', 'spread', 'sync_tune', 'wt1_formant', 'wt1_tone',
    'wt2_formant', 'wt2_tone', 'osc_mod_ratio', 'char_mix', 'char_tone', 'filter_env',
    'op1', 'op2', 'op3', 'op4', 'fm_feedback', 'fm_carrier_mix', 'fm_pitch_env',
    'fm_fine', 'wt_mod_pos', 'wt_mod_warp'])}
PERF_SRC = dict(wheel=0, velocity=1, pressure=2, expression=3, sustain=4, cc=5)


def rt(source=0, destination=0, amount=0.0, target=4, cc=1):
    return dict(enabled=amount != 0, source=source, destination=destination, target=target,
                cc=cc, amount=round(float(amount), 5))


def sound_routes(*routes):
    """Up to 10 (source, destination, amount) per layer, by name."""
    out = [rt(SRC[s], DST[d], a) for s, d, a in routes]
    assert len(out) <= 10
    return out + [rt() for _ in range(10 - len(out))]


def perf_routes(*routes):
    """Performance matrix: (source, destination, amount[, layer]) by name; 6 slots."""
    out = []
    for r in routes:
        s, d, a = r[:3]
        out.append(rt(PERF_SRC[s], DST[d], a, r[3] if len(r) > 3 else 4))
    assert len(out) <= 6
    return out + [rt() for _ in range(6 - len(out))]


# Expression pedal (CC11) always rides the level; every patch gets it.
BASE_PERF = [('expression', 'amplitude', .1)]

# ----------------------------------------------------------------------- effects
# Globals 0-5: master, tempo, delay mix, delay feedback, reverb mix, chorus mix. Patch fx
# keys: 7-9 phaser rate/depth/feedback, 10-11 chorus rate/depth, 12-13 reverb size/decay,
# 14 delay timing (0 1/4, 1 1/8, 2 1/16, 3 1/2, 4 1/8 dotted, 5 1/4 dotted, 6 1/8T, 7 1/4T),
# 16-19 delay sync/time ms/ping-pong/tone, 23-36 shimmer, 37-40 flanger, 41-44 tremolo
# (mode 0 tremolo, 1 pan, 2 rotary), 45-47 bitcrusher, 48-49 delay duck, 50-55 compressor,
# 56-59 auto-wah, 60-69 power (shimmer, delay, reverb, chorus, phaser, flanger, tremolo,
# crush, wah, comp), 70-72 reverb type/pre-delay/tone.
POWER = dict(shimmer=60, delay=61, reverb=62, chorus=63, phaser=64, flanger=65, tremolo=66,
             crush=67, wah=68, comp=69)
FX_KEYS = dict(
    phaser_rate=7, phaser_depth=8, phaser_feedback=9, chorus_rate=10, chorus_depth=11,
    reverb_size=12, reverb_decay=13, delay_timing=14, delay_sync=16, delay_ms=17,
    delay_pingpong=18, delay_tone=19, shimmer_mix=23, shimmer_pitch=24, shimmer_decay=25,
    shimmer_tone=26, shimmer_predelay=27, shimmer_amount=28, shimmer_v5=29, shimmer_v7=30,
    shimmer_v12=31, shimmer_reverse=32, shimmer_early=33, shimmer_early_size=34,
    shimmer_late=35, shimmer_late_decay=36, flanger_mix=37, flanger_rate=38,
    flanger_depth=39, flanger_feedback=40, trem_mix=41, trem_rate=42, trem_depth=43,
    trem_mode=44, crush_mix=45, crush_bits=46, crush_down=47, duck_amount=48,
    duck_release=49, comp_threshold=50, comp_ratio=51, comp_attack=52, comp_release=53,
    comp_makeup=54, comp_auto=55, wah_mix=56, wah_sens=57, wah_range=58, wah_mode=59,
    reverb_type=70, reverb_predelay=71, reverb_tone=72)
GLOBAL_FX = dict(delay_mix=2, delay_feedback=3, reverb_mix=4, chorus_mix=5)

# A musical default for every effect; families and patches override what matters.
FX_BASE = dict(
    phaser_rate=.35, phaser_depth=.7, phaser_feedback=.35, phaser_mix=.35,
    chorus_rate=.5, chorus_depth=.45, chorus_mix=.3,
    reverb_mix=.18, reverb_size=.45, reverb_decay=1.8, reverb_type=0, reverb_predelay=0,
    reverb_tone=.5,
    delay_mix=.16, delay_feedback=.28, delay_timing=4, delay_sync=1, delay_ms=375,
    delay_pingpong=1, delay_tone=.55, duck_amount=.3, duck_release=.4,
    shimmer_mix=.22, shimmer_pitch=12, shimmer_decay=4, shimmer_tone=.55,
    shimmer_predelay=30, shimmer_amount=.45, shimmer_v5=0, shimmer_v7=.3, shimmer_v12=.8,
    shimmer_reverse=0, shimmer_early=.4, shimmer_early_size=.4, shimmer_late=.7,
    shimmer_late_decay=4,
    flanger_mix=.35, flanger_rate=.25, flanger_depth=.6, flanger_feedback=.45,
    trem_mix=.6, trem_rate=4.5, trem_depth=.5, trem_mode=0,
    crush_mix=.35, crush_bits=10, crush_down=2,
    comp_threshold=-18, comp_ratio=3, comp_attack=8, comp_release=140, comp_makeup=3,
    comp_auto=0, wah_mix=.7, wah_sens=.55, wah_range=.6, wah_mode=0)

FAMILY_FX = {
    'keys': dict(chorus_rate=.55, chorus_depth=.4, chorus_mix=.3, phaser_rate=.3,
                 phaser_depth=.65, phaser_feedback=.3, phaser_mix=.35, trem_mode=1,
                 trem_rate=3.4, trem_depth=.45, trem_mix=.6, delay_timing=4,
                 delay_feedback=.25, delay_mix=.15, reverb_type=1, reverb_mix=.2,
                 reverb_size=.42, reverb_decay=2.0, reverb_predelay=18),
    'piano': dict(chorus_rate=.4, chorus_depth=.3, chorus_mix=.22, trem_mode=1,
                  trem_rate=2.5, trem_depth=.35, delay_timing=4, delay_feedback=.22,
                  delay_mix=.13, reverb_type=1, reverb_mix=.2, reverb_size=.5,
                  reverb_decay=2.2, reverb_predelay=15),
    'organ': dict(trem_mode=2, trem_rate=6.6, trem_depth=.7, trem_mix=.85,
                  chorus_rate=.8, chorus_depth=.3, chorus_mix=.25, reverb_type=0,
                  reverb_mix=.12, reverb_size=.5, reverb_decay=1.6, delay_timing=1,
                  delay_feedback=.2, delay_mix=.1, comp_threshold=-14, comp_ratio=2.5),
    'strings': dict(chorus_rate=.35, chorus_depth=.55, chorus_mix=.35, reverb_type=1,
                    reverb_mix=.26, reverb_size=.65, reverb_decay=3.0, reverb_predelay=20,
                    delay_timing=5, delay_feedback=.3, delay_mix=.14, phaser_rate=.12,
                    phaser_depth=.6, phaser_mix=.3),
    'brass': dict(chorus_rate=.45, chorus_depth=.35, chorus_mix=.25, reverb_type=1,
                  reverb_mix=.18, reverb_size=.5, reverb_decay=1.8, reverb_predelay=12,
                  delay_timing=4, delay_feedback=.22, delay_mix=.14, comp_threshold=-16),
    'lead': dict(delay_timing=4, delay_feedback=.35, delay_mix=.22, chorus_rate=.6,
                 chorus_depth=.35, chorus_mix=.25, reverb_type=1, reverb_mix=.16,
                 reverb_size=.45, reverb_decay=1.8, reverb_predelay=10, flanger_rate=.18,
                 flanger_mix=.35, phaser_rate=.45, phaser_mix=.4),
    'pad': dict(chorus_rate=.3, chorus_depth=.6, chorus_mix=.35, reverb_type=1,
                reverb_mix=.3, reverb_size=.75, reverb_decay=4.0, reverb_predelay=25,
                delay_timing=5, delay_feedback=.4, delay_mix=.18, shimmer_mix=.28,
                phaser_rate=.1, phaser_depth=.7, phaser_mix=.35, flanger_rate=.08),
    'comp': dict(delay_timing=4, delay_feedback=.3, delay_mix=.18, chorus_rate=.7,
                 chorus_depth=.35, chorus_mix=.28, reverb_type=0, reverb_mix=.15,
                 reverb_size=.4, reverb_decay=1.4, comp_threshold=-16, comp_ratio=4,
                 phaser_rate=.5),
    'bass': dict(chorus_rate=.6, chorus_depth=.3, chorus_mix=.2, reverb_type=0,
                 reverb_mix=.06, reverb_size=.3, reverb_decay=1.0, delay_timing=1,
                 delay_mix=.08, comp_threshold=-20, comp_ratio=4, comp_attack=12,
                 wah_mix=.8, wah_sens=.6, wah_range=.55),
    'perc': dict(reverb_type=1, reverb_mix=.2, reverb_size=.5, reverb_decay=2.2,
                 reverb_predelay=10, delay_timing=4, delay_feedback=.3, delay_mix=.16,
                 chorus_rate=.5, chorus_depth=.3, trem_mode=0, trem_rate=5.5,
                 trem_depth=.4),
    'wind': dict(reverb_type=1, reverb_mix=.22, reverb_size=.55, reverb_decay=2.4,
                 reverb_predelay=15, delay_timing=4, delay_feedback=.3, delay_mix=.16,
                 chorus_rate=.4, chorus_depth=.3),
    'guitar': dict(chorus_rate=.7, chorus_depth=.45, chorus_mix=.3, delay_timing=4,
                   delay_feedback=.3, delay_mix=.18, reverb_type=0, reverb_mix=.16,
                   reverb_size=.4, reverb_decay=1.6, trem_mode=0, trem_rate=5.0,
                   trem_depth=.5, wah_mix=.8, wah_sens=.6, wah_range=.6, comp_threshold=-18,
                   comp_ratio=4, phaser_rate=.4),
    'fx': dict(reverb_type=1, reverb_mix=.35, reverb_size=.9, reverb_decay=6.0,
               reverb_predelay=40, delay_timing=5, delay_feedback=.5, delay_mix=.28,
               shimmer_mix=.4, flanger_rate=.06, flanger_mix=.4),
}


def effects(family, on=('reverb',), sound_fx=False, **overrides):
    """(globals 2-5 values, phaser mix, fx dict). Only Reverb may ship on, except Sound FX."""
    s = dict(FX_BASE)
    s.update(FAMILY_FX[family])
    s.update(overrides)
    for name in on:
        assert name == 'reverb' or sound_fx, f'only Reverb may ship on ({name})'
    fx = {}
    for name, key in FX_KEYS.items():
        fx[key] = s[name]
    for name, key in POWER.items():
        fx[key] = 1 if name in on else 0
    glob = {GLOBAL_FX[k]: s[k] for k in GLOBAL_FX}
    from assemble_modx_bank import GRANGES, GINTEGER
    for k, v in list(fx.items()) + list(glob.items()):
        lo, hi = GRANGES[k]
        assert lo <= v <= hi, f'effect value {k}={v} outside [{lo},{hi}]'
        if k in GINTEGER:
            fx[k] = round(v) if k in fx else v
    assert 0 <= s['phaser_mix'] <= 1
    return glob, s['phaser_mix'], fx


# ------------------------------------------------------------------------ macros
def macro_set(p, spec):
    """8 custom macros: spec = [(name, [(layer, param-name or -global-index, span), ...])].
    Every route is symmetric around the stored value, so macro 0.5 = the patch as saved."""
    out = {}
    names = []
    for m in range(8):
        name, routes = spec[m] if m < len(spec) else (None, [])
        rr = []
        for l, param, span in routes:
            if l < 0:
                k = param
                v = p['globals'][k] if k < 6 else p['fx'][str(k)]
                shared = True
            else:
                k = P[param]
                v = p['layers'][l]['values'][str(k)]
                shared = False
            center = normalized(v, k, shared)
            s = min(span, center, 1 - center)
            if s <= 1e-6:
                continue
            rr.append({'id': f'm{m}-l{l}-p{k}', 'target': {'layer': l, 'parameter': k},
                       'from': round(center - s, 6), 'to': round(center + s, 6)})
        out[str(m)] = dict(name=name or f'Macro {m + 1}', routes=rr)
        names.append(name)
    # Unused slots: a whisper of reverb (keeps CustomMacro.valid; audible only if moved).
    for m in range(8):
        if not out[str(m)]['routes']:
            v = p['globals'][4]
            center = normalized(v, 4, True)
            s = min(.05, center, 1 - center) or .01
            lo, hi = max(0, center - s), min(1, center + s)
            out[str(m)] = dict(name=out[str(m)]['name'] if names[m] else 'Space',
                               routes=[{'id': f'm{m}-l-1-p4', 'target': {'layer': -1, 'parameter': 4},
                                        'from': round(lo, 6), 'to': round(hi, 6)}])
    return out


# ------------------------------------------------------------------------ patches
PATCHES = []


def patch(name, category, detail, layers, family, *, fm_layers=None, glob=None,
          on=('reverb',), sound_fx=False, fx=None, sends=None, sound=None, perf=None,
          macros=None, struck=False, motion_layers=None, tempo=110):
    PATCHES.append(dict(name=name, category=category, detail=detail, layers=layers,
                        family=family, fm_layers=fm_layers or {}, on=on, sound_fx=sound_fx,
                        fx=fx or {}, sends=sends, sound=sound or {}, perf=perf or [],
                        macros=macros or [], struck=struck, motion_layers=motion_layers or {},
                        tempo=tempo))


def slug(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def base_name(name):
    return name[:-4] if name.endswith(' -CL') else name


def disabled_motion(v, l):
    m = motion(v, 'Keys', 0, l)
    m['enabled'] = False
    for r in m['routes']:
        r['enabled'] = False
    return m


def motion_env(seconds, points, routes, loop=False):
    """An enabled motion envelope. routes: {index: (min, max)} with 0 amplitude, 1 cutoff Hz,
    2 pitch st, 3 pan, 4/5 WT 1/2 position, 6/7 WT 1/2 warp."""
    lo = [0, 400, 0, -1, 0, 0, 0, 0]
    hi = [1, 6000, 12, 1, 1, 1, 1, 1]
    rr = [dict(enabled=i in routes, minimum=routes.get(i, (lo[i], hi[i]))[0],
               maximum=routes.get(i, (lo[i], hi[i]))[1], inverted=False) for i in range(8)]
    return dict(enabled=True, loop=loop, seconds=seconds, beats=None, grid=0,
                points=[dict(x=x, y=y, curve=c) for x, y, c in points], routes=rr)


def build():
    levels = json.loads(LEVELS.read_text()) if LEVELS.exists() else {}
    out = []
    for e in PATCHES:
        layers = list(e['layers'])
        assert 1 <= len(layers) <= 2, e['name']
        if e['struck']:
            for v in layers:
                v[P['sustain']] = 0
        full = layers + [off_layer() for _ in range(4 - len(layers))]
        strlayers = [{'values': {str(k): val for k, val in v.items()}} for v in full]
        for l, f in e['fm_layers'].items():
            if e['struck']:
                for o in f['ops'].values():
                    assert o['env']['levels'][2] == 0, f"{e['name']}: struck FM op holds (L3 > 0)"
            strlayers[l]['fm'] = f
        gfx, phaser, fx = effects(e['family'], on=e['on'], sound_fx=e['sound_fx'], **e['fx'])
        pid = ('mxep-' if e['category'] == 'FM EP' else 'mx-') + slug(base_name(e['name']))
        cal = levels.get(pid, {})
        if isinstance(cal, (int, float)):
            cal = {'master': cal}
        master = cal.get('master', .5)
        scale = cal.get('level_scale', 1.0)
        if scale != 1.0:
            for l in range(len(layers)):
                key = str(P['level'])
                strlayers[l]['values'][key] = round(min(1.0, strlayers[l]['values'][key] * scale), 7)
        glob = [master, e['tempo'], gfx[2], gfx[3], gfx[4], gfx[5]]
        mo = [disabled_motion(full[l], l) for l in range(4)]
        for l, m in e['motion_layers'].items():
            mo[l] = m
        sends = e['sends'] or [dict(delay=.5, reverb=.6, shimmer=.4, shimmerBypass=False)
                               for _ in range(4)]
        matrix = [sound_routes(*e['sound'].get(l, [])) for l in range(4)]
        p = dict(id=pid, name=e['name'], category=e['category'], detail=e['detail'],
                 layers=strlayers, globals=glob, phaserMix=phaser,
                 fx={str(k): v for k, v in sorted(fx.items())}, macros=[.5] * 8,
                 motion=mo, sends=sends, soundMatrix=matrix,
                 performanceMatrix=perf_routes(*(BASE_PERF + e['perf'])),
                 xy=dict(x=dict(macro=0, start=0, end=1), y=dict(macro=1, start=0, end=1)))
        p['customMacros'] = macro_set(p, e['macros'])
        assert len(e['detail']) <= 500, e['name']
        out.append(p)
    return out


# =============================================================================
# FM EP (4)
# =============================================================================
# DX7-style electric piano (the 1983 E.PIANO 1 recipe): two carrier/modulator pairs on the
# EP Twin algorithm. Pair A (op2 -> op0) is the body, 1:1 with a touch of feedback; pair B
# (op3 -> op1) is the tine, a 14:1 modulator whose sidebands (13th and 15th harmonics) ring
# for a fraction of a second. The two carriers are 3 cents apart for the slow shimmer of
# the original's detuned pairs. Velocity drives both indices: soft is round, hard barks.
def dx_ep_ops(body=1.6, tine=1.0, tine_ratio=14.0, body_ratio=1.0, detune=.03,
              body_time=2.8, tine_time=.4, carrier_vel=1.0, mod_vel=.9, attack=1000):
    """Exponential (DX-style) envelopes. Carriers: a 4 dB settle in 0.25 s, then a slow fall
    (the layer's amp envelope sets the note's overall decay). Body index: -6 dB in 0.3 s,
    then 60 dB over body_time. Tine index: -12 dB in 60 ms, then 60 dB over tine_time."""
    carrier = dict(rates=(attack, fall_rate(4.4, .25), fall_rate(60, 20), fall_rate(60, .35)),
                   levels=(1, .6, 0, 0))
    return [
        op(1.0, .72, carrier_vel, ks=1, **carrier),
        op(1.0, .6, carrier_vel, fine=detune, ks=1, **carrier),
        op(body_ratio, index_level(body), mod_vel, ks=1,
           rates=(1000, fall_rate(6, .3), fall_rate(60, body_time), fall_rate(60, .3)),
           levels=(1, .5, 0, 0)),
        op(tine_ratio, index_level(tine), mod_vel, ks=1,
           rates=(1000, fall_rate(12, .06), fall_rate(60, tine_time), fall_rate(60, .2)),
           levels=(1, .25, 0, 0)),
    ]


# Decay 5.5 s: a pedalled note lives 1.33 x Decay, so this keeps pedalled voice counts sane.
EP_LAYER = dict(cutoff=12000, attack=.001, decay=5.5, sustain=0, release=.45, level=.7,
                char=1, char_drive=.06, char_mix=.2, char_tone=.7)
EP_MACROS = [('Brightness', [(0, 'cutoff', .16)]), ('Decay', [(0, 'decay', .12), (0, 'release', .12)]),
             ('Grit', [(0, 'char_drive', .2)]), ('Space', [(-1, 4, .12)])]

patch('Eighty-Three Tines -CL', 'FM EP',
      'The 1983 FM electric piano: glassy tine on top, round body underneath, a slow shimmer '
      'between two detuned pairs. Soft touch stays mellow, hard touch barks. Play ballad '
      'chords with the pedal. X: Brightness; Y: Decay.',
      [layer(**dict(EP_LAYER, char_drive=.08, char_mix=.25))], 'keys',
      fm_layers={0: fm(EP_TWIN, .35, dx_ep_ops(), carrier_mix=.45)},
      macros=EP_MACROS, struck=True)

patch('Ballad Glass -CL', 'FM EP',
      'A rounder, softer FM piano for quiet verses: gentle tine, warm body, a wider chorus '
      'between the pairs and a long singing decay. Play it sparse and let notes ring. '
      'X: Brightness; Y: Decay.',
      [layer(**dict(EP_LAYER, cutoff=7000, release=.6))], 'keys',
      fm_layers={0: fm(EP_TWIN, .15, dx_ep_ops(body=1.05, tine=.55, detune=.05,
                                                body_time=3.5, attack=150), carrier_mix=.5)},
      fx=dict(reverb_mix=.24, reverb_decay=2.6, reverb_predelay=24),
      macros=EP_MACROS, struck=True)

patch('Tine Bark -CL', 'FM EP',
      'Funk and soul FM piano with teeth: touch decides everything, from a clean ping to a '
      'growling bark with a little grit. Comp sixteenths and dig in on the accents. '
      'X: Brightness; Y: Decay.',
      [layer(**dict(EP_LAYER, cutoff=14000, decay=4.5, release=.25, char_drive=.18,
                    char_mix=.4, char_tone=.75))], 'keys',
      fm_layers={0: fm(EP_TWIN, .55, dx_ep_ops(body=2.2, tine=1.3, body_time=1.8,
                                                mod_vel=1.0, carrier_vel=1.0), carrier_mix=.4)},
      sound={0: [('velocity', 'char_drive', .25)]},
      fx=dict(reverb_mix=.14, reverb_type=0, reverb_decay=1.4, reverb_predelay=8),
      macros=EP_MACROS, struck=True)

patch('Bell Tine Nineties -CL', 'FM EP',
      'The glossy 90s R&B ballad piano: a clear bell partial over a soft round body, '
      'shimmering and wide. Lush slow chords, pedal down. X: Brightness; Y: Decay.',
      [layer(**dict(EP_LAYER, cutoff=10000, release=.55))], 'keys',
      fm_layers={0: fm(EP_TWIN, .1, dx_ep_ops(body=.9, tine=1.25, tine_ratio=3.5, detune=.045,
                                                body_time=3.2, tine_time=1.6, attack=400),
                       carrier_mix=.5)},
      fx=dict(reverb_mix=.26, reverb_decay=2.8, reverb_predelay=22),
      macros=EP_MACROS, struck=True)


# =============================================================================
# Keyboard (4)
# =============================================================================
KEY_TRACK = ('key', 'cutoff', .6)          # ~80 % filter key tracking

patch('Wurli Smoke -CL', 'Keyboard',
      'Reed piano in the Wurlitzer tradition: warm and nasal when you play softly, a growling '
      'bark when you dig in. Soul ballads, Supertramp-style riffs. The preset Tremolo is the '
      'classic vibrato switch. X: Bark; Y: Decay.',
      [layer(wave1=3, pw=.36, wave2=1, blend=.35, cutoff=1500, res=.12, filter_env=.3,
             attack=.002, decay=3.2, sustain=0, release=.22, level=.7, drive=.12, char=1,
             char_drive=.12, char_mix=.35, char_tone=.55)], 'keys', struck=True,
      sound={0: [('velocity', 'cutoff', .28), ('velocity', 'drive', .35), KEY_TRACK]},
      fx=dict(trem_mode=0, trem_rate=5.6, trem_depth=.35, trem_mix=.7, reverb_type=0,
              reverb_mix=.14, reverb_size=.35, reverb_decay=1.4, reverb_predelay=8),
      macros=[('Bark', [(0, 'drive', .2), (0, 'cutoff', .1)]),
              ('Decay', [(0, 'decay', .12), (0, 'release', .1)]),
              ('Warmth', [(0, 'char_drive', .2)]), ('Space', [(-1, 4, .12)])])

patch('Pianet Spark -CL', 'Keyboard',
      'A short, woody reed pluck after the Hohner Pianet: bright tick, quick bloom, gone. '
      'Great for sixties pop comping and staccato hooks. X: Tone; Y: Decay.',
      [layer(wave1=2, wave2=3, pw=.3, blend=.3, cutoff=2200, res=.18, filter_env=.35,
             attack=.001, decay=1.1, sustain=0, release=.07, level=.66, f2=1, f2_type=1,
             f2_cutoff=180)], 'keys', struck=True,
      sound={0: [('velocity', 'cutoff', .3), KEY_TRACK]},
      fx=dict(reverb_type=0, reverb_mix=.12, reverb_size=.3, reverb_decay=1.2),
      macros=[('Tone', [(0, 'cutoff', .14)]), ('Decay', [(0, 'decay', .14)]),
              ('Snap', [(0, 'filter_env', .15)]), ('Space', [(-1, 4, .12)])])

patch('Clav Stax -CL', 'Keyboard',
      'Funk clavinet with a darker, thicker bite than a bright wah clav: tight strings, fast '
      'mute on release. Play choppy sixteenths; the preset Auto-wah turns it into Superstition. '
      'X: Bite; Y: Decay.',
      [layer(wave1=3, pw=.18, wave2=2, blend=.25, cutoff=2600, res=.35, filter_env=.45,
             attack=.001, decay=.55, sustain=0, release=.05, level=.62, f2=1, f2_type=1,
             f2_cutoff=260, f2_res=.1)], 'keys', struck=True,
      sound={0: [('velocity', 'cutoff', .35), ('key', 'cutoff', .5)]},
      fx=dict(wah_mix=.8, wah_sens=.65, wah_range=.65, wah_mode=1, reverb_type=0,
              reverb_mix=.08, reverb_size=.25, reverb_decay=1.0, phaser_rate=.5),
      macros=[('Bite', [(0, 'cutoff', .12), (0, 'res', .12)]), ('Decay', [(0, 'decay', .15)]),
              ('Thin', [(0, 'f2_cutoff', .15)]), ('Space', [(-1, 4, .1)])])

patch('Harmonium Porch -CL', 'Keyboard',
      'Pump harmonium: two reeds a hair apart, a little bellows breath and a gentle swell. '
      'Folk hymns, drones under a vocal, film scores. X: Reeds; Y: Bellows.',
      [layer(wave1=2, wave2=3, pw=.4, blend=.4, detune=5, cutoff=2400, res=.08, attack=.07,
             sustain=.92, release=.18, level=.6, noise=.035, lfo1_dest=3, lfo1_rate=.35,
             lfo1_depth=.06, unison=2, uni_detune=4, spread=.4, f2=1, f2_type=1, f2_cutoff=110)],
      'organ',
      fx=dict(reverb_type=0, reverb_mix=.14, reverb_decay=1.6, trem_mode=0, trem_rate=4.2),
      macros=[('Reeds', [(0, 'detune', .15), (0, 'blend', .12)]),
              ('Bellows', [(0, 'lfo1_depth', .1)]), ('Tone', [(0, 'cutoff', .12)]),
              ('Space', [(-1, 4, .12)])])

# =============================================================================
# Piano (3)
# =============================================================================
patch('House Piano 90 -CL', 'Piano',
      'The bright, punchy early-90s house piano: a hollow FM body with a bell pair on top. '
      'Block chords on the offbeat, one note per finger, lots of velocity. X: Brightness; '
      'Y: Decay.',
      [layer(cutoff=11000, attack=.001, decay=4.5, sustain=0, release=.35, level=.72, char=1,
             char_drive=.06, char_mix=.2, char_tone=.75)], 'piano', struck=True,
      fm_layers={0: fm(EP_TWIN, .3, [
          op(1.0, .75, 1.0, ks=1, rates=(1000, fall_rate(5, .2), fall_rate(60, 12), fall_rate(60, .3)),
             levels=(1, .55, 0, 0)),
          op(1.0, .55, 1.0, fine=.02, ks=1,
             rates=(1000, fall_rate(8, .15), fall_rate(60, 6), fall_rate(60, .3)), levels=(1, .4, 0, 0)),
          op(2.0, index_level(1.4), .9, ks=1,
             rates=(1000, fall_rate(8, .12), fall_rate(60, 1.6), fall_rate(60, .3)), levels=(1, .4, 0, 0)),
          op(4.0, index_level(1.1), .9, ks=1,
             rates=(1000, fall_rate(10, .08), fall_rate(60, 1.0), fall_rate(60, .2)), levels=(1, .3, 0, 0)),
      ], carrier_mix=.4)},
      fx=dict(reverb_type=1, reverb_mix=.16, reverb_decay=1.8, reverb_predelay=12),
      macros=EP_MACROS)

patch('Electric Grand 80 -CL', 'Piano',
      'Electric grand in the CP-80 spirit: string twang up top, a slightly out-of-tune '
      'chorus between unisons, a strong midrange that cuts through a band. 80s ballads and '
      'new wave. X: Brightness; Y: Decay.',
      [layer(cutoff=9000, attack=.001, decay=6.0, sustain=0, release=.4, level=.72, char=1,
             char_drive=.05, char_mix=.2, char_tone=.7)], 'piano', struck=True,
      fm_layers={0: fm(EP_TWIN, .25, [
          op(1.0, .7, 1.0, ks=1, rates=(1000, fall_rate(4, .2), fall_rate(60, 16), fall_rate(60, .35)),
             levels=(1, .6, 0, 0)),
          op(1.0, .55, 1.0, fine=.06, ks=1,
             rates=(1000, fall_rate(4, .2), fall_rate(60, 12), fall_rate(60, .35)), levels=(1, .6, 0, 0)),
          op(1.0, index_level(1.8), .9, ks=1,
             rates=(1000, fall_rate(8, .2), fall_rate(60, 2.2), fall_rate(60, .3)), levels=(1, .4, 0, 0)),
          op(3.0, index_level(.9), .9, ks=1,
             rates=(1000, fall_rate(12, .08), fall_rate(60, .7), fall_rate(60, .2)), levels=(1, .25, 0, 0)),
      ], carrier_mix=.45)},
      sound={0: [('key', 'cutoff', .4)]},
      macros=EP_MACROS)

patch('Lo-Fi Upright -CL', 'Piano',
      'A worn upright through an old tape machine: soft hammers, a little wow and flutter, '
      'crushed top end. Hip-hop chords, bedroom ballads. X: Tape; Y: Crush.',
      [layer(wave1=1, wave2=2, blend=.3, detune=3, cutoff=1900, res=.05, filter_env=.25,
             attack=.002, decay=2.8, sustain=0, release=.45, level=.72, noise=.02, char=4,
             char_drive=.2, char_bits=9, char_rate=.45, char_mix=.35, char_tone=.4, lfo1_dest=1,
             lfo1_rate=.55, lfo1_depth=.035)], 'piano', struck=True,
      sound={0: [('velocity', 'cutoff', .25), ('key', 'cutoff', .5)]},
      fx=dict(reverb_type=0, reverb_mix=.12, reverb_size=.3, reverb_decay=1.2, crush_mix=.4),
      macros=[('Tape', [(0, 'lfo1_depth', .12)]), ('Crush', [(0, 'char_mix', .25)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

# =============================================================================
# Organ (4) — drawbars on the Pure Additive FM algorithm
# =============================================================================
def drawbars(ratios, levels, perc=None):
    """Four sine carriers held at full (organ sustain); `perc` = (ratio, level) makes the
    fourth a fast-decaying percussion harmonic instead."""
    ops = [op(r, l, 0, rates=(1000, 1, 1, 40), levels=(1, 1, 1, 0), mode=0)
           for r, l in zip(ratios, levels)]
    if perc:
        ops[3] = op(perc[0], perc[1], .3, rates=(1000, fall_rate(60, .45), 1, 40),
                    levels=(1, 0, 0, 0))
    return ops


CLICK = layer(wave1=0, noise=.9, cutoff=3200, filter_type=2, res=.3, attack=.001, decay=.02,
              sustain=0, release=.01, level=.16)
ORGAN_LAYER = dict(cutoff=16000, attack=.003, sustain=1, release=.035, level=.6, char=1,
                   char_drive=.05, char_mix=.3, char_tone=.7)

patch('Drawbar Jazz -CL', 'Organ',
      'Jazz tonewheel organ: 16, 5 1/3 and 8 foot drawbars out, third-harmonic percussion and '
      'key click. Walk the bass with your left hand; the preset Tremolo is a rotary speaker. '
      'X: Drive; Y: Click.',
      [layer(**ORGAN_LAYER), CLICK], 'organ',
      fm_layers={0: fm(PURE_ADDITIVE, 0, drawbars([.5, 1.0, 1.5, 3.0], [.8, .8, .8, .7],
                                                   perc=(3.0, .7)), carrier_mix=.75)},
      fx=dict(trem_rate=.8, trem_depth=.55),
      macros=[('Drive', [(0, 'char_drive', .15)]), ('Click', [(1, 'level', .1)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .1)])])

patch('Rock Drive -CL', 'Organ',
      'All drawbars out into an overdriven amp: the rock organ that growls on chords and '
      'screams on glissandos. The preset Tremolo is a fast rotary. X: Drive; Y: Click.',
      [layer(**dict(ORGAN_LAYER, cutoff=7000, char_drive=.38, char_mix=.85, char_tone=.6,
                    level=.5)), CLICK], 'organ',
      fm_layers={0: fm(PURE_ADDITIVE, 0, drawbars([.5, 1.0, 2.0, 4.0], [.8, .8, .7, .6]),
                       carrier_mix=.75)},
      fx=dict(trem_rate=6.6, trem_depth=.75, comp_threshold=-12),
      macros=[('Drive', [(0, 'char_drive', .2)]), ('Click', [(1, 'level', .1)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .1)])])

patch('Combo Sixty -CL', 'Organ',
      'Transistor combo organ from the garage-band sixties: buzzy squares at 8 and 4 foot. '
      'Ninety-six Tears, ska upstrokes, surf. The preset Tremolo is its vibrato. X: Tone; '
      'Y: Octave.',
      [layer(wave1=3, pw=.5, wave2=3, sync=1, sync_tune=12, blend=.4, cutoff=4200, res=.1,
             attack=.004, sustain=1, release=.05, level=.56, f2=1, f2_type=1, f2_cutoff=220)],
      'organ', fx=dict(trem_mode=0, trem_rate=6.2, trem_depth=.3, reverb_type=0, reverb_mix=.12),
      macros=[('Tone', [(0, 'cutoff', .14)]), ('Octave', [(0, 'blend', .2)]),
              ('Buzz', [(0, 'pw', .15)]), ('Space', [(-1, 4, .1)])])

patch('Musette Café -CL', 'Organ',
      'Paris musette accordion: three reeds tuned apart for that shimmering wobble, a breath '
      'of bellows. Waltzes, tangos, café scenes. X: Musette; Y: Bellows.',
      [layer(wave1=2, wave2=3, pw=.45, blend=.45, detune=14, unison=3, uni_detune=11,
             spread=.5, cutoff=2800, res=.06, attack=.035, sustain=.95, release=.1, level=.6,
             lfo1_dest=3, lfo1_rate=.4, lfo1_depth=.05, f2=1, f2_type=1, f2_cutoff=140)],
      'organ', fx=dict(reverb_type=1, reverb_mix=.16, reverb_decay=1.8),
      macros=[('Musette', [(0, 'uni_detune', .2), (0, 'detune', .15)]),
              ('Bellows', [(0, 'lfo1_depth', .1)]), ('Tone', [(0, 'cutoff', .12)]),
              ('Space', [(-1, 4, .12)])])

# =============================================================================
# Strings (4)
# =============================================================================
patch('Solina Glow -CL', 'Strings',
      'String machine glow: a buzzing ensemble of saws, thin at the bottom and shimmering on '
      'top, straight out of 70s disco and space rock. The preset Chorus deepens the '
      'ensemble. X: Ensemble; Y: Attack.',
      [layer(wave1=2, wave2=2, detune=7, blend=.5, unison=3, uni_detune=14, spread=.85,
             cutoff=5200, attack=.28, sustain=1, release=1.1, level=.62, f2=1, f2_type=1,
             f2_cutoff=240, lfo1_dest=1, lfo1_rate=5.8, lfo1_depth=.012)], 'strings',
      fx=dict(chorus_depth=.7, chorus_mix=.4),
      macros=[('Ensemble', [(0, 'uni_detune', .2)]), ('Attack', [(0, 'attack', .15)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Cinema Section -CL', 'Strings',
      'A big, slow-swelling string section with the upper octave floating above it: film '
      'cues, worship swells, the last chorus. Hold chords and let them bloom. X: Swell; '
      'Y: Octave.',
      [layer(wave1=2, wave2=2, detune=8, blend=.5, unison=2, uni_detune=10, spread=.7,
             cutoff=2600, res=.05, filter_env=.18, attack=.55, sustain=.95, release=1.6,
             level=.6, f2=1, f2_type=1, f2_cutoff=120, lfo3_rate=.15),
       layer(wave1=2, wave2=2, detune=6, blend=.5, transpose=12, unison=1, uni_detune=8,
             spread=.9, cutoff=5000, attack=.8, sustain=.9, release=1.8, level=.22, f2=1,
             f2_type=1, f2_cutoff=400)], 'strings',
      sound={0: [('lfo3', 'cutoff', .04)]},
      fx=dict(reverb_mix=.28, reverb_decay=3.2, reverb_size=.7),
      macros=[('Swell', [(0, 'attack', .15), (1, 'attack', .15)]), ('Octave', [(1, 'level', .15)]),
              ('Tone', [(0, 'cutoff', .12), (1, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Staccato Bows -CL', 'Strings',
      'Short, bitey string section for rhythm: spiccato eighths, pop-string stabs, driving '
      'ostinatos. Velocity sets the bite. X: Length; Y: Bite.',
      [layer(wave1=2, wave2=2, detune=8, blend=.5, unison=2, uni_detune=10, spread=.6,
             cutoff=3400, res=.08, filter_env=.25, attack=.012, decay=.5, sustain=.38,
             release=.16, level=.8, f2=1, f2_type=1, f2_cutoff=160)], 'strings',
      sound={0: [('velocity', 'cutoff', .25)]},
      fx=dict(reverb_mix=.2, reverb_decay=1.8),
      macros=[('Length', [(0, 'decay', .15), (0, 'release', .15)]),
              ('Bite', [(0, 'filter_env', .15)]), ('Tone', [(0, 'cutoff', .12)]),
              ('Space', [(-1, 4, .12)])])

patch('Cello Lament -CL', 'Strings',
      'A solo cello line: legato slides, a woody body resonance and vibrato that blooms as '
      'the note holds. Channel pressure deepens the vibrato. Play one voice, slowly. '
      'X: Vibrato; Y: Bow.',
      [layer(wave1=2, wave2=3, pw=.35, blend=.3, cutoff=2100, res=.18, filter_env=.12,
             attack=.14, sustain=.95, release=.35, level=.7, voice_mode=2, glide=.07,
             lfo1_dest=1, lfo1_rate=5.3, lfo1_depth=.03, lfo1_delay=.4, lfo1_fade=.6, f2=1,
             f2_type=2, f2_cutoff=900, f2_res=.2, f_routing=2, f_balance=.3, noise=.02)],
      'strings', perf=[('pressure', 'lfo1_depth', .3)],
      fx=dict(reverb_mix=.22, reverb_decay=2.4),
      macros=[('Vibrato', [(0, 'lfo1_depth', .12)]), ('Bow', [(0, 'attack', .15)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

# =============================================================================
# Brass (4)
# =============================================================================
patch('Jump Brass -CL', 'Brass',
      'The bright synth-brass stab of 80s rock anthems: two detuned saws, a blatty filter '
      'bite on every chord. Big block chords on the beat. X: Brightness; Y: Blat.',
      [layer(wave1=2, wave2=2, detune=9, blend=.5, unison=2, uni_detune=7, spread=.6,
             cutoff=1900, res=.12, attack=.008, decay=.4, sustain=.85, release=.28, level=.62,
             mod_attack=.01, mod_decay=.45, mod_sustain=.35, mod_release=.3, mod_amount=.3,
             mod_dest=0, drive=.1)], 'brass',
      sound={0: [('velocity', 'cutoff', .2)]},
      macros=[('Brightness', [(0, 'cutoff', .12)]), ('Blat', [(0, 'mod_amount', .12)]),
              ('Release', [(0, 'release', .12)]), ('Space', [(-1, 4, .12)])])

patch('Section Punch -CL', 'Brass',
      'A tight horn section for funk and soul hits: fast swell, short fall, all punch. Stab '
      'the offbeats. X: Punch; Y: Length.',
      [layer(wave1=2, wave2=3, pw=.4, blend=.35, detune=6, unison=2, uni_detune=9,
             cutoff=1500, res=.1, attack=.02, decay=.3, sustain=.6, release=.12, level=.68,
             mod_attack=.035, mod_decay=.2, mod_sustain=.25, mod_amount=.38, mod_dest=0,
             drive=.15)], 'brass',
      sound={0: [('velocity', 'cutoff', .3)]},
      fx=dict(reverb_type=0, reverb_mix=.14, reverb_decay=1.3),
      macros=[('Punch', [(0, 'mod_amount', .12)]),
              ('Length', [(0, 'decay', .14), (0, 'release', .14)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Horn Swell -CL', 'Brass',
      'Warm French horns swelling in slowly: film pads, hymn endings, a soft bed under a '
      'ballad. Channel pressure opens them up. X: Swell; Y: Warmth.',
      [layer(wave1=2, wave2=1, blend=.4, detune=5, unison=2, uni_detune=6, spread=.5,
             cutoff=900, res=.05, filter_env=.3, attack=.3, sustain=.9, release=.7, level=.72,
             f2=1, f2_type=1, f2_cutoff=130)], 'brass', perf=[('pressure', 'cutoff', .15)],
      fx=dict(reverb_mix=.24, reverb_decay=2.6),
      macros=[('Swell', [(0, 'attack', .15)]), ('Warmth', [(0, 'cutoff', .14)]),
              ('Release', [(0, 'release', .12)]), ('Space', [(-1, 4, .12)])])

patch('Muted Noir -CL', 'Brass',
      'A harmon-muted trumpet for film noir and late-night jazz: nasal, breathy, with a '
      'vibrato that arrives late. Play single lines; pressure opens the mute. X: Mute; '
      'Y: Vibrato.',
      [layer(wave1=3, pw=.22, wave2=2, blend=.3, cutoff=1700, res=.42, filter_env=.2,
             attack=.035, sustain=.85, release=.14, level=.66, voice_mode=2, glide=.05,
             noise=.025, lfo1_dest=1, lfo1_rate=5.6, lfo1_depth=.025, lfo1_delay=.35,
             lfo1_fade=.4, f2=1, f2_type=1, f2_cutoff=500)], 'brass',
      perf=[('pressure', 'cutoff', .2)],
      fx=dict(reverb_mix=.2, reverb_predelay=15),
      macros=[('Mute', [(0, 'res', .12), (0, 'cutoff', .1)]), ('Vibrato', [(0, 'lfo1_depth', .1)]),
              ('Breath', [(0, 'noise', .05)]), ('Space', [(-1, 4, .12)])])

# =============================================================================
# Syn Lead (5)
# =============================================================================
patch('Sawtooth Sermon -CL', 'Syn Lead',
      'The fat mono saw lead: two detuned saws over a sub, a squelch on every attack and '
      'legato glide. Solos that preach. Mod wheel adds vibrato and brightness. X: Cutoff; '
      'Y: Glide.',
      [layer(wave1=2, wave2=2, detune=10, blend=.5, sub=.3, cutoff=2200, res=.3,
             attack=.004, sustain=1, release=.14, level=.6, voice_mode=2, glide=.06,
             mod_attack=.003, mod_decay=.35, mod_sustain=.35, mod_amount=.32, mod_dest=0,
             drive=.15)], 'lead', perf=[('wheel', 'cutoff', .15), ('pressure', 'cutoff', .15)],
      macros=[('Cutoff', [(0, 'cutoff', .14)]), ('Glide', [(0, 'glide', .12)]),
              ('Drive', [(0, 'drive', .15)]), ('Space', [(-1, 4, .12)])])

patch('Sync Scream -CL', 'Syn Lead',
      'Hard-sync lead that tears open on each note and settles into a singing tone. New wave '
      'solos, rock hooks. Pressure pushes the sync harder. X: Scream; Y: Sweep.',
      [layer(wave1=2, wave2=2, sync=1, sync_tune=9, blend=.85, cutoff=6000, res=.1,
             attack=.004, sustain=1, release=.14, level=.52, voice_mode=2, glide=.04,
             mod_attack=.002, mod_decay=.6, mod_sustain=.3, mod_amount=0, drive=.1)], 'lead',
      sound={0: [('mod_env', 'sync_tune', .3), ('pressure', 'sync_tune', .15)]},
      macros=[('Scream', [(0, 'sync_tune', .15)]), ('Sweep', [(0, 'mod_decay', .15)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Whistle Portamento -CL', 'Syn Lead',
      'A soft, pure whistle of a lead with slow glide and a vibrato that blooms: ballad '
      'melodies, Morricone lines, a voice-like counter-melody. X: Glide; Y: Vibrato.',
      [layer(wave1=1, wave2=0, blend=.5, cutoff=5000, attack=.02, sustain=1, release=.22,
             level=.9, drive=.12, voice_mode=2, glide=.12, lfo1_dest=1, lfo1_rate=5.4, lfo1_depth=.03,
             lfo1_delay=.3, lfo1_fade=.5)], 'lead',
      fx=dict(reverb_mix=.2, reverb_decay=2.2),
      macros=[('Glide', [(0, 'glide', .15)]), ('Vibrato', [(0, 'lfo1_depth', .1)]),
              ('Tone', [(0, 'blend', .2)]), ('Space', [(-1, 4, .12)])])

patch('Chip Square -CL', 'Syn Lead',
      'An 8-bit square lead with game-console crunch: fast runs, arpeggio-style melodies, '
      'chiptune hooks. X: Duty; Y: Crunch.',
      [layer(wave1=3, pw=.5, blend=0, cutoff=12000, attack=.003, sustain=1, release=.06,
             level=.45, voice_mode=1, char=4, char_bits=5, char_rate=.5, char_mix=1,
             char_drive=.2)], 'lead',
      fx=dict(reverb_type=0, reverb_mix=.1, delay_timing=4, delay_mix=.2),
      macros=[('Duty', [(0, 'pw', .2)]), ('Crunch', [(0, 'char_rate', .2)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .1)])])

patch('Vowel Talker -CL', 'Syn Lead',
      'A talking lead: every note says "wow" through a vocal wavetable, and the mod wheel '
      'changes the vowel. Talk-box funk lines, robot hooks. X: Vowel; Y: Sweep.',
      [layer(wt1=1, wt1_table=6, wt1_pos=.2, cutoff=4800, res=.15, attack=.01, sustain=1,
             release=.15, level=.8, voice_mode=2, glide=.05, mod_attack=.08, mod_decay=.7,
             mod_sustain=.4, mod_amount=.35, mod_dest=5, drive=.1)], 'lead',
      sound={0: [('pressure', 'wt1_pos', .3)]}, perf=[('wheel', 'wt1_pos', .35)],
      macros=[('Vowel', [(0, 'wt1_pos', .15)]), ('Sweep', [(0, 'mod_amount', .15)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

# =============================================================================
# Pad/Choir (6)
# =============================================================================
patch('Polyester Pad -CL', 'Pad/Choir',
      'The 80s polysynth pad: pulse-width shimmer and a warm saw underneath. Sustained '
      'chords that move by themselves; the preset Chorus is the famous stereo wash. '
      'X: Warmth; Y: PWM.',
      [layer(wave1=3, pw=.5, pwm=.45, lfo1_rate=.55, wave2=2, blend=.3, detune=6, unison=2,
             uni_detune=7, spread=.8, cutoff=2400, res=.12, filter_env=.08, attack=.4,
             sustain=.9, release=1.4, level=.62, f2=1, f2_type=1, f2_cutoff=180)], 'pad',
      fx=dict(chorus_depth=.7, chorus_mix=.4),
      macros=[('Warmth', [(0, 'cutoff', .14)]), ('PWM', [(0, 'pwm', .15)]),
              ('Attack', [(0, 'attack', .15)]), ('Space', [(-1, 4, .12)])])

patch('Breath Choir -CL', 'Pad/Choir',
      'An airy choir of vocal wavetables: ooh drifting toward aah, breath in the tone. Hold '
      'wide chords under a ballad or a hymn. X: Vowel; Y: Air.',
      [layer(wt1=1, wt1_table=19, wt1_pos=.35, wt2=1, wt2_table=5, wt2_pos=.55, blend=.45,
             detune=6, unison=2, uni_detune=9, spread=.9, noise=.07, cutoff=5500, res=.05,
             attack=.55, sustain=.95, release=1.6, level=.85, f2=1, f2_type=1, f2_cutoff=140,
             lfo3_rate=.13)], 'pad',
      sound={0: [('lfo3', 'wt1_pos', .1)]},
      fx=dict(reverb_mix=.32),
      macros=[('Vowel', [(0, 'wt1_pos', .2)]), ('Air', [(0, 'noise', .05)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Dark Matter -CL', 'Pad/Choir',
      'A slow, dark, living drone: two atmospheric wavetables drifting at different speeds '
      'under a closed filter. Cinematic intros, tension beds, ambient sets. X: Depth; Y: '
      'Attack.',
      [layer(wt1=1, wt1_table=16, wt1_pos=.2, wt2=1, wt2_table=18, wt2_pos=.4, blend=.5,
             detune=4, cutoff=800, res=.25, attack=1.8, sustain=.9, release=3.0, level=.72,
             unison=2, uni_detune=8, spread=.8, f2=1, f2_type=1, f2_cutoff=90, lfo3_rate=.05,
             lfo4_rate=.047, lfo5_rate=.031)], 'pad',
      sound={0: [('lfo3', 'cutoff', .08), ('lfo4', 'wt1_pos', .25), ('lfo5', 'wt2_pos', .25),
                 ('lfo4', 'pan', .3)]},
      fx=dict(reverb_mix=.35, reverb_decay=5.0),
      macros=[('Depth', [(0, 'cutoff', .14)]), ('Attack', [(0, 'attack', .12)]),
              ('Resonance', [(0, 'res', .12)]), ('Space', [(-1, 4, .12)])])

patch('Glass Halo -CL', 'Pad/Choir',
      'A bell-pad halo: every chord strikes like glass, then melts into a soft shimmering pad '
      'with an octave floating above. Christmas ballads, intros, worship. X: Brightness; '
      'Y: Shimmer.',
      [layer(wt1=1, wt1_table=10, wt1_pos=.35, wt2=1, wt2_table=22, wt2_pos=.5, blend=.45,
             detune=5, unison=2, uni_detune=7, spread=.8, cutoff=3800, res=.1, attack=.02,
             decay=1.5, sustain=.75, release=1.6, level=.72, mod_attack=.001, mod_decay=1.2,
             mod_sustain=.15, mod_release=1.0, mod_amount=.35, mod_dest=0, f2=1, f2_type=1,
             f2_cutoff=160, lfo3_rate=.11),
       layer(wave1=0, transpose=12, attack=1.2, sustain=.9, release=1.6, level=.18)], 'pad',
      sound={0: [('lfo3', 'wt1_pos', .12)]},
      fx=dict(shimmer_mix=.3, reverb_mix=.32),
      macros=[('Brightness', [(0, 'cutoff', .14)]), ('Shimmer', [(1, 'level', .12)]),
              ('Attack', [(0, 'attack', .12), (1, 'attack', .12)]), ('Space', [(-1, 4, .12)])])

patch('CS Sunrise -CL', 'Pad/Choir',
      'The Blade Runner brass pad: detuned saws whose filter rises slowly like a sunrise, '
      'with a late, gentle vibrato. Channel pressure opens it further. Hold long chords. '
      'X: Sunrise; Y: Warmth.',
      [layer(wave1=2, wave2=2, detune=8, blend=.5, unison=2, uni_detune=6, spread=.7,
             cutoff=700, res=.28, attack=.45, sustain=.9, release=2.2, level=.62,
             mod_attack=1.4, mod_decay=2.5, mod_sustain=.55, mod_release=2.0, mod_amount=.42,
             mod_dest=0, lfo1_dest=1, lfo1_rate=5.1, lfo1_depth=.012, lfo1_delay=1.0,
             lfo1_fade=1.5, f2=1, f2_type=1, f2_cutoff=110)], 'pad',
      perf=[('pressure', 'cutoff', .2)],
      fx=dict(reverb_mix=.36, reverb_decay=5.0, reverb_predelay=30),
      macros=[('Sunrise', [(0, 'mod_amount', .12)]), ('Warmth', [(0, 'cutoff', .14)]),
              ('Attack', [(0, 'attack', .12)]), ('Space', [(-1, 4, .12)])])

patch('Soft Cloud -CL', 'Pad/Choir',
      'A light, airy pad that stays out of the way: high, soft and wide, with almost no low '
      'end, made to sit under a piano or a vocal (a Dual Patch partner). X: Air; '
      'Y: Brightness.',
      [layer(wave1=1, wave2=0, blend=.4, detune=5, unison=3, uni_detune=9, spread=1.0,
             noise=.03, cutoff=4200, attack=.8, sustain=.9, release=2.0, level=.85, f2=1,
             f2_type=1, f2_cutoff=200, lfo3_rate=.09)], 'pad',
      sound={0: [('lfo3', 'cutoff', .05)]},
      fx=dict(reverb_mix=.34, reverb_predelay=30),
      macros=[('Air', [(0, 'noise', .05)]), ('Brightness', [(0, 'cutoff', .14)]),
              ('Attack', [(0, 'attack', .12)]), ('Space', [(-1, 4, .12)])])

# =============================================================================
# Syn Comp (4)
# =============================================================================
patch('Supersaw Anthem -CL', 'Syn Comp',
      'Trance and big-room supersaw: a wall of detuned saws for anthem chords and stabs. '
      'Short release keeps it tight; widen it with Y. X: Tone; Y: Width.',
      [layer(wave1=2, wave2=2, detune=11, blend=.4, unison=5, uni_detune=22, spread=.95,
             cutoff=5200, res=.05, filter_env=.12, attack=.004, decay=.9, sustain=.65,
             release=.28, level=.85, f2=1, f2_type=1, f2_cutoff=170)], 'comp',
      sound={0: [('velocity', 'cutoff', .15)]},
      fx=dict(reverb_type=1, reverb_mix=.18, reverb_decay=2.0),
      macros=[('Tone', [(0, 'cutoff', .12)]), ('Width', [(0, 'uni_detune', .15)]),
              ('Length', [(0, 'release', .15)]), ('Space', [(-1, 4, .12)])])

patch('Lagoon Pluck -CL', 'Syn Comp',
      'Tropical-house pluck: a soft, round snap that sits perfectly in offbeat chord '
      'patterns. The preset Delay (dotted eighths) makes it bounce. X: Pluck; Y: Length.',
      [layer(wave1=1, wave2=2, blend=.35, cutoff=700, res=.35, attack=.001, decay=.5,
             sustain=0, release=.25, level=.72, mod_attack=.001, mod_decay=.16, mod_sustain=0,
             mod_amount=.55, mod_dest=0, unison=2, uni_detune=6, spread=.6)], 'comp',
      struck=True, sound={0: [('velocity', 'cutoff', .2)]},
      macros=[('Pluck', [(0, 'mod_amount', .12)]), ('Length', [(0, 'decay', .15)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Funk Poly -CL', 'Syn Comp',
      'A snappy analog poly for funk comping: saw and pulse through a quick filter envelope, '
      'velocity decides the bite. Short chords, lots of space. X: Snap; Y: Length.',
      [layer(wave1=2, wave2=3, pw=.42, blend=.4, detune=7, cutoff=1300, res=.3, attack=.002,
             decay=.35, sustain=.3, release=.14, level=.68, mod_attack=.001, mod_decay=.22,
             mod_sustain=.1, mod_amount=.42, mod_dest=0)], 'comp',
      sound={0: [('velocity', 'cutoff', .25)]},
      macros=[('Snap', [(0, 'mod_amount', .12)]), ('Length', [(0, 'decay', .15)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Reso Stab 90 -CL', 'Syn Comp',
      'A resonant early-90s house stab: a squelchy filter blip on every chord. Play '
      'rhythmic stabs; turn Y for more squelch. X: Sweep; Y: Resonance.',
      [layer(wave1=2, wave2=3, pw=.5, blend=.45, cutoff=900, res=.72, attack=.001, decay=.28,
             sustain=0, release=.1, level=.6, mod_attack=.001, mod_decay=.17, mod_sustain=0,
             mod_amount=.5, mod_dest=0, f2=1, f2_type=1, f2_cutoff=150)], 'comp', struck=True,
      fx=dict(reverb_type=0, reverb_mix=.16),
      macros=[('Sweep', [(0, 'mod_amount', .12)]), ('Resonance', [(0, 'res', .1)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

# =============================================================================
# Chromatic Perc (3)
# =============================================================================
patch('Vibes Night Club -CL', 'Chromatic Perc',
      'Vibraphone with the motor on: soft mallets, a metallic bar partial and a slow '
      'amplitude shimmer. Jazz ballads, lounge chords; use the sustain pedal like the real '
      'damper bar. X: Motor; Y: Decay.',
      [layer(cutoff=12000, attack=.001, decay=5.5, sustain=0, release=.7, level=.72,
             lfo1_dest=3, lfo1_rate=5.2, lfo1_depth=.7)], 'perc', struck=True,
      fm_layers={0: fm(EP_TWIN, 0, [
          op(1.0, .75, .95, ks=1, rates=(1000, fall_rate(5, .3), fall_rate(60, 12), fall_rate(60, .5)),
             levels=(1, .6, 0, 0)),
          op(4.0, .2, .95, ks=1, rates=(1000, fall_rate(12, .3), fall_rate(60, 1.2), fall_rate(60, .3)),
             levels=(1, .3, 0, 0)),
          op(1.0, index_level(.5), .9, rates=(1000, fall_rate(12, .15), fall_rate(60, 1.0), fall_rate(60, .3)),
             levels=(1, .3, 0, 0)),
          op(1.0, index_level(.3), .9, rates=(1000, fall_rate(12, .15), fall_rate(60, .8), fall_rate(60, .3)),
             levels=(1, .3, 0, 0)),
      ], carrier_mix=.25)},
      macros=[('Motor', [(0, 'lfo1_depth', .15)]), ('Decay', [(0, 'decay', .12)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Glock Candy -CL', 'Chromatic Perc',
      'Glockenspiel built from its real bar partials (1, 2.76, 5.4, 8.9): a bright, pure '
      'ding that rings two octaves up. Melodies over pads, Christmas, music-box lines. '
      'X: Decay; Y: Brightness.',
      [layer(cutoff=18000, attack=.001, decay=3.0, sustain=0, release=.9, level=.6,
             transpose=24)], 'perc', struck=True,
      fm_layers={0: fm(PURE_ADDITIVE, 0, [
          op(1.0, 1.0, .9, rates=(1000, fall_rate(6, .3), fall_rate(60, 3.0), fall_rate(60, .8)), levels=(1, .5, 0, 0)),
          op(2.76, .5, .8, rates=(1000, fall_rate(10, .3), fall_rate(60, 1.6), fall_rate(60, .6)), levels=(1, .35, 0, 0)),
          op(5.40, .32, .9, rates=(1000, fall_rate(14, .2), fall_rate(60, .9), fall_rate(60, .4)), levels=(1, .25, 0, 0)),
          op(8.93, .18, .9, rates=(1000, fall_rate(18, .1), fall_rate(60, .5), fall_rate(60, .3)), levels=(1, .2, 0, 0)),
      ], carrier_mix=.5)},
      fx=dict(reverb_mix=.22, reverb_decay=2.5),
      macros=[('Decay', [(0, 'decay', .12), (0, 'release', .12)]), ('Brightness', [(0, 'cutoff', .1)]),
              ('Level', [(0, 'level', .1)]), ('Space', [(-1, 4, .12)])])

patch('Kalimba Sun -CL', 'Chromatic Perc',
      'Thumb piano: a round, woody pluck with the kalimba\'s high overtone ringing briefly on '
      'top. Afro-pop riffs, lullabies, bright arpeggios. X: Pluck; Y: Decay.',
      [layer(cutoff=9000, attack=.001, decay=1.8, sustain=0, release=.25, level=.72)], 'perc',
      struck=True,
      fm_layers={0: fm(EP_TWIN, 0, [
          op(1.0, .75, .95, rates=(1000, fall_rate(8, .12), fall_rate(60, 1.6), fall_rate(60, .3)), levels=(1, .4, 0, 0)),
          op(6.0, .22, .85, fine=-.05, rates=(1000, fall_rate(20, .1), fall_rate(60, .35), fall_rate(60, .2)),
             levels=(1, .15, 0, 0)),
          op(1.0, index_level(.8), .9, rates=(1000, fall_rate(15, .05), fall_rate(60, .4), fall_rate(60, .2)),
             levels=(1, .2, 0, 0)),
          op(3.0, index_level(.4), .9, rates=(1000, fall_rate(15, .05), fall_rate(60, .3), fall_rate(60, .2)),
             levels=(1, .2, 0, 0)),
      ], carrier_mix=.3)},
      macros=[('Pluck', [(0, 'cutoff', .12)]), ('Decay', [(0, 'decay', .14)]),
              ('Level', [(0, 'level', .1)]), ('Space', [(-1, 4, .12)])])

# =============================================================================
# Woodwind (2), Guitar (2), Bass (2), Ethnic (1)
# =============================================================================
patch('Pan Flute Andes -CL', 'Woodwind',
      'Pan flute with breath and chiff: a pure tone wrapped in air, vibrato that comes in '
      'late. Andean melodies, film themes, meditation. X: Breath; Y: Vibrato.',
      [layer(wave1=0, wave2=1, blend=.35, noise=.12, cutoff=3200, res=.05, filter_env=.25,
             attack=.045, sustain=.9, release=.22, level=.72, lfo1_dest=1, lfo1_rate=5.0,
             lfo1_depth=.02, lfo1_delay=.3, lfo1_fade=.5)], 'wind',
      fx=dict(reverb_mix=.26),
      macros=[('Breath', [(0, 'noise', .06)]), ('Vibrato', [(0, 'lfo1_depth', .1)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Clarinet Shadow -CL', 'Woodwind',
      'A clarinet voice: hollow odd harmonics, a woody tone that brightens as you play '
      'higher and harder, legato slurs. Klezmer, jazz, chamber lines. X: Reed; Y: Breath.',
      [layer(wave1=3, pw=.5, wave2=1, blend=.2, cutoff=1600, res=.1, filter_env=.18,
             attack=.04, sustain=.92, release=.12, level=.66, voice_mode=2, glide=.03,
             noise=.018, lfo1_dest=1, lfo1_rate=5.2, lfo1_depth=.015, lfo1_delay=.4,
             lfo1_fade=.6)], 'wind',
      sound={0: [('key', 'cutoff', .6), ('velocity', 'cutoff', .15)]},
      macros=[('Reed', [(0, 'cutoff', .12)]), ('Breath', [(0, 'noise', .04)]),
              ('Vibrato', [(0, 'lfo1_depth', .1)]), ('Space', [(-1, 4, .12)])])

patch('Clean Chime -CL', 'Guitar',
      'A clean electric guitar pluck with a bright pick and a warm body: arpeggios, '
      'chord melodies, indie riffs. The preset Chorus and Delay make it a 90s clean tone. '
      'X: Pick; Y: Decay.',
      [layer(wave1=2, wave2=3, pw=.3, blend=.35, cutoff=1800, res=.15, attack=.001,
             decay=2.6, sustain=0, release=.25, level=.72, mod_attack=.001, mod_decay=.28,
             mod_sustain=0, mod_amount=.3, mod_dest=0, f2=1, f2_type=1, f2_cutoff=140)],
      'guitar', struck=True,
      sound={0: [('velocity', 'cutoff', .25), ('key', 'cutoff', .6)]},
      macros=[('Pick', [(0, 'mod_amount', .12)]), ('Decay', [(0, 'decay', .14)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .12)])])

patch('Banjo Porch -CL', 'Guitar',
      'Bright, twangy banjo: thin steel strings and a drum-head resonance, short and '
      'punchy. Bluegrass rolls, country fills. X: Twang; Y: Decay.',
      [layer(wave1=3, pw=.14, wave2=2, blend=.3, cutoff=3800, res=.3, attack=.001, decay=.8,
             sustain=0, release=.08, level=.66, mod_attack=.001, mod_decay=.09, mod_sustain=0,
             mod_amount=.35, mod_dest=0, f2=1, f2_type=2, f2_cutoff=1100, f2_res=.35,
             f_routing=2, f_balance=.35)], 'guitar', struck=True,
      sound={0: [('velocity', 'cutoff', .2)]},
      macros=[('Twang', [(0, 'res', .12)]), ('Decay', [(0, 'decay', .14)]),
              ('Tone', [(0, 'cutoff', .12)]), ('Space', [(-1, 4, .1)])])

patch('Finger Round -CL', 'Bass',
      'A round finger-style electric bass: warm thump, soft top, natural decay. Walks, '
      'grooves, ballads. Velocity adds the finger attack. X: Tone; Y: Pluck.',
      [layer(wave1=1, wave2=2, blend=.25, sub=.25, cutoff=900, res=.1, filter_env=.25,
             attack=.004, decay=2.6, sustain=0, release=.12, level=.8, voice_mode=1)], 'bass',
      on=(), struck=True, sound={0: [('velocity', 'cutoff', .25)]},
      macros=[('Tone', [(0, 'cutoff', .14)]), ('Pluck', [(0, 'filter_env', .15)]),
              ('Decay', [(0, 'decay', .12)]), ('Sub', [(0, 'sub', .15)])])

patch('Mono Floor -CL', 'Bass',
      'The classic mono synth bass: saw and square over a sub, a filter punch on every note, '
      'legato slides. Funk, disco, synth-pop. X: Cutoff; Y: Punch.',
      [layer(wave1=2, wave2=3, pw=.5, blend=.4, detune=6, sub=.45, cutoff=520, res=.38,
             attack=.003, sustain=.85, release=.1, level=.72, voice_mode=2, glide=.03,
             mod_attack=.001, mod_decay=.28, mod_sustain=.15, mod_amount=.45, mod_dest=0,
             drive=.12)], 'bass', on=(), sound={0: [('velocity', 'cutoff', .15)]},
      macros=[('Cutoff', [(0, 'cutoff', .14)]), ('Punch', [(0, 'mod_amount', .12)]),
              ('Glide', [(0, 'glide', .1)]), ('Drive', [(0, 'drive', .12)])])

patch('Koto Garden -CL', 'Ethnic',
      'Koto: a plucked silk-string tone with a tiny pitch drop at the attack and a '
      'woody decay. Pentatonic melodies, tremolo picking, film scenes. X: Pluck; Y: Decay.',
      [layer(cutoff=8000, attack=.001, decay=2.2, sustain=0, release=.35, level=.72)], 'perc',
      struck=True,
      fm_layers={0: fm(EP_TWIN, .1, [
          op(1.0, .75, .95, rates=(1000, fall_rate(8, .15), fall_rate(60, 2.0), fall_rate(60, .4)), levels=(1, .4, 0, 0)),
          op(3.0, .12, .8, rates=(1000, fall_rate(20, .1), fall_rate(60, .5), fall_rate(60, .2)), levels=(1, .2, 0, 0)),
          op(1.0, index_level(1.1), .9, rates=(1000, fall_rate(12, .08), fall_rate(60, .9), fall_rate(60, .3)),
             levels=(1, .25, 0, 0)),
          op(2.0, index_level(.5), .9, rates=(1000, fall_rate(12, .06), fall_rate(60, .5), fall_rate(60, .2)),
             levels=(1, .25, 0, 0)),
      ], carrier_mix=.3, pitch=(.025, .06, .3))},
      fx=dict(reverb_mix=.24),
      macros=[('Pluck', [(0, 'cutoff', .12)]), ('Decay', [(0, 'decay', .14)]),
              ('Level', [(0, 'level', .1)]), ('Space', [(-1, 4, .12)])])

# =============================================================================
# Musical FX (1), Sound FX (1)
# =============================================================================
patch('Heartbeat Pulse -CL', 'Musical FX',
      'A tempo-synced pulsing pad: sixteenth-note gates breathe through the chord, locked to '
      'the tempo (118 BPM here, or incoming MIDI clock). Hold one chord and let it drive the '
      'song. X: Gate; Y: Tone.',
      [layer(wave1=2, wave2=3, pw=.4, blend=.4, detune=7, unison=2, uni_detune=10, spread=.8,
             cutoff=1800, res=.2, attack=.02, sustain=1, release=.4, level=.62, lfo3_shape=3,
             lfo3_rate=4, lfo3_sync=1, lfo3_div=6, lfo3_depth=1, f2=1, f2_type=1,
             f2_cutoff=150)], 'comp', tempo=118,
      sound={0: [('lfo3', 'amplitude', 1.0), ('lfo3', 'cutoff', .08)]},
      fx=dict(delay_timing=4, delay_feedback=.35, reverb_type=1, reverb_mix=.2),
      macros=[('Gate', [(0, 'lfo3_depth', .2)]), ('Tone', [(0, 'cutoff', .14)]),
              ('Release', [(0, 'release', .12)]), ('Space', [(-1, 4, .12)])])

patch('Riser Nebula -CL', 'Sound FX',
      'An eight-second riser: a noisy supersaw cloud that climbs an octave while its filter '
      'opens, through shimmer, echoes and a huge plate. Hold one note into the drop. '
      'X: Noise; Y: Width.',
      [layer(wave1=2, wave2=2, detune=12, blend=.5, noise=.8, unison=4, uni_detune=25,
             spread=1.0, cutoff=300, attack=2.5, sustain=1, release=1.5, level=.55, f2=1,
             f2_type=1, f2_cutoff=120)], 'fx', sound_fx=True,
      on=('reverb', 'delay', 'shimmer', 'flanger'),
      motion_layers={0: motion_env(8.0, [(0, 0, .3), (1, 1, 0)], {1: (250, 12000), 2: (0, 12)})},
      fx=dict(shimmer_mix=.4, delay_timing=5, delay_feedback=.5, delay_mix=.28, flanger_mix=.35),
      macros=[('Noise', [(0, 'noise', .15)]), ('Width', [(0, 'uni_detune', .15)]),
              ('Release', [(0, 'release', .12)]), ('Space', [(-1, 4, .12)])])
