(vl-load-com)

;; User-positive native angular-dimension formula V1.
;;
;; Authority: live native handle E6 on source 87 / ARC / 6, measured without
;; mutation on 2026-08-26.  Grips 0 and 1 form the dimension arc, grips 2 and
;; 3 are the source endpoints, and grip 4 is the native text anchor.
;;
;; The approved object proves that two quantities must remain independent:
;;   1. dimension arc side and radius band;
;;   2. text-anchor side and clearance from the dimension arc.
;; The previous formula incorrectly inferred both from one signed offset and
;; accepted a compressed rank-1 object merely because it was near 1.85H.

(if (not (boundp 'cx:*ups-seed-reference-band-h*))
  (setq cx:*ups-seed-reference-band-h* 1.85))
(if (not (boundp 'cx:*ups-dimension-band-h*))
  (setq cx:*ups-dimension-band-h* 1.825633854835873))
(if (not (boundp 'cx:*ups-text-anchor-extra-h*))
  (setq cx:*ups-text-anchor-extra-h* 0.924369747624199))
(if (not (boundp 'cx:*ups-measured-text-anchor-extra*))
  (setq cx:*ups-measured-text-anchor-extra* 1.650000000))

(defun cx:ups-center-from-bulge (p0 p1 bulge / dx dy chord mx my center-offset)
  (setq dx (- (car p1) (car p0))
        dy (- (cadr p1) (cadr p0))
        chord (distance p0 p1)
        mx (/ (+ (car p0) (car p1)) 2.0)
        my (/ (+ (cadr p0) (cadr p1)) 2.0))
  (if (and (> chord 1e-9) (> (abs bulge) 1e-10))
    (progn
      (setq center-offset
        (/ (* chord (- 1.0 (* bulge bulge))) (* 4.0 bulge)))
      (list
        (- mx (* (/ dy chord) center-offset))
        (+ my (* (/ dx chord) center-offset))
        0.0))
    nil))

(defun cx:ups-arc-geometry
  (entity segment / object bulge-result p0-result pm-result p1-result
     bulge p0 pm p1 center chord radius)
  (setq object
    (vl-catch-all-apply 'vlax-ename->vla-object (list entity)))
  (if (or (vl-catch-all-error-p object) (null object))
    (list "FAIL" "SOURCE_OBJECT")
    (progn
      (setq bulge-result
        (vl-catch-all-apply 'vla-GetBulge (list object segment))
            p0-result
        (vl-catch-all-apply 'vlax-curve-getPointAtParam
          (list entity segment))
            pm-result
        (vl-catch-all-apply 'vlax-curve-getPointAtParam
          (list entity (+ segment 0.5)))
            p1-result
        (vl-catch-all-apply 'vlax-curve-getPointAtParam
          (list entity (1+ segment))))
      (if (or (vl-catch-all-error-p bulge-result)
              (vl-catch-all-error-p p0-result)
              (vl-catch-all-error-p pm-result)
              (vl-catch-all-error-p p1-result)
              (not (numberp bulge-result))
              (<= (abs bulge-result) 1e-10)
              (null p0-result) (null pm-result) (null p1-result))
        (list "FAIL" "ARC_GEOMETRY")
        (progn
          (setq bulge bulge-result
                p0 p0-result
                pm pm-result
                p1 p1-result
                center (cx:ups-center-from-bulge p0 p1 bulge)
                chord (distance p0 p1)
                radius
                  (/ (* chord (+ 1.0 (* bulge bulge)))
                     (* 4.0 (abs bulge))))
          (if center
            (list "PASS" bulge p0 pm p1 center radius)
            (list "FAIL" "ARC_CENTER")))))))

(defun cx:ups-unit-from-center (center point / vector magnitude)
  (setq vector (mapcar '- point center)
        magnitude (distance '(0.0 0.0 0.0) vector))
  (if (> magnitude 1e-9)
    (mapcar '(lambda (value) (/ value magnitude)) vector)
    nil))

(defun cx:ups-text-height-from-seed (offset)
  (if (and (numberp offset)
           (> (abs offset) 1e-9)
           (> cx:*ups-seed-reference-band-h* 1e-9))
    (/ (abs offset) cx:*ups-seed-reference-band-h*)
    0.0))

(defun cx:ups-text-height-from-effective (offset)
  (if (and (numberp offset)
           (> (abs offset) 1e-9)
           (> cx:*ups-dimension-band-h* 1e-9))
    (/ (abs offset) cx:*ups-dimension-band-h*)
    0.0))

(defun cx:ups-outer-offset (bulge text-height / magnitude)
  (setq magnitude (* text-height cx:*ups-dimension-band-h*))
  ;; In the verified full-batch normal convention, bulge*offset > 0 is inward.
  ;; Therefore the external-radius side always has the opposite sign to bulge.
  (if (> bulge 0.0) (- magnitude) magnitude))

(defun cx:ups-target-text-point-wcs
  (geometry text-height / pm center radius unit target-radius)
  (if (or (not (listp geometry)) (/= (car geometry) "PASS"))
    nil
    (progn
      (setq pm (nth 3 geometry)
            center (nth 5 geometry)
            radius (nth 6 geometry)
            unit (cx:ups-unit-from-center center pm)
            target-radius
              (+ radius
                 (* text-height
                   (+ cx:*ups-dimension-band-h*
                      cx:*ups-text-anchor-extra-h*))))
      (if unit
        (mapcar '+ center
          (mapcar '(lambda (value) (* value target-radius)) unit))
        nil))))

(defun cx:ups-formula-detail (geometry text-height effective-offset)
  (strcat
    "USER_POSITIVE_V1{dimension_side=OUTER_RADIUS"
    ",effective_offset=" (rtos effective-offset 2 9)
    ",dimension_band_h=" (rtos cx:*ups-dimension-band-h* 2 9)
    ",text_anchor_extra_h=" (rtos cx:*ups-text-anchor-extra-h* 2 9)
    ",text_anchor_extra="
      (rtos (* text-height cx:*ups-text-anchor-extra-h*) 2 9)
    ",text_anchor_radius_h="
      (rtos (+ cx:*ups-dimension-band-h*
               cx:*ups-text-anchor-extra-h*) 2 9)
    ",direction_basis=SOURCE_ARC_CENTER_TO_MIDPOINT"
    ",acceptance=ENDPOINT_ASSOCIATION_PLUS_NATIVE_BBOX_CLEARANCE}"))

;; The complete verified V12 dispatcher is preserved under cx:sp2-v12-run-one.
;; This override changes only the signed seed and its magnitude.
(defun cx:fb-run-one
  (entity segment offset expected-style / geometry text-height effective-offset result)
  (setq geometry (cx:ups-arc-geometry entity segment)
        text-height (cx:ups-text-height-from-seed offset)
        effective-offset
          (if (and (listp geometry) (= (car geometry) "PASS")
                   (> text-height 1e-9))
            (cx:ups-outer-offset (nth 1 geometry) text-height)
            offset)
        result
          (cx:sp2-v12-run-one
            entity segment effective-offset expected-style))
  (cx:gr-append-result-detail result
    (cx:ups-formula-detail geometry text-height effective-offset)))

(defun cx:ups-placement-better-p (candidate current)
  (and candidate
       (> (cx:cs-safe-audit-rank candidate) 0)
       (or (null current)
           (> (cx:cs-safe-audit-rank candidate)
              (cx:cs-safe-audit-rank current))
           (and (= (cx:cs-safe-audit-rank candidate)
                   (cx:cs-safe-audit-rank current))
                (< (abs (nth 4 candidate))
                   (abs (nth 4 current)))))))

;; If Tianzheng still creates a compressed rank-1 native object, recreate only
;; that object once using the measured native text-anchor point.  This is a
;; creation-position correction, not a post-creation grip move.
(defun cx:cs-settle-final-result
  (entity segment offset expected-style result
    / original-added detail geometry text-height target-wcs target-ucs pick
       current-audit trial added candidate-audit valid accepted)
  (setq original-added (cx:cs-result-added result)
        detail (cx:cs-result-detail result))
  (if (/= (length original-added) 1)
    result
    (progn
      (setq current-audit
        (cx:pg-audit entity "ARC" segment (car original-added) offset))
      (if (/= (cx:cs-safe-audit-rank current-audit) 1)
        result
        (progn
          (setq geometry (cx:ups-arc-geometry entity segment)
                text-height (cx:ups-text-height-from-effective offset)
                target-wcs
                  (cx:ups-target-text-point-wcs geometry text-height)
                target-ucs (if target-wcs (trans target-wcs 0 1) nil)
                pick (nth 2 result))
          (if (or (null target-ucs) (null pick))
            (cx:cs-with-detail result
              (cx:cs-append-detail detail
                "USER_POSITIVE_FINAL_POSITION{status=GEOMETRY_UNAVAILABLE}"))
            (progn
              (cx:pg-set-visible original-added nil)
              (setq trial
                (cx:sp2-create-candidate
                  entity segment expected-style pick target-ucs offset)
                    added (nth 1 trial)
                    candidate-audit (nth 2 trial)
                    valid (nth 3 trial)
                    accepted
                      (and valid
                           (cx:ups-placement-better-p
                             candidate-audit current-audit)))
              (setq detail
                (cx:cs-append-detail detail
                  (strcat
                    "USER_POSITIVE_FINAL_POSITION{target_point_ucs="
                    (vl-princ-to-string target-ucs)
                    ",added=" (cx:fb-join added)
                    ",accepted=" (if accepted "YES" "NO")
                    "," (cx:cs-safe-audit-diagnostic candidate-audit) "}")))
              (if accepted
                (progn
                  (cx:cs-delete-live-handles original-added)
                  (cx:cs-with-detail
                    (list (car trial) added pick target-ucs detail) detail))
                (progn
                  (if added (cx:cs-delete-live-handles added))
                  (cx:pg-set-visible original-added T)
                  (cx:cs-with-detail result detail))))))))))

(princ)
