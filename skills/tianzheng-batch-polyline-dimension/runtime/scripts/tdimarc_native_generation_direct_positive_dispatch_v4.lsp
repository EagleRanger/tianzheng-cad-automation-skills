(vl-load-com)

;; Direct positive dispatcher V4.
;;
;; V3 entered the measured TDIMARC prompt adapter only after the frozen route
;; had already returned exactly one ordinary survivor.  A zero-survivor result
;; therefore bypassed the new formula completely.  V4 makes the direct route
;; reachable from both states:
;;   - no ordinary survivor; or
;;   - one ordinary survivor below the normal band.
;;
;; The source pick fallback reuses the frozen kernel's verified point-on-arc
;; function.  It does not introduce an offline coordinate approximation.

(defun cx:dp4-audit-detail (audit)
  (if audit
    (cx:cs-safe-audit-diagnostic audit)
    "placement=NO_AUDIT,rank=0,actual=0,expected=0,residual=1e99"))

(defun cx:dp4-run-one
  (entity segment offset expected-style
    / geometry text-height effective-offset result detail added ordinary-count
       current-audit current-rank current-valid target-wcs target-ucs pick
       fallback-points trigger trial candidate-added candidate-audit
       candidate-rank candidate-valid accepted)
  (setq geometry (cx:ups-arc-geometry entity segment)
        text-height (cx:ups-text-height-from-seed offset)
        effective-offset
          (if (and (listp geometry) (= (car geometry) "PASS")
                   (> text-height 1e-9))
            (cx:ups-outer-offset (nth 1 geometry) text-height)
            offset)
        result
          (cx:sp2-v12-run-one
            entity segment effective-offset expected-style)
        detail
          (cx:cs-append-detail
            (cx:cs-result-detail result)
            (cx:ups-formula-detail geometry text-height effective-offset))
        result (cx:cs-with-detail result detail)
        added (cx:cs-result-added result)
        ordinary-count (length added)
        current-audit
          (if (= ordinary-count 1)
            (cx:pg-audit entity "ARC" segment (car added) effective-offset)
            nil)
        current-rank (cx:cs-safe-audit-rank current-audit)
        current-valid (> current-rank 0)
        target-wcs (cx:tp5-dimension-point-wcs geometry text-height)
        target-ucs (if target-wcs (trans target-wcs 0 1) nil)
        pick (nth 2 result))

  ;; A failed ordinary route can return no useful pick.  Reuse the verified
  ;; original-polyline midpoint pick instead of making the direct route
  ;; unreachable.
  (if (null pick)
    (progn
      (setq fallback-points
        (cx:fb-segment-points entity segment 0.50 effective-offset))
      (if fallback-points (setq pick (car fallback-points)))))

  (cond
    ((and (= ordinary-count 1) (>= current-rank 2))
      (cx:cs-with-detail result
        (cx:cs-append-detail detail
          (strcat "DIRECT_USER_POSITIVE_DISPATCH_V4_SKIPPED{"
            "trigger=ORDINARY_ALREADY_NORMAL,"
            (cx:dp4-audit-detail current-audit) "}"))))

    ((or (null target-ucs) (null pick))
      (if added (cx:cs-delete-live-handles added))
      (list nil '() pick target-ucs
        (cx:cs-append-detail detail
          (strcat "DIRECT_USER_POSITIVE_DISPATCH_V4_UNAVAILABLE{"
            "ordinary_survivor_count=" (itoa ordinary-count)
            ",target_available=" (if target-ucs "YES" "NO")
            ",pick_available=" (if pick "YES" "NO") "}"))))

    (t
      (setq trigger
        (if (= ordinary-count 0)
          "NO_ORDINARY_SURVIVOR"
          "CURRENT_RANK_BELOW_2"))
      (if added (cx:pg-set-visible added nil))
      (setq trial
              (cx:sp2-create-candidate
                entity segment expected-style pick target-ucs effective-offset)
            candidate-added (nth 1 trial)
            candidate-audit (nth 2 trial)
            candidate-rank (cx:cs-safe-audit-rank candidate-audit)
            candidate-valid (nth 3 trial)
            accepted
              (and candidate-valid
                   (> candidate-rank 0)
                   (or (not current-valid)
                       (cx:ups-placement-better-p
                         candidate-audit current-audit)))
            detail
              (cx:cs-append-detail detail
                (strcat
                  "DIRECT_USER_POSITIVE_DISPATCH_V4{"
                  "route=DIRECT_ON_ZERO_OR_LOW_RANK"
                  ",trigger=" trigger
                  ",ordinary_survivor_count=" (itoa ordinary-count)
                  ",selection=ORIGINAL_ACDBPOLYLINE_ARC"
                  ",pick_fallback=" (if fallback-points "MIDPOINT" "NO")
                  ",confirm_arc=SOURCE_ARC_MIDPOINT"
                  ",final_position=E6_DIMENSION_ARC_BAND"
                  ",target_wcs=" (vl-princ-to-string target-wcs)
                  ",target_ucs=" (vl-princ-to-string target-ucs)
                  ",candidate=" (cx:fb-join candidate-added)
                  ",accepted=" (if accepted "YES" "NO")
                  "," (cx:dp4-audit-detail candidate-audit)
                  ",prompt_trace=" cx:*sp2-last-trace* "}")))
      (if accepted
        (progn
          (if added (cx:cs-delete-live-handles added))
          (cx:cs-with-detail
            (list (car trial) candidate-added pick target-ucs detail)
            detail))
        (progn
          (if candidate-added
            (cx:cs-delete-live-handles candidate-added))
          (if current-valid
            (progn
              (cx:pg-set-visible added T)
              (cx:cs-with-detail result detail))
            (progn
              (if added (cx:cs-delete-live-handles added))
              (list nil '() pick target-ucs detail))))))))

(defun cx:fb-run-one (entity segment offset expected-style)
  (cx:dp4-run-one entity segment offset expected-style))

(princ)

