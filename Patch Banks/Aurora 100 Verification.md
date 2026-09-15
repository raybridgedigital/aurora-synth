# Aurora 100 — verification

Version 0.2 · 14 September 2026

100 patches; 10 categories with 10 patches each; 112 total factory sounds including the starter collection.

All 100 passed the native offline audit at 48 kHz stereo:

- Full preset schema, allowed parameter values, and unique names/IDs/settings.
- Four-second held notes or chords at velocity 100, then eight seconds of release.
- Eight-note chords at velocity 127 for eight seconds, including slow attack sounds.
- Finite samples, non-silent output, release completion, and immediate silence after Panic.
- No identical audio hashes among the 100 held renders.

Highest phrase peak: 0.053967. Highest stress peak: 0.167076. Both use the bank reference Master of 25%.

Native interface checks covered bundled bank loading, all ten category menu entries, a ten-patch filtered group, name search, an empty search, split-patch loading, preservation of Master volume, and the existing personal sound collection. Session sound values, favorites, routing, mappings, output choice, and buffer matched the pre-check snapshot after Undo.

These are automated signal and interface checks. Sound quality and playing feel still benefit from listening on the user’s keyboards and output system. Organ, brass, string, and key patches are synthesized interpretations, not sampled acoustic instruments.

Reproduce with `bash scripts/audit_patch_bank.sh`. The detailed per-patch report is in `build/patch-audit-report.json`.
