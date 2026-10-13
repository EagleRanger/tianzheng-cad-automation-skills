# Capability and Validation Boundary

This summary describes the framework's capability classes. It does not claim that every capability is production-ready for arbitrary drawings.

## Verified foundations

| Capability | Meaning | Boundary |
|---|---|---|
| Isolated drawing intake | Identify, copy, and protect a source drawing before work | Requires reliable hashing and protected output locations |
| Owned Tianzheng session lifecycle | Open an isolated DWG in a controlled Tianzheng/AutoCAD session, handle known dialogs, verify readiness, save/close/reopen | Exact dialog rules and ownership checks are mandatory |
| Native object audit | Identify Tianzheng-native and standard AutoCAD object classes after reopening | Full proprietary-property extraction may vary by version |
| Version/proxy diagnosis | Detect compatibility issues where older versions show native objects as proxy/zombie entities | Missing external references are reported, not silently repaired |
| Layer/display restoration | Temporarily isolate relevant objects and restore original layer/display state | Required whenever visual isolation is used |

## Native annotation generation

| Capability | Meaning | Boundary |
|---|---|---|
| Native arc-angle generation | Create one editable Tianzheng-native angular dimension per selected arc | Each arc uses a fresh native command transaction; no universal generality claim |
| Multi-arc batch generation | Repeat the verified per-arc transaction across governed source polylines | Scope must match the accepted source set and acceptance contract |
| Typed line/arc dispatch | Classify polyline segments and dispatch arcs and straight segments to appropriate native commands | Zero-length, ambiguous, and wrong-type segments are rejected before mutation |
| Targeted replacement/repair | Replace or repair a bounded, explicitly mapped subset of existing annotations | Validation-only until exact source mapping, object audit, and reopen checks pass |

## Annotation layout and audit

| Capability | Meaning | Boundary |
|---|---|---|
| Native control-point layout | Move approved native annotation control points without changing values or source associations | Not a generic solution until cross-drawing gates pass |
| Band and side normalization | Align related annotations into readable bands or consistent sides | Short arcs, sharp corners, and collision clusters need separate rules |
| Text-box-aware spacing | Use native text extents rather than screenshot estimates for collision spacing | Depends on reliable extraction of native text metrics |
| Collision audit | Check label/label and label/source geometric conflicts against a defined clearance policy | A local pass does not prove full-sheet or cross-drawing success |
| Save-close-reopen acceptance | Verify object types, handles, source relationships, and visual readability after reopening | Required for promotion from experiment to stable workflow |

## Drawing-set production

| Capability | Meaning | Boundary |
|---|---|---|
| Semantic object extraction | Convert relevant content into a reusable operation plan | Ambiguous content must remain protected or require review |
| Template/layout candidate preparation | Prepare frame, viewport, scale, subdivision, title, and directory plans | Candidate previews are not production acceptance |
| Sheet composition pipeline | Compose verified blocks into a full drawing-set workflow | Must be built only from independently accepted components |
| Standard drawing library | Organize reusable symbols and detail groups for later assembly | Deferred until core layout automation is stable |

## Rejected routes

The framework explicitly rejects the following as default production routes:

- one command session consuming every arc point when it creates only the first object;
- fixed three-click or fixed-screen-coordinate mouse replay;
- blind global mouse control of a user-visible CAD window;
- accepting object count alone as proof of native annotation success;
- using a generic move that breaks native annotation semantics;
- editing values or exploding native objects to make a layout look easier;
- retrying the same failed operation without changing a reviewed variable or root cause.

## Promotion policy

Capabilities are classified as:

```text
verified stable kernel
sample real-drawing pass
validation only
planned
rejected or blocked
```

Only a verified stable kernel may become a default production route. A new implementation receives a new identity and must pass its own object, visual, and save-close-reopen gates before replacing the current stable route. Evidence from one sample drawing does not automatically promote a capability to universal use.
