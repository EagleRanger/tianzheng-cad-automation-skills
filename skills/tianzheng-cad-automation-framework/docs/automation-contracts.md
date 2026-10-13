# Controller/Adapter Contracts

The controller and CAD adapter communicate through local structured messages. The controller prepares, validates, and reports; the adapter runs approved native operations in the CAD environment and returns machine-readable results.

## Message principles

1. Use explicit request IDs.
2. Bind every request to a specific drawing and task.
3. Submit operations, not arbitrary command strings.
4. Include dry-run/preview mode.
5. Require per-object acceptance fields.
6. Report unknown prompts and partial failures instead of hiding them.
7. Never send credentials, customer names, or production paths in examples.

## Request shape

```json
{
  "request_id": "uuid",
  "document": "isolated-copy.dwg",
  "source_sha256": "hex",
  "operation": "annotate_arc_angle",
  "dry_run": false,
  "source": {
    "discovery_rule": "selected_polyline_segment",
    "segment_index": 1
  },
  "placement": {
    "side": "right",
    "offset_units": 1.0
  },
  "style": {
    "layer": "annotation",
    "style_name": "generic-dimension"
  },
  "acceptance": {
    "native_type": "tianzheng-native-dimension",
    "source_mapping_required": true,
    "save_close_reopen_required": true
  },
  "rollback": {
    "on_failure": "delete_current_attempt"
  }
}
```

Generic names above are placeholders. A real implementation should replace them with the exact local object class names, style registry, and units defined by its version contract.

## Response shape

```json
{
  "request_id": "uuid",
  "status": "accepted|failed|blocked|rolled_back",
  "started_at": "local-time",
  "finished_at": "local-time",
  "document_state": {
    "active_document": "isolated-copy.dwg",
    "command_idle": true
  },
  "results": [
    {
      "source_ref": "polyline:segment-1",
      "created_object": {
        "handle": "generic-handle",
        "native_type": "tianzheng-native-dimension",
        "layer": "annotation"
      },
      "checks": {
        "type_match": true,
        "source_mapping_match": true,
        "placement_within_contract": true
      }
    }
  ],
  "failure": null,
  "rollback": null,
  "next_safe_action": "save_close_reopen_acceptance"
}
```

## Batch operation rules

A batch is not one opaque command. The recommended behavior is:

1. validate all inputs before mutation;
2. execute bounded transactions;
3. validate each result independently;
4. on failure, roll back the failed batch according to its contract;
5. retain the exact completed and failed subsets;
6. permit targeted retry only when the root cause and changed variable are known.

## Layout request

Layout requests should preserve semantics:

```json
{
  "request_id": "uuid",
  "document": "isolated-copy.dwg",
  "operation": "relayout_native_annotations",
  "scope": {
    "group_id": "generic-group",
    "candidate_handles": ["generic-handle-1", "generic-handle-2"]
  },
  "policy": {
    "preserve_values": true,
    "preserve_source_association": true,
    "preserve_native_type": true,
    "allow_text_mirror": false,
    "clearance_policy": "native-text-height-plus-measured-bbox"
  },
  "acceptance": {
    "internal_collision_target": 0,
    "source_endpoint_immutability": true,
    "save_close_reopen_required": true
  }
}
```

## Sheet composition request

Sheet planning can be represented as a data pipeline before CAD writes:

```json
{
  "request_id": "uuid",
  "operation": "plan_sheet_layout",
  "input": {
    "drawing": "isolated-copy.dwg",
    "content_model": "semantic-content-map",
    "frame_template": "generic-frame",
    "scale": 1
  },
  "output": {
    "sheets": [
      {
        "sheet_id": "sheet-01",
        "region": "planned-region",
        "viewport_scale": 1,
        "title": "generic-title",
        "continuation_refs": []
      }
    ]
  },
  "review": {
    "require_overlap_check": true,
    "require_coverage_check": true,
    "require_crop_check": true,
    "require_directory_consistency": true
  }
}
```

The plan must be reviewed before producing actual sheets. A plan response is a candidate, not a completed drawing set.
