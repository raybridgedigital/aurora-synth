# Aurora Dual-Patch Live Specification

Status: **design locked — not implemented yet**  
Date: 2026-09-20  
Related: signal path in [README.md](README.md); current release `v0.21.6`

When ready to build, treat this document as the product contract. Do not invent a one-bus merge of two patches.

---

## Goal

Stack **two full Aurora patches** for live performance without FX parameters fighting (Mix, time, shimmer, etc.).

---

## Why not one bus

A single shared FX chain cannot host two authored patches: the second patch’s FX overwrite or fight the first. Layer sends only scale feed into that shared chain; they do not give each patch its own Mix/time/decay/shimmer settings.

**Decision:** dual full buses, or do not offer dual-patch.

---

## Play UI

- **Slot A** and **Slot B** on the Play tab, above the layer strip.
- Selecting a slot shows that slot’s **layers** (Edit focus follows selected slot).
- Per slot:
  - **Level**
  - **Pan**
  - **Bus bypass** — must **skip DSP** for that bus (not merely mute), so CPU drops when the slot is unused.
- Per bus: **Shimmer bypass** (skips shimmer DSP on that bus only).
- **Global Shimmer off** — one control that bypasses shimmer on **both** buses without rewriting stored patch settings.

---

## Engine / signal path

Each slot has a **full FX bus**:

`chorus → phaser → delay return → reverb return → shimmer`  
(+ per-layer delay / reverb / shimmer sends into that bus)

Both buses sum into shared:

`EQ → Master → Output boost / limiter`

Voice generation stays per layer inside each slot; the **voice pool is shared** across both slots.

---

## Tempo

- When loading a patch into a slot: **Slot A applies patch tempo; Slot B never applies patch tempo** (B follows A’s clock). Day-one requirement.
- **Set pads** store the full performance snapshot **including tempo** (see Pads).

---

## Macros / XY

- **Macros and XY apply to Slot A only.**
- Slot B loads as authored and is **set-and-leave** (no live macro morph on B).
- Rationale: macros exist to simplify performance; one morph surface avoids a second parameter fight.

---

## Panic and switching

| Action | Behavior |
|--------|----------|
| **Top Panic** | Full kill — **both** buses (voices + FX rings), same emergency meaning as today |
| **Set pad change** | **Full Panic**, then recall pad snapshot (whole performance swap) |
| **Patch switch on one slot** | **Half-cut (day one)** — Panic-fade / clear **only that bus**; the other slot keeps playing |

Half-cut reuses the existing mute-bus Panic approach, scoped per bus. It is **required on day one** for single-slot patch changes. It is **not** used for pad changes.

---

## Pads (Set rack)

A pad is a **performance snapshot**, not a single patch reference only:

- Slot A patch (reference or state)
- Slot B patch (reference or state)
- Tempo
- Per-slot level / pan
- Bypass states as needed (bus bypass, shimmer bypass; global shimmer off may be session-level)

Pad recall = full Panic → apply snapshot.

---

## Polyphony

- User **option** in settings: **64 (default)** up through **128**.
- Session preference for live load; not required to store on pads for day one.
- Operator can use 128 for lighter sets and drop to 64 when A+B + shimmer is heavy.
- Unison remains the primary way to manage density when stacking (known polyphony constraint).

---

## Shared on purpose

- Shared voice pool  
- Shared Master / Output boost / session EQ  
- Hold, Record, MIDI Learn  
- Top Panic (both buses)

**Hold:** latches notes (and arp chord) after key-up; cleared by Panic / Hold off / cut paths as today.

---

## Performance notes (MacBook Air M3, 8 GB)

- Dual bus is acceptable if idle bus/shimmer DSP is truly bypassed.
- Shimmer is the main FX CPU risk; global + per-bus shimmer bypass are the safety valves.
- Delay / chorus / phaser / reverb ×2 is secondary to shimmer and voice count.
- Do not ship 128 as the default without a stress test under dual hot shimmer + unison.

---

## Out of scope / non-goals

- One-bus “blend two patches” with shared FX  
- Macros on Slot B for day one  
- Slot B applying its own tempo on load  
- Half-cut on Set pad changes  

---

## Build checklist (when starting)

1. Duplicate post-mix FX state per bus; wire A/B sum into shared EQ/Master.  
2. Play UI: slots, level/pan, bus bypass, per-bus shimmer bypass, global shimmer off.  
3. Load rules: A tempo yes, B tempo no; macros/XY → A only.  
4. Panic: full (top + pads); half-cut on single-slot patch load.  
5. Pad schema: A+B+tempo+mix(+bypass).  
6. Polyphony setting 64…128 (default 64).  
7. Stress-test on target Air before calling it done.

---

## Revision

| Date | Note |
|------|------|
| 2026-09-20 | Initial lock from product discussion (dual bus, A-only macros, B skips tempo, half-cut day one, polyphony option, global shimmer off). |
