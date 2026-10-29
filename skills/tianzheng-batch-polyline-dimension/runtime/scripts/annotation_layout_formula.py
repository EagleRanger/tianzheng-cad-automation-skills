"""Versioned, text-height-normalised formula for native annotation layout."""

from __future__ import annotations

import json
from dataclasses import dataclass
from math import hypot
from pathlib import Path

from annotation_vector_geometry import ConvexPolygon, VectorPoint, signed_near_edge_clearance


@dataclass(frozen=True)
class CandidateGeometryFormula:
    pick_fractions: tuple[float, ...]
    radius_pick_fractions: tuple[float, ...]
    text_states: tuple[str, ...]
    text_to_dimension_target_h: float
    text_to_source_hard_h: float
    text_to_source_preferred_h: float
    source_visible_edge_to_text_preferred_h: float
    text_text_hard_gap_h: float
    text_text_preferred_gap_h: float
    sequence_seam_target_h: float
    sequence_seam_hard_h: float
    dimension_dimension_hard_gap_h: float
    dimension_dimension_preferred_gap_h: float
    dimension_shared_endpoint_exclusion_h: float
    arrow_size_h: float
    dimension_arc_max_step_degrees: float
    clearance_footprint_samples: int
    radius_slide_sample_spacing_h: float
    radius_slide_endpoint_clearance_h: float
    radius_slide_max_samples: int
    radius_leader_text_gap_h: float
    radius_marker_to_text_offsets_h: tuple[float, ...]
    text_width_per_visible_character_h: float
    angle_text_min_width_h: float
    radius_text_min_width_h: float
    thin_stroke_kinds: tuple[str, ...]


@dataclass(frozen=True)
class ShortArcFormula:
    capacity_primary_threshold: float
    capacity_support_threshold: float
    classification_text_width_per_visible_character_h: float
    classification_angle_text_min_width_h: float
    closed_path_preferred_side: str
    closed_path_allow_interior_fallback: bool
    candidate_tangential_capacity_min: float
    inner_radius_floor_h: float
    pick_fractions: tuple[float, ...]
    inner_band_factors_h: tuple[float, ...]
    inner_text_band_factors_h: tuple[float, ...]
    text_text_hard_gap_h: float
    text_text_preferred_gap_h: float
    dimension_dimension_hard_gap_h: float
    dimension_dimension_preferred_gap_h: float


@dataclass(frozen=True)
class SoftWeightsFormula:
    profile_deviation: float
    wide_space: float
    side_switch: float
    band_step: float
    offset_delta: float
    along_shift: float
    non_dominant_side: float
    source_clearance_preference: float
    text_line_target: float
    radius_inside_angle: float
    radius_angle_gap: float
    dimension_spacing: float
    text_thin_stroke_overlap: float


@dataclass(frozen=True)
class DirectionalClearanceFormula:
    """Native grip-0 band rules learned from the accepted blue-line sample."""

    base_band_h: float
    closed_exterior_band_h: float
    below_source_band_h: float
    minimum_increment_h: float
    exterior_polygon_arc_step_degrees: float


@dataclass(frozen=True)
class QuantifiedCommonBandFormula:
    """Measured source/text geometry collapsed to one band per source path."""

    source_visible_edge_gap_h: float
    text_dimension_gap_h: float
    minimum_band_h: float
    aggregation: str
    snap_policy: str
    text_thickness_input: str
    source_width_input: str
    observed_obb_role: str
    observed_obb_failure_action: str


@dataclass(frozen=True)
class FourDirectionTextAlignmentFormula:
    """Observed native text-state alignment across four screen orientations."""

    orientation_classes: tuple[str, ...]
    orientation_basis: str
    observed_native_states: tuple[str, ...]
    mirror_command: str
    target_visible_clearance_h: float
    reference_selection: str
    alignment_scope: str
    common_band_priority: str
    normal_correction_order: tuple[str, ...]
    single_item_radial_exception: str
    exception_receipt_required: bool


@dataclass(frozen=True)
class TwoPassBatchPolicyFormula:
    """The accepted template-first, failed-subset-second execution contract."""

    reference_profile: str
    target_count_mode: str
    required_completeness_ratio: float
    initial_batch_mode: str
    initial_base_band_h: float
    initial_closed_exterior_band_h: float
    initial_below_source_band_h: float
    candidate_bands_h: tuple[float, ...]
    audit_mode: str
    correction_mode: str
    maximum_subset_correction_rounds: int
    freeze_passed_items: bool
    allow_full_batch_retry_for_local_defects: bool
    sample_count_is_global_constant: bool


@dataclass(frozen=True)
class SandwichLayoutFormula:
    """Second-pass topology rule learned from the accepted blue-line sample."""

    activation: str
    required_order: str
    source_to_text_gap_h: float
    text_to_dimension_gap_h: float
    source_half_width_fallback_h: float
    require_text_between_source_and_dimension: bool
    failed_item_action: str
    endpoint_cluster_action: str
    candidate_order: tuple[str, ...]
    maximum_correction_rounds: int
    freeze_passed_items: bool
    status: str


@dataclass(frozen=True)
class SharpCornerCorrectionFormula:
    """Second-pass rule for a first-pass failed sharp or dense turn."""

    activation: str
    target_visible_gap_h: float
    target_text_center_formula: str
    projected_text_half_extent: str
    move_grip_index: int
    move_direction: str
    maximum_correction_rounds: int
    freeze_source_association_grips: tuple[int, ...]
    freeze_passed_items: bool
    evidence: str
    status: str


@dataclass(frozen=True)
class EndpointClusterFormula:
    """Joint layout rule for adjacent short arcs at one sharp corner."""

    activation: str
    promote_full_cluster_on_member_failure: bool
    common_side_required: bool
    common_band_required: bool
    common_band_tolerance_h: float
    same_band_first: bool
    preferred_band_rank: int
    allow_shared_endpoint_arrow_touch: bool
    allow_shared_endpoint_dimension_touch: bool
    text_arrow_overlap_is_hard: bool
    text_text_overlap_is_hard: bool
    band_escalation_only_after_hard_collision: bool
    next_band_increment_h: float
    maximum_exterior_band_rank: int
    interior_fallback: bool
    fallback_order: tuple[str, ...]
    maximum_correction_rounds: int
    freeze_passed_items: bool
    status: str


@dataclass(frozen=True)
class VectorLayoutFormula:
    formula_id: str
    geometry: CandidateGeometryFormula
    short_arc: ShortArcFormula
    soft_weights: SoftWeightsFormula
    directional_clearance: DirectionalClearanceFormula
    quantified_common_band: QuantifiedCommonBandFormula
    four_direction_text_alignment: FourDirectionTextAlignmentFormula
    two_pass_batch_policy: TwoPassBatchPolicyFormula
    sandwich_layout: SandwichLayoutFormula
    sharp_corner_correction: SharpCornerCorrectionFormula
    endpoint_cluster: EndpointClusterFormula
    require_zero_hard_solution: bool
    no_zero_hard_solution_status: str

    @property
    def weights(self) -> SoftWeightsFormula:
        """Stable public name used by planners and regression contracts."""

        return self.soft_weights


def quantified_common_band_h(
    *,
    text_height: float,
    source_width: float,
    target_text_radial_thicknesses: tuple[float, ...],
    rule: QuantifiedCommonBandFormula,
    candidate_bands_h: tuple[float, ...],
) -> tuple[float, float]:
    """Return raw and snapped grip-0 band for one continuous source path.

    For each annotation the required centreline-to-dimension distance is:

      W/2 + G_source + T_target + G_dimension

    ``T_target`` is the measured native text height after placing the angle text
    tangent to its target dimension arc.  A currently misoriented OBB is not
    allowed to inflate the whole source path: actual OBBs are audited after
    placement and any exception is repaired through text-state selection or an
    along-arc move on the failed subset.  The path snaps upward to the versioned
    H-band ladder.  This reproduces the good 1.85H sample from measured geometry
    instead of treating 1.85 as a task constant.
    """

    if text_height <= 0.0 or source_width < 0.0:
        raise ValueError("invalid quantified common-band dimensions")
    if not target_text_radial_thicknesses or any(
        value <= 0.0 for value in target_text_radial_thicknesses
    ):
        raise ValueError("target tangent text thicknesses are required")
    if rule.aggregation != "maximum_required_band_per_source_path":
        raise ValueError("unsupported quantified common-band aggregation")
    if rule.snap_policy != "ceiling_to_versioned_candidate_band":
        raise ValueError("unsupported quantified common-band snap policy")
    raw_requirements = tuple(
        (
            source_width * 0.5
            + rule.source_visible_edge_gap_h * text_height
            + thickness
            + rule.text_dimension_gap_h * text_height
        )
        / text_height
        for thickness in target_text_radial_thicknesses
    )
    raw = max(rule.minimum_band_h, max(raw_requirements))
    for candidate in candidate_bands_h:
        if candidate + 1.0e-9 >= raw:
            return raw, candidate
    raise ValueError(f"quantified common band exceeds candidate ladder: {raw:.6f}H")


@dataclass(frozen=True)
class SandwichAudit:
    """Measured source/text/dimension ordering on one native radial."""

    passed: bool
    side_sign: int
    source_edge_distance: float
    text_near_distance: float
    text_far_distance: float
    dimension_distance: float
    source_text_gap: float
    text_dimension_gap: float
    target_dimension_distance: float
    failure_reasons: tuple[str, ...]


def audit_text_between_source_and_dimension(
    center: VectorPoint,
    grip0: VectorPoint,
    text_polygon: ConvexPolygon,
    source_radius: float,
    source_half_width: float,
    text_height: float,
    source_to_text_gap_h: float,
    text_to_dimension_gap_h: float,
    side_sign: int | None = None,
) -> SandwichAudit:
    """Audit the native layout using projected vector geometry.

    The accepted visual topology is not merely "no overlapping text boxes".
    Along the local radial it must read as source visible edge, free gap, text
    OBB, free gap, dimension curve.  Projecting the real OBB makes the rule
    invariant to view rotation and text quadrant.
    """

    if source_radius <= 0.0 or source_half_width < 0.0 or text_height <= 0.0:
        raise ValueError("invalid sandwich geometry")
    if source_to_text_gap_h < 0.0 or text_to_dimension_gap_h < 0.0:
        raise ValueError("sandwich gaps cannot be negative")
    radial_x = grip0.x - center.x
    radial_y = grip0.y - center.y
    dimension_radius = hypot(radial_x, radial_y)
    if dimension_radius <= 1.0e-9:
        raise ValueError("grip0 cannot coincide with the radial centre")
    axis = VectorPoint(radial_x / dimension_radius, radial_y / dimension_radius)
    inferred_side = 1 if dimension_radius >= source_radius else -1
    side = inferred_side if side_sign is None else side_sign
    if side not in (-1, 1):
        raise ValueError("side_sign must be -1 or 1")

    projected = tuple(
        side
        * (
            (point.x - center.x) * axis.x
            + (point.y - center.y) * axis.y
            - source_radius
        )
        for point in text_polygon.points
    )
    text_near = min(projected)
    text_far = max(projected)
    dimension_distance = side * (dimension_radius - source_radius)
    source_edge = source_half_width
    source_text_gap = text_near - source_edge
    text_dimension_gap = dimension_distance - text_far
    source_gap_target = source_to_text_gap_h * text_height
    dimension_gap_target = text_to_dimension_gap_h * text_height
    # Native Tianzheng grips and child-text extents are rounded independently.
    # A one-percent-H tolerance keeps the intended 1.85H band from failing
    # because 1/3 + 1 + 1/3 evaluates to 1.8466...H, while remaining far
    # below a visually meaningful spacing change.
    gap_tolerance = max(1.0e-9, 0.01 * text_height)
    reasons: list[str] = []
    if dimension_distance <= 0.0:
        reasons.append("DIMENSION_ON_WRONG_SIDE")
    if text_near <= source_edge:
        reasons.append("TEXT_NOT_BEYOND_SOURCE_VISIBLE_EDGE")
    if text_far >= dimension_distance:
        reasons.append("TEXT_NOT_BEFORE_DIMENSION_CURVE")
    if source_text_gap + gap_tolerance < source_gap_target:
        reasons.append("SOURCE_TEXT_GAP_BELOW_TARGET")
    if text_dimension_gap + gap_tolerance < dimension_gap_target:
        reasons.append("TEXT_DIMENSION_GAP_BELOW_TARGET")
    text_thickness = max(0.0, text_far - text_near)
    target_dimension_distance = (
        source_edge + source_gap_target + text_thickness + dimension_gap_target
    )
    return SandwichAudit(
        passed=not reasons,
        side_sign=side,
        source_edge_distance=source_edge,
        text_near_distance=text_near,
        text_far_distance=text_far,
        dimension_distance=dimension_distance,
        source_text_gap=source_text_gap,
        text_dimension_gap=text_dimension_gap,
        target_dimension_distance=target_dimension_distance,
        failure_reasons=tuple(reasons),
    )


def load_vector_layout_formula(path: Path) -> VectorLayoutFormula:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError("unsupported vector layout formula schema")
    geometry = payload.get("candidate_geometry", {})
    short_arc = payload.get("short_arc", {})
    solver = payload.get("solver", {})
    fractions = tuple(float(value) for value in geometry.get("pick_fractions", ()))
    if not fractions or any(value <= 0.0 or value >= 1.0 for value in fractions):
        raise ValueError("pick fractions must lie strictly inside the source arc")
    states = tuple(str(value) for value in geometry.get("text_states", ()))
    if not states or any(value not in {"BASELINE", "MIRRORED"} for value in states):
        raise ValueError("unsupported native text state")
    radius_fractions = tuple(
        float(value) for value in geometry.get("radius_pick_fractions", ())
    )
    if not radius_fractions or any(
        value <= 0.0 or value >= 1.0 for value in radius_fractions
    ):
        raise ValueError("radius pick fractions must lie strictly inside the source arc")
    candidate = CandidateGeometryFormula(
        pick_fractions=fractions,
        radius_pick_fractions=radius_fractions,
        text_states=states,
        text_to_dimension_target_h=float(geometry["text_to_dimension_target_h"]),
        text_to_source_hard_h=float(geometry["text_to_source_hard_h"]),
        text_to_source_preferred_h=float(geometry["text_to_source_preferred_h"]),
        source_visible_edge_to_text_preferred_h=float(
            geometry.get(
                "source_visible_edge_to_text_preferred_h",
                geometry["text_to_source_preferred_h"],
            )
        ),
        text_text_hard_gap_h=float(geometry["text_text_hard_gap_h"]),
        text_text_preferred_gap_h=float(geometry["text_text_preferred_gap_h"]),
        sequence_seam_target_h=float(geometry["sequence_seam_target_h"]),
        sequence_seam_hard_h=float(geometry["sequence_seam_hard_h"]),
        dimension_dimension_hard_gap_h=float(
            geometry["dimension_dimension_hard_gap_h"]
        ),
        dimension_dimension_preferred_gap_h=float(
            geometry["dimension_dimension_preferred_gap_h"]
        ),
        dimension_shared_endpoint_exclusion_h=float(
            geometry["dimension_shared_endpoint_exclusion_h"]
        ),
        arrow_size_h=float(geometry["arrow_size_h"]),
        dimension_arc_max_step_degrees=float(geometry["dimension_arc_max_step_degrees"]),
        clearance_footprint_samples=int(geometry["clearance_footprint_samples"]),
        radius_slide_sample_spacing_h=float(geometry["radius_slide_sample_spacing_h"]),
        radius_slide_endpoint_clearance_h=float(
            geometry["radius_slide_endpoint_clearance_h"]
        ),
        radius_slide_max_samples=int(geometry["radius_slide_max_samples"]),
        radius_leader_text_gap_h=float(geometry["radius_leader_text_gap_h"]),
        radius_marker_to_text_offsets_h=tuple(
            float(value)
            for value in geometry.get("radius_marker_to_text_offsets_h", ())
        ),
        text_width_per_visible_character_h=float(
            geometry["text_width_per_visible_character_h"]
        ),
        angle_text_min_width_h=float(geometry["angle_text_min_width_h"]),
        radius_text_min_width_h=float(geometry["radius_text_min_width_h"]),
        thin_stroke_kinds=tuple(
            str(value).lower() for value in geometry.get("thin_stroke_kinds", ())
        ),
    )
    short = ShortArcFormula(
        capacity_primary_threshold=float(short_arc["capacity_primary_threshold"]),
        capacity_support_threshold=float(short_arc["capacity_support_threshold"]),
        classification_text_width_per_visible_character_h=float(
            short_arc["classification_text_width_per_visible_character_h"]
        ),
        classification_angle_text_min_width_h=float(
            short_arc["classification_angle_text_min_width_h"]
        ),
        closed_path_preferred_side=str(
            short_arc["closed_path_preferred_side"]
        ).lower(),
        closed_path_allow_interior_fallback=bool(
            short_arc["closed_path_allow_interior_fallback"]
        ),
        candidate_tangential_capacity_min=float(
            short_arc["candidate_tangential_capacity_min"]
        ),
        inner_radius_floor_h=float(short_arc["inner_radius_floor_h"]),
        pick_fractions=tuple(
            float(value) for value in short_arc.get("pick_fractions", ())
        ),
        inner_band_factors_h=tuple(
            float(value) for value in short_arc.get("inner_band_factors_h", ())
        ),
        inner_text_band_factors_h=tuple(
            float(value)
            for value in short_arc.get("inner_text_band_factors_h", ())
        ),
        text_text_hard_gap_h=float(short_arc["text_text_hard_gap_h"]),
        text_text_preferred_gap_h=float(
            short_arc["text_text_preferred_gap_h"]
        ),
        dimension_dimension_hard_gap_h=float(
            short_arc["dimension_dimension_hard_gap_h"]
        ),
        dimension_dimension_preferred_gap_h=float(
            short_arc["dimension_dimension_preferred_gap_h"]
        ),
    )
    weight_payload = payload.get("soft_weights", {})
    weight_names = tuple(SoftWeightsFormula.__dataclass_fields__)
    if set(weight_payload) != set(weight_names):
        raise ValueError("soft weight keys do not match the versioned formula")
    weights = SoftWeightsFormula(
        **{name: float(weight_payload[name]) for name in weight_names}
    )
    directional_payload = payload.get("directional_clearance", {})
    directional_names = tuple(DirectionalClearanceFormula.__dataclass_fields__)
    if set(directional_payload) != set(directional_names):
        raise ValueError("directional clearance keys do not match the versioned formula")
    directional = DirectionalClearanceFormula(
        **{name: float(directional_payload[name]) for name in directional_names}
    )
    common_payload = payload.get("quantified_common_band", {})
    common = QuantifiedCommonBandFormula(
        source_visible_edge_gap_h=float(common_payload["source_visible_edge_gap_h"]),
        text_dimension_gap_h=float(common_payload["text_dimension_gap_h"]),
        minimum_band_h=float(common_payload["minimum_band_h"]),
        aggregation=str(common_payload["aggregation"]),
        snap_policy=str(common_payload["snap_policy"]),
        text_thickness_input=str(common_payload["text_thickness_input"]),
        source_width_input=str(common_payload["source_width_input"]),
        observed_obb_role=str(common_payload["observed_obb_role"]),
        observed_obb_failure_action=str(common_payload["observed_obb_failure_action"]),
    )
    alignment_payload = payload.get("four_direction_text_alignment", {})
    alignment = FourDirectionTextAlignmentFormula(
        orientation_classes=tuple(
            str(value) for value in alignment_payload["orientation_classes"]
        ),
        orientation_basis=str(alignment_payload["orientation_basis"]),
        observed_native_states=tuple(
            str(value) for value in alignment_payload["observed_native_states"]
        ),
        mirror_command=str(alignment_payload["mirror_command"]),
        target_visible_clearance_h=float(
            alignment_payload["target_visible_clearance_h"]
        ),
        reference_selection=str(alignment_payload["reference_selection"]),
        alignment_scope=str(alignment_payload["alignment_scope"]),
        common_band_priority=str(alignment_payload["common_band_priority"]),
        normal_correction_order=tuple(
            str(value) for value in alignment_payload["normal_correction_order"]
        ),
        single_item_radial_exception=str(
            alignment_payload["single_item_radial_exception"]
        ),
        exception_receipt_required=bool(
            alignment_payload["exception_receipt_required"]
        ),
    )
    two_pass_payload = payload.get("two_pass_batch_policy", {})
    two_pass = TwoPassBatchPolicyFormula(
        reference_profile=str(two_pass_payload["reference_profile"]),
        target_count_mode=str(two_pass_payload["target_count_mode"]),
        required_completeness_ratio=float(
            two_pass_payload["required_completeness_ratio"]
        ),
        initial_batch_mode=str(two_pass_payload["initial_batch_mode"]),
        initial_base_band_h=float(two_pass_payload["initial_base_band_h"]),
        initial_closed_exterior_band_h=float(
            two_pass_payload["initial_closed_exterior_band_h"]
        ),
        initial_below_source_band_h=float(
            two_pass_payload["initial_below_source_band_h"]
        ),
        candidate_bands_h=tuple(
            float(value) for value in two_pass_payload["candidate_bands_h"]
        ),
        audit_mode=str(two_pass_payload["audit_mode"]),
        correction_mode=str(two_pass_payload["correction_mode"]),
        maximum_subset_correction_rounds=int(
            two_pass_payload["maximum_subset_correction_rounds"]
        ),
        freeze_passed_items=bool(two_pass_payload["freeze_passed_items"]),
        allow_full_batch_retry_for_local_defects=bool(
            two_pass_payload["allow_full_batch_retry_for_local_defects"]
        ),
        sample_count_is_global_constant=bool(
            two_pass_payload["sample_count_is_global_constant"]
        ),
    )
    sandwich_payload = payload.get("sandwich_layout", {})
    sandwich = SandwichLayoutFormula(
        activation=str(sandwich_payload["activation"]),
        required_order=str(sandwich_payload["required_order"]),
        source_to_text_gap_h=float(sandwich_payload["source_to_text_gap_h"]),
        text_to_dimension_gap_h=float(
            sandwich_payload["text_to_dimension_gap_h"]
        ),
        source_half_width_fallback_h=float(
            sandwich_payload["source_half_width_fallback_h"]
        ),
        require_text_between_source_and_dimension=bool(
            sandwich_payload["require_text_between_source_and_dimension"]
        ),
        failed_item_action=str(sandwich_payload["failed_item_action"]),
        endpoint_cluster_action=str(sandwich_payload["endpoint_cluster_action"]),
        candidate_order=tuple(
            str(value) for value in sandwich_payload["candidate_order"]
        ),
        maximum_correction_rounds=int(
            sandwich_payload["maximum_correction_rounds"]
        ),
        freeze_passed_items=bool(sandwich_payload["freeze_passed_items"]),
        status=str(sandwich_payload["status"]),
    )
    sharp_payload = payload.get("sharp_corner_correction", {})
    sharp = SharpCornerCorrectionFormula(
        activation=str(sharp_payload["activation"]),
        target_visible_gap_h=float(sharp_payload["target_visible_gap_h"]),
        target_text_center_formula=str(
            sharp_payload["target_text_center_formula"]
        ),
        projected_text_half_extent=str(
            sharp_payload["projected_text_half_extent"]
        ),
        move_grip_index=int(sharp_payload["move_grip_index"]),
        move_direction=str(sharp_payload["move_direction"]),
        maximum_correction_rounds=int(
            sharp_payload["maximum_correction_rounds"]
        ),
        freeze_source_association_grips=tuple(
            int(value)
            for value in sharp_payload["freeze_source_association_grips"]
        ),
        freeze_passed_items=bool(sharp_payload["freeze_passed_items"]),
        evidence=str(sharp_payload["evidence"]),
        status=str(sharp_payload["status"]),
    )
    endpoint_payload = payload.get("endpoint_cluster", {})
    endpoint = EndpointClusterFormula(
        activation=str(endpoint_payload["activation"]),
        promote_full_cluster_on_member_failure=bool(
            endpoint_payload["promote_full_cluster_on_member_failure"]
        ),
        common_side_required=bool(endpoint_payload["common_side_required"]),
        common_band_required=bool(endpoint_payload["common_band_required"]),
        common_band_tolerance_h=float(
            endpoint_payload["common_band_tolerance_h"]
        ),
        same_band_first=bool(endpoint_payload["same_band_first"]),
        preferred_band_rank=int(endpoint_payload["preferred_band_rank"]),
        allow_shared_endpoint_arrow_touch=bool(
            endpoint_payload["allow_shared_endpoint_arrow_touch"]
        ),
        allow_shared_endpoint_dimension_touch=bool(
            endpoint_payload["allow_shared_endpoint_dimension_touch"]
        ),
        text_arrow_overlap_is_hard=bool(
            endpoint_payload["text_arrow_overlap_is_hard"]
        ),
        text_text_overlap_is_hard=bool(endpoint_payload["text_text_overlap_is_hard"]),
        band_escalation_only_after_hard_collision=bool(
            endpoint_payload["band_escalation_only_after_hard_collision"]
        ),
        next_band_increment_h=float(endpoint_payload["next_band_increment_h"]),
        maximum_exterior_band_rank=int(
            endpoint_payload["maximum_exterior_band_rank"]
        ),
        interior_fallback=bool(endpoint_payload["interior_fallback"]),
        fallback_order=tuple(str(item) for item in endpoint_payload["fallback_order"]),
        maximum_correction_rounds=int(endpoint_payload["maximum_correction_rounds"]),
        freeze_passed_items=bool(endpoint_payload["freeze_passed_items"]),
        status=str(endpoint_payload["status"]),
    )
    positive_values = (
        candidate.text_to_dimension_target_h,
        candidate.text_to_source_hard_h,
        candidate.text_to_source_preferred_h,
        candidate.source_visible_edge_to_text_preferred_h,
        candidate.text_text_hard_gap_h,
        candidate.text_text_preferred_gap_h,
        candidate.sequence_seam_target_h,
        candidate.sequence_seam_hard_h,
        candidate.dimension_dimension_hard_gap_h,
        candidate.dimension_dimension_preferred_gap_h,
        candidate.dimension_shared_endpoint_exclusion_h,
        candidate.arrow_size_h,
        candidate.dimension_arc_max_step_degrees,
        candidate.radius_slide_sample_spacing_h,
        candidate.radius_slide_endpoint_clearance_h,
        candidate.radius_leader_text_gap_h,
        candidate.text_width_per_visible_character_h,
        candidate.angle_text_min_width_h,
        candidate.radius_text_min_width_h,
        short.capacity_primary_threshold,
        short.capacity_support_threshold,
        short.classification_text_width_per_visible_character_h,
        short.classification_angle_text_min_width_h,
        short.candidate_tangential_capacity_min,
        short.inner_radius_floor_h,
        short.text_text_hard_gap_h,
        short.text_text_preferred_gap_h,
        short.dimension_dimension_hard_gap_h,
        short.dimension_dimension_preferred_gap_h,
        directional.base_band_h,
        directional.closed_exterior_band_h,
        directional.below_source_band_h,
        directional.minimum_increment_h,
        directional.exterior_polygon_arc_step_degrees,
    )
    if (
        any(value <= 0 for value in positive_values)
        or candidate.clearance_footprint_samples < 5
        or candidate.radius_slide_max_samples < 3
        or not candidate.radius_marker_to_text_offsets_h
        or any(value <= 0 for value in candidate.radius_marker_to_text_offsets_h)
        or not candidate.thin_stroke_kinds
        or len(set(candidate.thin_stroke_kinds)) != len(candidate.thin_stroke_kinds)
    ):
        raise ValueError("invalid non-positive formula coefficient")
    if candidate.text_to_source_hard_h >= candidate.text_to_source_preferred_h:
        raise ValueError("hard source clearance must be below preferred clearance")
    if (
        candidate.text_to_source_hard_h
        >= candidate.source_visible_edge_to_text_preferred_h
    ):
        raise ValueError(
            "hard source clearance must be below visible-edge preferred clearance"
        )
    if candidate.text_text_hard_gap_h >= candidate.text_text_preferred_gap_h:
        raise ValueError("hard text gap must be below preferred text gap")
    if candidate.sequence_seam_target_h >= candidate.sequence_seam_hard_h:
        raise ValueError("target seam gap must be below hard seam gap")
    if (
        candidate.dimension_dimension_hard_gap_h
        >= candidate.dimension_dimension_preferred_gap_h
    ):
        raise ValueError("hard dimension gap must be below preferred dimension gap")
    if candidate.text_to_dimension_target_h <= 0.5:
        raise ValueError("text centre must clear its own dimension line")
    if short.capacity_primary_threshold >= short.capacity_support_threshold:
        raise ValueError("short-arc primary threshold must be below support threshold")
    if short.closed_path_preferred_side not in {"exterior", "interior"}:
        raise ValueError("closed-path short-arc side must be exterior or interior")
    if short.text_text_hard_gap_h >= short.text_text_preferred_gap_h:
        raise ValueError("short-arc hard text gap must be below preferred text gap")
    if (
        short.dimension_dimension_hard_gap_h
        >= short.dimension_dimension_preferred_gap_h
    ):
        raise ValueError(
            "short-arc hard dimension gap must be below preferred dimension gap"
        )
    if directional.closed_exterior_band_h < directional.base_band_h:
        raise ValueError("closed exterior band cannot be below the base band")
    if directional.below_source_band_h < directional.base_band_h:
        raise ValueError("below-source band cannot be below the base band")
    if (
        directional.below_source_band_h - directional.base_band_h
        + 1.0e-12
        < directional.minimum_increment_h
    ):
        raise ValueError("below-source band increment is below the minimum increment")
    if two_pass.target_count_mode != "dynamic_exact_inventory":
        raise ValueError("two-pass target count must come from dynamic exact inventory")
    if two_pass.required_completeness_ratio != 1.0:
        raise ValueError("two-pass completeness ratio must be exactly one")
    if two_pass.initial_batch_mode != "one_offline_formula_one_owned_batch":
        raise ValueError("unsupported two-pass initial batch mode")
    if two_pass.audit_mode != "one_native_vector_and_source_audit":
        raise ValueError("unsupported two-pass audit mode")
    if two_pass.correction_mode != "one_failed_subset_only":
        raise ValueError("unsupported two-pass correction mode")
    if two_pass.maximum_subset_correction_rounds != 1:
        raise ValueError("two-pass policy permits exactly one subset correction round")
    if not two_pass.freeze_passed_items:
        raise ValueError("two-pass policy must freeze passed items")
    if two_pass.allow_full_batch_retry_for_local_defects:
        raise ValueError("two-pass policy forbids full-batch local-defect retries")
    if two_pass.sample_count_is_global_constant:
        raise ValueError("sample inventory count cannot be a global constant")
    if two_pass.candidate_bands_h != short.inner_band_factors_h:
        raise ValueError("two-pass bands must match the versioned directional formula")
    if (
        two_pass.initial_base_band_h != directional.base_band_h
        or two_pass.initial_closed_exterior_band_h
        != directional.closed_exterior_band_h
        or two_pass.initial_below_source_band_h != directional.below_source_band_h
    ):
        raise ValueError("two-pass initial bands must match directional clearance")
    if min(
        common.source_visible_edge_gap_h,
        common.text_dimension_gap_h,
        common.minimum_band_h,
    ) <= 0.0:
        raise ValueError("quantified common-band coefficients must be positive")
    if common.minimum_band_h != directional.base_band_h:
        raise ValueError("quantified common-band minimum must match base band")
    if common.text_thickness_input != "measured_native_text_height_on_target_tangent":
        raise ValueError("quantified common-band must use target-tangent text height")
    if common.source_width_input != "measured_polyline_constant_width":
        raise ValueError("quantified common-band must use measured source width")
    if common.observed_obb_role != "post_layout_local_failure_detection_only":
        raise ValueError("observed OBB must remain a post-layout local audit")
    if common.observed_obb_failure_action != (
        "report_only__never_mutate_text_or_inflate_global_band"
    ):
        raise ValueError("unsupported observed OBB failure action")
    if alignment.orientation_classes != ("TOP", "BOTTOM", "LEFT", "RIGHT"):
        raise ValueError("four-direction alignment classes are invalid")
    if alignment.orientation_basis != (
        "dominant_component_of_source_midpoint_to_text_center"
    ):
        raise ValueError("four-direction alignment basis is invalid")
    if alignment.observed_native_states != ("BASELINE", "MIRRORED"):
        raise ValueError("native text-state pair is incomplete")
    if alignment.mirror_command != "TMirDim":
        raise ValueError("native mirror command is invalid")
    if alignment.target_visible_clearance_h != common.source_visible_edge_gap_h:
        raise ValueError("four-direction clearance must match common-band clearance")
    if alignment.reference_selection != (
        "minimum_hard_pass_clearance_at_or_above_target"
    ):
        raise ValueError("four-direction reference selection is invalid")
    if alignment.alignment_scope != "one_continuous_source_polyline":
        raise ValueError("four-direction alignment scope is invalid")
    if alignment.common_band_priority != "preserve_before_local_exception":
        raise ValueError("common band must precede local exceptions")
    if alignment.normal_correction_order != (
        "choose_baseline_or_mirrored",
        "along_arc_shift",
        "promote_contiguous_failed_cluster_one_band",
    ):
        raise ValueError("four-direction correction order is invalid")
    if alignment.single_item_radial_exception != (
        "last_resort_only_after_all_normal_candidates_fail"
    ) or not alignment.exception_receipt_required:
        raise ValueError("single-item exception policy is invalid")
    if sandwich.activation != "second_pass_native_vector_audit":
        raise ValueError("sandwich layout is restricted to the second-pass audit")
    if sandwich.required_order != (
        "source_visible_edge_then_text_obb_then_dimension_curve"
    ):
        raise ValueError("unsupported source-text-dimension order")
    if min(
        sandwich.source_to_text_gap_h,
        sandwich.text_to_dimension_gap_h,
        sandwich.source_half_width_fallback_h,
    ) <= 0.0:
        raise ValueError("sandwich layout distances must be positive")
    if not sandwich.require_text_between_source_and_dimension:
        raise ValueError("text-between topology is mandatory")
    if sandwich.failed_item_action != "recompute_side_and_band":
        raise ValueError("failed sandwich items must recompute side and band")
    if sandwich.endpoint_cluster_action != "flip_or_escalate_as_one_group":
        raise ValueError("endpoint clusters must be corrected as one group")
    if sandwich.candidate_order != (
        "same_side_balanced_band",
        "cluster_shared_opposite_side_balanced_band",
        "cluster_shared_side_next_band",
        "manual_review",
    ):
        raise ValueError("unsupported sandwich candidate order")
    if sandwich.maximum_correction_rounds != 1 or not sandwich.freeze_passed_items:
        raise ValueError("sandwich layout permits one failed-subset correction only")
    if sharp.activation not in {
        "failed_subset_only_after_initial_audit",
        "calibration_candidate_only__runtime_dispatch_disabled_until_promotion",
    }:
        raise ValueError(
            "sharp-corner correction must remain failed-subset or calibration-only"
        )
    if sharp.target_visible_gap_h <= 0.0:
        raise ValueError("sharp-corner visible gap must be positive")
    if sharp.move_grip_index != 0:
        raise ValueError("sharp-corner correction may only move native grip0")
    if sharp.move_direction != "current_grip0_radial_unit":
        raise ValueError("sharp-corner correction must follow the native grip0 radial")
    if sharp.target_text_center_formula != (
        "source_radius + side_sign * (source_half_width + "
        "target_visible_gap_h * H + projected_text_half_extent)"
    ):
        raise ValueError("sharp-corner target-centre formula is not the validated form")
    if sharp.projected_text_half_extent != (
        "max_abs_obb_support_about_text_center_on_current_grip0_radial"
    ):
        raise ValueError("sharp-corner text support must use the true radial OBB")
    if sharp.maximum_correction_rounds != 1:
        raise ValueError("sharp-corner correction permits exactly one residual move")
    if sharp.freeze_source_association_grips != (2, 3):
        raise ValueError("sharp-corner correction must freeze source grips2/3")
    if not sharp.freeze_passed_items:
        raise ValueError("sharp-corner correction must freeze passed items")
    if not sharp.evidence or not sharp.status:
        raise ValueError("sharp-corner correction requires evidence and status")
    if endpoint.activation != "adjacent_short_arcs_sharing_source_endpoint":
        raise ValueError("unsupported endpoint-cluster activation")
    if not endpoint.promote_full_cluster_on_member_failure:
        raise ValueError("one failed endpoint member must promote its local cluster")
    if not endpoint.common_side_required or not endpoint.common_band_required:
        raise ValueError("endpoint clusters require one common side and one common band")
    if endpoint.common_band_tolerance_h < 0.0:
        raise ValueError("endpoint-cluster band tolerance cannot be negative")
    if not endpoint.same_band_first or endpoint.preferred_band_rank != 0:
        raise ValueError("endpoint clusters must begin on one shared close band")
    if not (
        endpoint.allow_shared_endpoint_arrow_touch
        and endpoint.allow_shared_endpoint_dimension_touch
    ):
        raise ValueError("endpoint clusters must preserve the chained native seam")
    if not endpoint.text_arrow_overlap_is_hard or not endpoint.text_text_overlap_is_hard:
        raise ValueError("endpoint-cluster text collisions must remain hard")
    if not endpoint.band_escalation_only_after_hard_collision:
        raise ValueError("endpoint-cluster bands may escalate only after a hard collision")
    if endpoint.next_band_increment_h <= 0.0 or endpoint.maximum_exterior_band_rank < 1:
        raise ValueError("invalid endpoint-cluster band formula")
    if endpoint.interior_fallback:
        raise ValueError("endpoint-cluster first version forbids automatic interior fallback")
    if endpoint.fallback_order != (
        "along_arc",
        "next_exterior_band",
        "manual_review",
    ):
        raise ValueError("unsupported endpoint-cluster fallback order")
    if endpoint.maximum_correction_rounds != 1 or not endpoint.freeze_passed_items:
        raise ValueError("endpoint clusters permit one failed-subset correction only")
    if not endpoint.status:
        raise ValueError("endpoint-cluster formula requires a status")
    if not short.pick_fractions or any(
        value <= 0.0 or value >= 1.0 for value in short.pick_fractions
    ):
        raise ValueError("short-arc pick fractions must lie strictly inside the arc")
    if not short.inner_band_factors_h or any(
        value <= 0.0 for value in short.inner_band_factors_h
    ):
        raise ValueError("short-arc inner bands must be positive text-height factors")
    if (
        not short.inner_text_band_factors_h
        or short.inner_text_band_factors_h[0] != 0.0
        or any(value < 0.0 for value in short.inner_text_band_factors_h)
        or tuple(sorted(set(short.inner_text_band_factors_h)))
        != short.inner_text_band_factors_h
    ):
        raise ValueError(
            "short-arc inner text bands must be unique ordered non-negative "
            "text-height factors starting at zero"
        )
    if solver.get("objective") != "lexicographic_hard_vector_then_soft_score":
        raise ValueError("formula must use hard-vector-first optimisation")
    if any(value < 0 for value in weights.__dict__.values()):
        raise ValueError("soft weights cannot be negative")
    return VectorLayoutFormula(
        formula_id=str(payload["formula_id"]),
        geometry=candidate,
        short_arc=short,
        soft_weights=weights,
        directional_clearance=directional,
        quantified_common_band=common,
        four_direction_text_alignment=alignment,
        two_pass_batch_policy=two_pass,
        sandwich_layout=sandwich,
        sharp_corner_correction=sharp,
        endpoint_cluster=endpoint,
        require_zero_hard_solution=bool(solver.get("require_zero_hard_solution", True)),
        no_zero_hard_solution_status=str(
            solver.get("no_zero_hard_solution_status", "NEEDS_MANUAL_REVIEW")
        ),
    )


def bbox_residual_distance(
    source_point: VectorPoint,
    text_polygon: ConvexPolygon,
    outward_normal: VectorPoint,
    text_height: float,
    source_clearance_h: float,
) -> float:
    """Return the measured post-generation normal correction for grip0.

    This function intentionally has no quadrant constants.  Directional
    differences emerge from the real native text polygon projected onto the
    local source normal.
    """

    if text_height <= 0 or source_clearance_h < 0:
        raise ValueError("invalid text-height clearance input")
    actual = signed_near_edge_clearance(source_point, text_polygon, outward_normal)
    return max(0.0, text_height * source_clearance_h - actual)


def sharp_corner_grip0_radial_residual(
    center: VectorPoint,
    grip0: VectorPoint,
    text_polygon: ConvexPolygon,
    source_radius: float,
    source_half_width: float,
    text_height: float,
    target_visible_gap_h: float,
    side_sign: int = 1,
) -> tuple[VectorPoint, float, float]:
    """Return the exact second-pass grip0 residual for a sharp turn.

    The native object projects a grip0 request onto its current radial.  The
    correction is therefore computed on that same axis from the source's
    visible edge to the nearest projected text edge.  ``side_sign=1`` is the
    validated exterior branch.  The interior branch is represented for future
    bounded validation but is not promoted by this helper alone.

    Returns ``(move_vector, target_text_center_radius, projected_half_extent)``.
    """

    if side_sign not in (-1, 1):
        raise ValueError("side_sign must be -1 or 1")
    if source_radius < 0.0 or source_half_width < 0.0:
        raise ValueError("source radius and half width cannot be negative")
    if text_height <= 0.0 or target_visible_gap_h <= 0.0:
        raise ValueError("text height and visible gap must be positive")

    radial_x = grip0.x - center.x
    radial_y = grip0.y - center.y
    radial_length = hypot(radial_x, radial_y)
    if radial_length <= 1.0e-9:
        raise ValueError("grip0 cannot coincide with the radial centre")
    axis = VectorPoint(radial_x / radial_length, radial_y / radial_length)

    point_count = len(text_polygon.points)
    text_center = VectorPoint(
        sum(point.x for point in text_polygon.points) / point_count,
        sum(point.y for point in text_polygon.points) / point_count,
    )
    current_center_radius = (
        (text_center.x - center.x) * axis.x
        + (text_center.y - center.y) * axis.y
    )
    projected_half_extent = max(
        abs(
            (point.x - text_center.x) * axis.x
            + (point.y - text_center.y) * axis.y
        )
        for point in text_polygon.points
    )
    target_center_radius = source_radius + side_sign * (
        source_half_width
        + target_visible_gap_h * text_height
        + projected_half_extent
    )
    residual = target_center_radius - current_center_radius
    return (
        VectorPoint(axis.x * residual, axis.y * residual),
        target_center_radius,
        projected_half_extent,
    )
