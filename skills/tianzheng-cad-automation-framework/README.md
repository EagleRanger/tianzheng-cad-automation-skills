# Tianzheng CAD Automation Framework

This repository documents a local automation framework for producing and editing full sets of Tianzheng CAD drawings with an AI orchestration layer. It describes the architecture, workflow, verified capabilities, safety gates, and reusable request contracts. It intentionally excludes production drawings, customer data, local paths, machine identifiers, execution logs, and real project names.

## What it is

The framework treats Tianzheng/AutoCAD as a governed desktop application rather than as a black box for blind GUI replay. A controller prepares data and reports, while native commands run inside a compatible Tianzheng session and produce editable Tianzheng-native objects.

The current focus is:

1. safe session lifecycle for isolated drawings;
2. semantic object discovery and audit;
3. native annotation generation and relayout;
4. objective acceptance by object audit, visual review, and save-close-reopen checks;
5. gradual extension from annotation modules to complete drawing-set layout.

## Core principle

A command returning success is not delivery. An automated result is accepted only when the source is protected, the intended objects are correct, native object types survive reopening, and the target drawing view reads correctly.

## Repository map

```text
README.md                         Introduction and scope
docs/framework.md                 Full drawing-set automation architecture
docs/capabilities.md              Current capabilities and validation boundary
docs/acceptance.md                Safety, acceptance, and evidence model
docs/automation-contracts.md      Controller/adapter request and response model
examples/request-arc-angle.json   Generic structured request example
```

## Intended use

This is a method and architecture reference. It is not a plug-and-play installer. Implementations must be adapted to the local Tianzheng version, AutoCAD release, drawing conventions, company review process, and security policy.

## Non-goals

- Do not modify Tianzheng's closed-source binaries.
- Do not fabricate native objects or convert a failed native operation into a text-only approximation while claiming native completion.
- Do not replay raw mouse coordinates as the primary production route.
- Do not write directly to a user's source drawing.
- Do not treat partial sample validation as a universal capability.
