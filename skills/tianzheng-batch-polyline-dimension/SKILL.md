---
name: tianzheng-batch-polyline-dimension
description: Automate native Tianzheng/AutoCAD dimensions for selected or runtime-discovered polylines, including ARC included-angle and LINE dimensions, ordinary exterior-band layout, exceptional collapsed-angle rescue, text-anchor restoration, machine audits, timing, and readable screenshots. Use when developing, testing, packaging, or running the project's batch polyline dimension command; do not use for unrelated CAD review or unvalidated production claims.
---

# Tianzheng Batch Polyline Dimension

Use this Skill as the stable project entry for the `自动批量多段线尺寸` capability. Reuse the project's registered scripts and contracts. Do not recreate the business algorithm inside the Skill.

## Start from authority

1. Resolve the project root from `TIANZHENG_CAD_AUTOMATION_HOME` or an explicit compatible checkout path; this packaged Skill does not contain a private project checkout.
2. Read the root and project `AGENTS.md`, then the minimal hot layer declared by `config/project_execution_index.json`.
3. Run `scripts/inspect_capability.ps1` from this Skill to read back the current package and special-text validation status.
4. Treat `config/current_execution_handoff.json` and `config/current_execution_return.json` as authoritative for the latest run. Never infer live state from an old conversation preview.
5. Read `references/project-contract.md` before changing formulas, publishing a READY handoff, or claiming acceptance.

## Reuse the two-layer implementation

- Business layer: runtime geometry discovery, native ARC/LINE dimension generation, source mapping, first-pass exterior layout, and the narrow exceptional rescue pass.
- Observer layer: identity, ACK/COMPLETE, timings, semantic and endpoint audits, native-grip inventory, readable screenshot, and return delivery.

Keep the business path short. Do not insert heavyweight probes into already-fast stages. Enable targeted diagnostics only at a failed boundary or for a known difficult candidate.

## Preserve dimension semantics

- ARC objects must remain native included-angle dimensions expressed in degrees. Arc length is a semantic failure even if the picture looks plausible.
- LINE objects must remain native linear dimensions and must not receive a degree marker.
- Require runtime source mapping and endpoint association. A visible object without a valid mapping is not a successful dimension.
- Ordinary objects use the shared exterior-band formula first. Do not move every object merely because one exceptional corner needs rescue.

## Handle the exceptional collapsed-angle case

Apply the rescue chain only when runtime measurements identify the anomaly. Never match a fixed handle, coordinate, segment number, bounding box, or object count.

1. Establish or replace an endpoint-valid native angle candidate.
2. Accept the curve side and posture before moving text.
3. Apply the runtime outer-band formula.
4. If the text anchor still lies on or crowds the dimension curve, move grip 4 only.
5. Derive the grip-4 WCS delta from a same-source, shared-endpoint, rank-2 degree peer normalized by measured text height `H`.
6. Pass planner `DX/DY` through unchanged. The controller must not recalculate the vector.
7. Re-inventory the complete native set and produce a readable screenshot.

## Execute through the governed lane

The project/strategy task may inspect, design, patch, test statically, and publish. It must not directly drive Tianzheng.

For a real CAD mutation:

1. Verify no active CAD lease conflict.
2. Build one immutable schema-v3 READY handoff with the current V8 publisher named by `config/project_execution_index.json`.
3. Dispatch it to the exact registered execution task.
4. Permit only the actions named by the handoff. Default test policy is `save=false` and `retry=0`.
5. End the project turn after dispatch. Review the immutable return in a later turn.

## Judge completion precisely

- A static test, DLL load, ACK, screenshot, or partial survivor set alone is not full success.
- Report generation coverage, semantic correctness, endpoint association, layout targets, protected-grip drift, source drift, screenshot result, business time, observer time, failures, and next legal gate.
- The special text peer-normal component has a current-board 3-of-3 stability record. This does not establish three complete blank-to-final runs and does not establish cross-structure DWG generality.
- Keep the whole command package at its registry maturity until its own promotion gates pass.

## Keep the package clean

- Do not copy run directories, screenshots, historical preparers, or superseded controllers into this Skill.
- Do not revive routes listed as forbidden or rejected by the project.
- Fix repeatable workflow faults in the shared layer and add a regression; do not accumulate one-run workarounds.
- Preserve test drafts unsaved unless the user explicitly requests a saved deliverable.
