(vl-load-com)

;; Direct positive dispatcher V3.
;;
;; V2 could leave the ordinary survivor in the drawing even when the final
;; V5 endpoint audit ranked it zero.  V3 treats endpoint association as part
;; of native-object validity: an endpoint-invalid ordinary object may be used
;; only as temporary evidence and is deleted if the direct repair also fails.

(defun cx:dp3-audit-detail (audit)
  (if audit
    (cx:cs-safe-audit-diagnostic audit)
    "placement=NO_AUDIT,rank=0,actual=0,expected=0,residual=1e99"))

(defun cx:dp3-run-one
  (entity segment offset expected-style
    / geometry text-height effective-offset result detail added current-audit
       target-wcs target-ucs pick trial candidate-added candidate-audit
       candidate-valid accepted current-valid)
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
        added (cx:cs-result-added result))

  (if (/= (length added) 1)
    result
    (progn
      (setq current-audit
              (cx:pg-audit entity "ARC" segment (car added) effective-offset)
            current-valid (> (cx:cs-safe-audit-rank current-audit) 0)
            target-wcs (cx:tp5-dimension-point-wcs geometry text-height)
            target-ucs (if target-wcs (trans target-wcs 0 1) nil)
            pick (nth 2 result))
      (if (or (>= (cx:cs-safe-audit-rank current-audit) 2)
              (null target-ucs) (null pick))
        (if current-valid
          (cx:cs-with-detail result
            (cx:cs-append-detail detail
              (strcat "DIRECT_USER_POSITIVE_DISPATCH_V3_SKIPPED{"
                (cx:dp3-audit-detail current-audit) "}")))
          (progn
            (cx:cs-delete-live-handles added)
            (list nil '() pick target-ucs
              (cx:cs-append-detail detail
                (strcat "CURRENT_ENDPOINT_INVALID_DISCARDED{"
                  (cx:dp3-audit-detail current-audit) "}")))))
        (progn
          (cx:pg-set-visible added nil)
          (setq trial
                  (cx:sp2-create-candidate
                    entity segment expected-style pick target-ucs effective-offset)
                candidate-added (nth 1 trial)
                candidate-audit (nth 2 trial)
                candidate-valid (nth 3 trial)
                accepted
                  (and candidate-valid
                       (cx:ups-placement-better-p
                         candidate-audit current-audit))
                detail
                  (cx:cs-append-detail detail
                    (strcat
                      "DIRECT_USER_POSITIVE_DISPATCH_V3{"
                      "selection=ORIGINAL_ACDBPOLYLINE_ARC"
                      ",trigger=CURRENT_RANK_BELOW_2"
                      ",confirm_arc=SOURCE_ARC_MIDPOINT"
                      ",final_position=E6_DIMENSION_ARC_BAND"
                      ",target_wcs=" (vl-princ-to-string target-wcs)
                      ",target_ucs=" (vl-princ-to-string target-ucs)
                      ",candidate=" (cx:fb-join candidate-added)
                      ",accepted=" (if accepted "YES" "NO")
                      "," (cx:dp3-audit-detail candidate-audit)
                      ",prompt_trace=" cx:*sp2-last-trace* "}")))
          (if accepted
            (progn
              (cx:cs-delete-live-handles added)
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
                  (cx:cs-delete-live-handles added)
                  (list nil '() pick target-ucs
                    (cx:cs-append-detail detail
                      (strcat "CURRENT_ENDPOINT_INVALID_DISCARDED{"
                        (cx:dp3-audit-detail current-audit) "}"))))))))))))

(defun cx:fb-run-one (entity segment offset expected-style)
  (cx:dp3-run-one entity segment offset expected-style))

(princ)
