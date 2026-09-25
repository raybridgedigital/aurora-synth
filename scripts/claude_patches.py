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
def op(ratio=1.0, level=.5, vel=.7, rates=(200, 3, .5, 8), levels=(1, .6, 0, 0),
       fine=0.0, wave=0, ks=0, fixed=None):
    """One FM operator. Level: carriers = amplitude; modulators = index (1.0 = 10 cycles,
    about 63 radians, so EP-style indices of 1-2 rad are levels near 0.02-0.03). Rate/level
    envelope: segment time = 1/rate seconds (rates 0.02-200), linear ramps; L3 is held."""
    assert all(.02 <= r <= 200 for r in rates), rates
    return dict(wave=wave, ratio=ratio, fixedHz=fixed or 440.0, fixedMode=1 if fixed else 0,
                fine=fine, level=level, vel=vel, keyScale=ks, keySync=1, envMode=0,
                pulseWidth=.5, wtTable=0, wtPos=.5, wtWarp=0.0,
                env=dict(rates=list(rates), levels=list(levels)))


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
        master = levels.get(pid, .5)
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
              body_time=2.8, tine_time=.4, carrier_vel=.85, mod_vel=.9, attack=200):
    carrier = dict(rates=(attack, 3.0, .16, 4.0), levels=(1, .6, 0, 0))
    return [
        op(1.0, .72, carrier_vel, ks=1, **carrier),
        op(1.0, .6, carrier_vel, fine=detune, ks=1, **carrier),
        op(body_ratio, index_level(body), mod_vel, ks=1,
           rates=(200, 2.5, 1 / body_time, 6.0), levels=(1, .5, 0, 0)),
        op(tine_ratio, index_level(tine), mod_vel, ks=1,
           rates=(200, 12.0, 1 / tine_time, 10.0), levels=(1, .25, 0, 0)),
    ]


EP_LAYER = dict(cutoff=12000, attack=.001, decay=8.0, sustain=0, release=.45, level=.7)
EP_MACROS = [('Brightness', [(0, 'cutoff', .16)]), ('Decay', [(0, 'decay', .12), (0, 'release', .12)]),
             ('Grit', [(0, 'char_drive', .2)]), ('Space', [(-1, 4, .12)])]

patch('Eighty-Three Tines -CL', 'FM EP',
      'The 1983 FM electric piano: glassy tine on top, round body underneath, a slow shimmer '
      'between two detuned pairs. Soft touch stays mellow, hard touch barks. Play ballad '
      'chords with the pedal. X: Brightness; Y: Decay.',
      [layer(**EP_LAYER, char=1, char_drive=.08, char_mix=.25, char_tone=.7)], 'keys',
      fm_layers={0: fm(EP_TWIN, .35, dx_ep_ops(), carrier_mix=.45)},
      macros=EP_MACROS, struck=True)

patch('Ballad Glass -CL', 'FM EP',
      'A rounder, softer FM piano for quiet verses: gentle tine, warm body, a wider chorus '
      'between the pairs and a long singing decay. Play it sparse and let notes ring. '
      'X: Brightness; Y: Decay.',
      [layer(**dict(EP_LAYER, cutoff=7000, release=.6))], 'keys',
      fm_layers={0: fm(EP_TWIN, .15, dx_ep_ops(body=1.05, tine=.55, detune=.05,
                                                body_time=3.5, attack=120), carrier_mix=.5)},
      fx=dict(reverb_mix=.24, reverb_decay=2.6, reverb_predelay=24),
      macros=EP_MACROS, struck=True)

patch('Tine Bark -CL', 'FM EP',
      'Funk and soul FM piano with teeth: touch decides everything, from a clean ping to a '
      'growling bark with a little grit. Comp sixteenths and dig in on the accents. '
      'X: Brightness; Y: Decay.',
      [layer(**dict(EP_LAYER, cutoff=14000, decay=5.0, release=.25), char=1, char_drive=.18,
             char_mix=.4, char_tone=.75)], 'keys',
      fm_layers={0: fm(EP_TWIN, .55, dx_ep_ops(body=2.2, tine=1.3, body_time=1.8,
                                                mod_vel=1.0, carrier_vel=.9), carrier_mix=.4)},
      sound={0: [('velocity', 'char_drive', .25)]},
      fx=dict(reverb_mix=.14, reverb_type=0, reverb_decay=1.4, reverb_predelay=8),
      macros=EP_MACROS, struck=True)

patch('Bell Tine Nineties -CL', 'FM EP',
      'The glossy 90s R&B ballad piano: a clear bell partial over a soft round body, '
      'shimmering and wide. Lush slow chords, pedal down. X: Brightness; Y: Decay.',
      [layer(**dict(EP_LAYER, cutoff=10000, release=.55))], 'keys',
      fm_layers={0: fm(EP_TWIN, .1, dx_ep_ops(body=.9, tine=.9, tine_ratio=3.0, detune=.045,
                                                body_time=3.2, tine_time=1.4, attack=160),
                       carrier_mix=.5)},
      fx=dict(reverb_mix=.26, reverb_decay=2.8, reverb_predelay=22),
      macros=EP_MACROS, struck=True)
