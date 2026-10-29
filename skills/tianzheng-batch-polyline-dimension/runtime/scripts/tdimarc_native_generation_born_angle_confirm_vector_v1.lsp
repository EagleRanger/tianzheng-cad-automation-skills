(vl-load-com)

;; Generic promotion route that changes only the TDIMARC dimension-type cursor.
;; It never writes DimStyle. A candidate is eligible only when Tianzheng
;; creates it directly with the requested native style.

(defun cx:bacv1-unit-xy (from to / dx dy length)
  (setq dx (- (car to) (car from))
        dy (- (cadr to) (cadr from))
        length (sqrt (+ (* dx dx) (* dy dy))))
  (if (> length 1e-12)
    (list (/ dx length) (/ dy length) 0.0)
    nil))

(defun cx:bacv1-confirm-point (geometry text-height scale / midpoint center unit)
  (if (or (not (listp geometry)) (/= (car geometry) "PASS"))
    nil
    (progn
      (setq midpoint (nth 3 geometry)
            center (nth 5 geometry)
            unit (cx:bacv1-unit-xy center midpoint))
      (if unit
        (list (+ (car midpoint) (* scale text-height (car unit)))
              (+ (cadr midpoint) (* scale text-height (cadr unit)))
              0.0)
        nil))))

(defun cx:bacv1-style (handle / entity)
  (setq entity (handent handle))
  (if entity
    (cx:fb-safe-property (vlax-ename->vla-object entity) 'DimStyle)
    ""))

(defun cx:bacv1-delete-handles (handles / handle entity)
  (foreach handle handles
    (setq entity (handent handle))
    (if entity
      (cx:gcp1-delete-object (vlax-ename->vla-object entity)))))

(defun cx:bacv1-attempt
  (entity segment expected-style pick point audit-offset scale
    / geometry text-height confirm-wcs stage helper shift back helper-entity
      shifted-pick shifted-confirm shifted-point before call-result after added
      born-style translate-result translated placement valid detail)
  (setq geometry (cx:ups-arc-geometry entity segment)
        text-height (cx:ups-text-height-from-effective audit-offset)
        confirm-wcs (cx:bacv1-confirm-point geometry text-height scale)
        stage (cx:gcp1-shifted-copy entity segment)
        helper (if stage (car stage) nil)
        shift (if stage (cadr stage) nil)
        back (if stage (caddr stage) nil)
        helper-entity (if helper (vlax-vla-object->ename helper) nil)
        shifted-pick (cx:gcp1-shift-wcs pick shift)
        shifted-confirm (cx:gcp1-shift-wcs confirm-wcs shift)
        shifted-point (cx:gcp1-shift-ucs point shift)
        before (cx:fb-native-handles)
        call-result nil)
  (if (and helper-entity shifted-pick shifted-confirm shifted-point)
    (progn
      (cx:gcp1-zoom-segment helper-entity segment)
      (setq call-result
        (cx:gm1-staged-tdimarc shifted-pick shifted-confirm shifted-point))))
  (cx:gcp1-delete-object helper)
  (setq after (cx:fb-native-handles)
        added (cx:fb-difference after before)
        born-style (if (= (length added) 1) (cx:bacv1-style (car added)) "")
        valid (and (= (getvar "CMDNAMES") "")
                   (not (vl-catch-all-error-p call-result))
                   (= (length added) 1)
                   (= born-style expected-style))
        translate-result
          (if valid
            (cx:gcp1-translate-handle (car added) back)
            (list "FAIL" "BORN_NATIVE_STYLE_NOT_INCLUDED_ANGLE"))
        translated (cx:gcp1-translate-result-ok-p translate-result)
        placement
          (if translated
            (cx:pg-audit entity "ARC" segment (car added) audit-offset)
            (list 0 "BORN_ANGLE_TRANSLATION_NOT_ACCEPTED" 0.0 audit-offset 1e99 0))
        valid (and valid translated (cx:pg-audit-normal-p placement))
        detail
          (strcat "BORN_ANGLE_CONFIRM_VECTOR_V1{scale_h=" (rtos scale 2 3)
            ",born_style=" born-style
            ",style_write=0,semantic="
            (if (= born-style expected-style) "NATIVE_INCLUDED_ANGLE" "REJECT_NATIVE_OTHER")
            ",translation=" (if translated "PASS" "FAIL")
            "," (cx:asv4-placement-vector placement) "}"))
  (if (not valid) (cx:bacv1-delete-handles added))
  (list call-result (if valid added '()) placement valid detail))

(defun cx:gcp1-create-candidate
  (entity segment expected-style pick point audit-offset
    / scales scale attempt accepted last-result trace)
  ;; Runtime dimensionless H-scaled radial cursor vectors. The exact midpoint
  ;; is excluded because the host selected arc-length there.
  (setq scales '(1.0 -1.0 2.0 -2.0)
        accepted nil last-result nil trace "")
  (while (and scales (null accepted))
    (setq scale (car scales)
          scales (cdr scales)
          attempt (cx:bacv1-attempt
                    entity segment expected-style pick point audit-offset scale)
          last-result attempt
          trace (strcat trace (if (= trace "") "" "|") (nth 4 attempt)))
    (if (nth 3 attempt) (setq accepted attempt)))
  (setq cx:*sp2-last-trace*
    (strcat cx:*sp2-last-trace* "|BORN_ANGLE_PROMOTION_VECTOR{" trace "}"))
  (if accepted
    (list (nth 0 accepted) (nth 1 accepted) (nth 2 accepted) (nth 3 accepted))
    (if last-result
      (list (nth 0 last-result) '() (nth 2 last-result) nil)
      (list nil '() (list 0 "NO_BORN_ANGLE_VECTOR_ATTEMPT" 0.0 audit-offset 1e99 0) nil))))

(princ)
