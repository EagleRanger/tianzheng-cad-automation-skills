# Full Drawing-Set Automation Framework

## Design goal

The system aims to turn a complete engineering drawing into a reproducible, reviewable drawing-set production pipeline. The key idea is to separate work into independently verified modules before composing them into larger drawing workflows.

The intended order is:

```text
Drawing intake and source protection
  -> compatibility and session readiness
  -> semantic object inventory
  -> operation plan and preview
  -> native command execution
  -> object/visual/reopen acceptance
  -> annotation layout and collision handling
  -> frame, scale, subdivision, title, and directory composition
  -> controlled output and audit receipt
```

## 1. Intake and source protection

Every task begins outside the CAD application:

1. Record the source drawing identity with file metadata and a cryptographic hash.
2. Copy the source to an isolated working file.
3. Define the exact allowed objects, layers, regions, and output paths.
4. Keep immutable source drawings, current work copies, test masters, historical checkpoints, and formal outputs in separate protected areas.
5. Preserve the original source as read-only evidence.

The controller should reject ambiguous source identity, missing dependencies, unknown object scopes, and any request that would overwrite a protected original.

## 2. Environment readiness

Tianzheng and AutoCAD compatibility must be checked before semantic work. Different Tianzheng versions may represent the same older drawing differently, especially through proxy or zombie objects.

A ready session is not just a visible window. The framework requires evidence that:

- the session belongs to the current task;
- the intended isolated drawing is the active document;
- startup dialogs are resolved by exact allowlisted signatures only;
- the command state is idle;
- model and paper layouts have been regenerated and inspected;
- unresolved external references are reported rather than silently re-bound.

Known startup, platform-selection, proxy-warning, external-reference, save, and close dialogs should be handled by deterministic finite-state rules. Unknown dialogs stop the task instead of entering a generic trial-and-error loop.

## 3. Semantic inventory

Before mutation, the adapter audits relevant drawing data:

- layers, layer states, visibility, freeze/lock state;
- model space and layout structure;
- viewports, scales, frame geometry, and usable plot regions;
- polylines, arcs, lines, blocks, text, leaders, and tables;
- Tianzheng-native objects and native object classes;
- handles, source associations, extents, and selected drawing metadata;
- external references and missing dependencies.

This inventory creates a semantic map rather than a flat list of entities. For example, a plant, road, dimension, coordinate mark, room label, or table row should be understood through its native object type, nearby labels, legend mapping, geometry relationship, and layout position.

## 4. Plan and preview

Every mutation becomes an explicit operation plan. A useful plan contains:

- operation type;
- exact source objects or discovery rule;
- expected result type and count;
- target style, layer, placement rule, and acceptance range;
- protected objects that must not change;
- rollback strategy;
- dry-run/preview output.

The preview is a human-review gate for ambiguous or destructive operations. It should show what will be created, changed, moved, or deleted and why. Discovery rules are allowed to propose candidates, but they must not silently turn uncertain semantics into irreversible edits.

## 5. Native command execution

The preferred architecture is a process-adjacent or in-process adapter that wraps approved Tianzheng commands. The controller submits structured data, not arbitrary command text.

The adapter executes:

1. source object locking or exact identification;
2. temporary visual isolation when overlapping geometry could cause ambiguity;
3. approved native command invocation;
4. per-object validation of type, source mapping, style, handle, and placement;
5. local transaction rollback on failure;
6. restoration of layer and display state;
7. append-only progress and audit records.

This preserves human-editable Tianzheng-native objects, such as native dimensions, coordinate marks, and other domain annotations. Users can continue editing them with normal Tianzheng tools.

## 6. Annotation relayout

Annotation work is separated from generation. A correct native object is first accepted as L1; layout quality is then handled in later levels:

```text
L1 complete and semantically correct
L2 internally clear: labels in a group do not collide
L3 globally clear: labels, source geometry, base map, frames, and existing content coexist readably
```

The layout optimizer should not change annotation values, source associations, object types, or semantic meaning. It should adjust only approved control points, bands, side selection, spacing, leader shapes, or other native parameters.

A practical rule is to normalize spacing using native text height and then refine it with measured text bounding boxes projected along the local placement direction. Ordinary continuous bands, short arcs, sharp corners, and collision clusters should be modeled separately so that one failure mode does not distort the general rule.

## 7. Drawing-set composition

After annotation modules stabilize, the full drawing-set pipeline composes:

- frame and title-block placement;
- drawing scale and viewport mapping;
- automatic subdivision of a large plan into sheet-sized regions;
- overlap, coverage, crop, and continuation checks;
- drawing names, numbers, sheet references, and directory relationships;
- consistent sheet layout and final plot/readability checks.

This stage should use source content, viewport definitions, and existing frame/title semantics as data. Original title blocks, signatures, directory references, and continuation relationships are preserved or explicitly carried into a new plan; they should not be discarded merely because a layout is regenerated.

## 8. Receipt and recovery

Every run should leave enough information to resume without replaying CAD operations:

- source and output identities;
- workflow/version and adapter identity;
- requested scope;
- object plan;
- created, changed, deleted, or rejected items;
- failed subset and reason;
- acceptance results;
- checkpoint/output location;
- next safe action.

Recovered work should reconcile completed effects before retrying. A process exiting, a command ending, or a file being produced is not equivalent to business acceptance.
