(vl-load-com)

;; Direct positive dispatcher V2.
;; Run the measured final-position correction whenever the ordinary survivor
;; has not already reached rank 2.  V1 incorrectly required the survivor to
;; be exactly rank 1 under the positive-side audit; an ordinary rank-1 result
;; is rank 0 when re-audited against the opposite/positive target, so V1
;; skipped the very correction that was meant to change its side.

(defun cx:dp2-audit-detail (audit)
  (if audit
    (cx:cs-safe-audit-diagnostic audit)
    "placement=NO_AUDIT,rank=0,actual=0,expected=0,residual=1e99"))

(defun cx:dp2-run-one
  (entity segment offset expected-style
    / geometry text-height effective-offset result detail added current-audit
       target-wcs target-ucs pick trial candidate-added candidate-audit
       candidate-valid accepted)
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
            target-wcs (cx:ups-target-text-point-wcs geometry text-height)
            target-ucs (if target-wcs (trans target-wcs 0 1) nil)
            pick (nth 2 result))
      (if (or (>= (cx:cs-safe-audit-rank current-audit) 2)
              (null target-ucs) (null pick))
        (cx:cs-with-detail result
          (cx:cs-append-detail detail
            (strcat "DIRECT_USER_POSITIVE_DISPATCH_V2_SKIPPED{"
              (cx:dp2-audit-detail current-audit) "}")))
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
                      "DIRECT_USER_POSITIVE_DISPATCH_V2{"
                      "selection=ORIGINAL_ACDBPOLYLINE_ARC"
                      ",trigger=CURRENT_RANK_BELOW_2"
                      ",final_position=E6_OUTER_RADIAL_TEXT_ANCHOR"
                      ",target_wcs=" (vl-princ-to-string target-wcs)
                      ",target_ucs=" (vl-princ-to-string target-ucs)
                      ",candidate=" (cx:fb-join candidate-added)
                      ",accepted=" (if accepted "YES" "NO")
                      "," (cx:dp2-audit-detail candidate-audit)
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
              (cx:pg-set-visible added T)
              (cx:cs-with-detail result detail))))))))

(defun cx:fb-run-one (entity segment offset expected-style)
  (cx:dp2-run-one entity segment offset expected-style))

(princ)
