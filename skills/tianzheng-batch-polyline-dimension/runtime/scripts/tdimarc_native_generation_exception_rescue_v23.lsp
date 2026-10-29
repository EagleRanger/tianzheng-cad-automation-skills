(vl-load-com)
;; V23 corrects only the command-context implementation of the V22 direct
;; source fraction stage.  It uses the already field-proven direct staged
;; TDIMARC prompt sequence instead of the early COMMAND-S helper.

(defun cx:er23-attempt-detail (fraction added placement accepted)
  (strcat "fraction=" (rtos fraction 2 2)
    ",added=" (cx:fb-join added)
    ",accepted=" (if accepted "YES" "NO")
    ",rank=" (itoa (cx:cs-safe-audit-rank placement))))

(defun cx:er22-direct-source-fraction-rescue
  (entity segment expected-style audit-offset
    / geometry text-height effective-offset fractions fraction points pick side
      before call-result after added placement accepted attempts result detail)
  (setq geometry (cx:ups-arc-geometry entity segment)
        text-height (cx:ups-text-height-from-effective audit-offset)
        effective-offset
          (if (and (listp geometry) (= (car geometry) "PASS") (> text-height 1e-9))
            (cx:ups-outer-offset (nth 1 geometry) text-height)
            audit-offset)
        fractions '(0.35 0.65 0.20 0.80 0.50)
        attempts '()
        result (list nil '()
          (list 0 "DIRECT_SOURCE_STAGED_FRACTION_NO_RESULT" 0.0 audit-offset 1e99 0)
          nil ""))
  (while (and fractions (not (nth 3 result)))
    (setq fraction (car fractions) fractions (cdr fractions)
          points (cx:fb-segment-points entity segment fraction effective-offset))
    (if points
      (progn
        (setq pick (car points) side (cadr points)
              before (cx:fb-native-handles)
              call-result (cx:sp2-staged-tdimarc pick side)
              after (cx:fb-native-handles)
              added (cx:fb-difference after before)
              placement
                (if (and (= (getvar "CMDNAMES") "")
                         (cx:fb-created-object-valid-p added expected-style))
                  (cx:pg-audit entity "ARC" segment (car added) audit-offset)
                  (list 0 "DIRECT_SOURCE_STAGED_FRACTION_INVALID_CANDIDATE"
                    0.0 audit-offset 1e99 0))
              accepted (and (= (length added) 1) (cx:pg-audit-normal-p placement))
              attempts (append attempts
                (list (cx:er23-attempt-detail fraction added placement accepted))))
        (if accepted
          (setq result (list call-result added placement T ""))
          (progn
            (if added (cx:fb-delete-handles added))
            (setq result (list call-result '() placement nil "")))))))
  (setq detail
    (strcat "EXCEPTION_DIRECT_SOURCE_STAGED_FRACTION_V23{"
      "route=ORIGINAL_SOURCE_ARC_DIRECT_STAGED"
      ",trigger=ORDINARY_RANK_BELOW_2"
      ",accepted=" (if (nth 3 result) "YES" "NO")
      ",attempts=" (cx:fb-join attempts) "}")
    cx:*sp2-last-trace* (strcat cx:*sp2-last-trace* "|" detail))
  (list (car result) (cadr result) (nth 2 result) (nth 3 result) detail))

(princ)
