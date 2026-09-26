#!/usr/bin/env python3
"""Loudness calibration for Claude patches.

Reads a bench/patchcheck JSON (measured with the current claude_levels.json applied) and
writes scripts/claude_levels.json so every " -CL" patch lands at TARGET dBFS early level:
Master first (up to MASTER_MAX; Master feeds a tanh soft clip, so it stays moderate), then a
common gain on the patch's layer levels for the rest. Run, rebuild the bank, re-measure;
two passes converge within a fraction of a dB.

Usage: python3 scripts/calibrate_claude_levels.py ~/Desktop/KiMiA\\ by\\ Claude/bench/results/x.json
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import claude_patches  # noqa: E402

TARGET = -33.0     # the median early level of the 55 original patches
MASTER_MAX = 1.0
# Levelled by hand: a riser is meant to swell far past its first seconds.
MANUAL = {'Riser Nebula -CL'}
LEVELS = claude_patches.LEVELS


def main(measured_path):
    """Works from the patches as built (Resources/AuroraFX.json): their effective Master and
    layer levels, where Level is already capped at 1.0. Required gain goes to Master first
    (up to MASTER_MAX), the rest to the layer levels (as a scale of the designed levels)."""
    measured = {r['name']: r for r in json.loads(Path(measured_path).read_text())}
    built = {p['name']: p for p in json.loads(
        (claude_patches.ROOT / 'Resources/AuroraFX.json').read_text())}
    current = json.loads(LEVELS.read_text()) if LEVELS.exists() else {}
    lv = str(claude_patches.P['level'])
    out = {}
    for e in claude_patches.PATCHES:
        name = e['name']
        pid = ('mxep-' if e['category'] == 'FM EP' else 'mx-') + claude_patches.slug(
            claude_patches.base_name(name))
        cur = current.get(pid, {})
        if isinstance(cur, (int, float)):
            cur = {'master': cur}
        out[pid] = {'master': cur.get('master', .5), 'level_scale': cur.get('level_scale', 1.0)}
        if name not in measured or name in MANUAL or name not in built:
            continue
        p = built[name]
        designed = max(v[claude_patches.P['level']] for v in e['layers'])
        effective = max(l['values'][lv] for l in p['layers'][:len(e['layers'])])
        master = p['globals'][0]
        gain = 10 ** ((TARGET - measured[name]['early']) / 20)
        new_master = min(MASTER_MAX, master * gain)
        rest = master * gain / new_master
        new_level = min(1.0, effective * rest)
        out[pid] = {'master': round(new_master, 4), 'level_scale': round(new_level / designed, 4)}
        short = 20 * math.log10(effective * rest / new_level) if new_level < effective * rest else 0
        print(f"{name:28s} early {measured[name]['early']:6.1f} -> master {new_master:.3f} "
              f"level {new_level:.2f}" + (f"  (level capped: {short:.1f} dB short)" if short > .05 else ''))
    LEVELS.write_text(json.dumps(out, indent=1, sort_keys=True) + '\n')
    print(f'wrote {LEVELS}')


if __name__ == '__main__':
    main(sys.argv[1])
