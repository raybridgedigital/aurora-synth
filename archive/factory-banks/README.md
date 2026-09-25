# Archived factory banks

These banks shipped with KiMiA (Aurora) up to **v0.25.0** (`b29e883`, 24 September 2026)
and were retired on 25 September 2026 in favour of the 55-patch `Resources/AuroraFX.json`
bank (one or two layers per patch, Dual Patch-ready). They are kept for history only: the
app and plug-ins no longer bundle, list or load them.

| File (`v0.25.0/`) | Patches | Notes |
| --- | ---: | --- |
| `AuroraSpectrum300.json` | 300 | Spectrum rebuild, 30 per category, IDs `spectrum-` |
| `Aurora100.json` | 125 | Spectrum mirror (100) + FM sounds (25, IDs `fm-`) |
| `AuroraPrism100.json` | 100 | Prism performances (Spectrum mirror) |
| `AuroraNova100.json` | 100 | Nova performances (Spectrum mirror) |
| `AuroraShimmer29.json` | 29 | Shimmer category, IDs `shimmer-` |
| `AuroraGB109.json` | 109 | 60 FX sounds (`fx-`) + 49 Y2K sounds (`y2k-`); the 60 FX sounds were the last to ship |
| `AuroraReference.json` | 2 | Reference fixtures used by old tests |
| `SpectrumLevelTrims.json` | — | Per-patch level trims used by the Spectrum audit |

Total: 765 patches. `catalogs/` holds the release catalogs, verification notes and grouped
preset ZIPs that used to live in `Patch Banks/`.

**Why they were retired:** most are 3–4 layer patches with heavy unison. At the 24 September
2026 gig (v0.25.0, M3 MacBook Air, 44.1 kHz/128 frames) the pedalled set-list sounds needed
up to 82–91% of the audio budget and crackled; the new bank's 1–2 layer patches sound as good
at a fraction of the cost.

**Auditioning one:** in KiMiA choose **Import** in the library and select any JSON file here.
The patches arrive in **Your sounds** as user presets (the engine still supports four layers).

Related archived tools: `archive/scripts/` (Nova generators, patch recipes, the Spectrum audit
runner) and `archive/tests/` (Spectrum and reference-level audits).
