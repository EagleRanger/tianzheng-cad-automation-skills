(vl-load-com)

;; Generic native-angle promotion V2.
;; A born-angle candidate is translated while its temporary source copy is
;; still alive. The helper is deleted only after the transactional all-grip
;; TransformBy has completed; final acceptance is audited after helper cleanup.

(defun cx:bacv2-unit-xy (from to / dx dy length)
  (setq dx (- (car to) (car from))
        dy (- (cadr to) (cadr from))
        length (sqrt (+ (* dx dx) (* dy dy))))
  (if (> length 1e-12)
    (list (/ dx length) (/ dy length) 0.0)
    nil))

(defun cx:bacv2-confirm-point (geometry text-height scale / midpoint center unit)
  (if (or (not (listp geometry)) (/= (car geometry) "PASS"))
    nil
    (progn
      (setq midpoint (nth 3 geometry)
            center (nth 5 geometry)
            unit (cx:bacv2-unit-xy center midpoint))
      (if unit
        (list (+ (car midpoint) (* scale text-height (car unit)))
              (+ (cadr midpoint) (* scale text-height (cadr unit)))
              0.0)
        nil))))

(defun cx:bacv2-style (handle / entity)
  (setq entity (handent handle))
  (if entity
    (cx:fb-safe-property (vlax-ename->vla-object entity) 'DimStyle)
    ""))

(defun cx:bacv2-delete-handles (handles / handle entity)
  (foreach handle handles
    (setq entity (handent handle))
    (if entity
      (cx:gcp1-delete-object (vlax-ename->vla-object entity)))))

(defun cx:bacv2-translate-detail (result)
  (if (cx:gcp1-translate-result-ok-p result)
    (strcat "PASS:" (nth 1 result)
      ":max_grip_vector_error=" (rtos (nth 5 result) 2 12)
      ":grips=" (itoa (fix (nth 6 result))))
    (strcat "FAIL:"
      (if (and (listp result) (> (length result) 1))
        (vl-princ-to-string (nth 1 result))
        "INVALID_RESULT"))))

(defun cx:bacv2-attempt
  (entity segment expected-style pick point audit-offset scale
    / geometry text-height confirm-wcs stage helper shift back helper-entity
      shifted-pick shifted-confirm shifted-point before call-result after added
      born-style pretranslate-valid translate-result translated helper-deleted
      survivor placement valid detail)
  (setq geometry (cx:ups-arc-geometry entity segment)
        text-height (cx:ups-text-height-from-effective audit-offset)
        confirm-wcs (cx:bacv2-confirm-point geometry text-height scale)
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
  ;; Inspect and translate before helper cleanup. This ordering is the only
  ;; material V2 delta and is guarded by the post-cleanup placement audit.
  (setq after (cx:fb-native-handles)
        added (cx:fb-difference after before)
        born-style (if (= (length added) 1) (cx:bacv2-style (car added)) "")
        pretranslate-valid
          (and (= (getvar "CMDNAMES") "")
               (not (vl-catch-all-error-p call-result))
               (= (length added) 1)
               (= born-style expected-style))
        translate-result
          (if pretranslate-valid
            (cx:gcp1-translate-handle (car added) back)
            (list "FAIL" "BORN_NATIVE_STYLE_NOT_INCLUDED_ANGLE"))
        translated (cx:gcp1-translate-result-ok-p translate-result))
  (cx:gcp1-delete-object helper)
  (setq helper-deleted T
        survivor (if (= (length added) 1) (handent (car added)) nil)
        placement
          (if (and translated survivor)
            (cx:pg-audit entity "ARC" segment (car added) audit-offset)
            (list 0 "BORN_ANGLE_POST_HELPER_CLEANUP_NOT_ACCEPTED"
              0.0 audit-offset 1e99 0))
        valid (and pretranslate-valid translated survivor
                   (cx:pg-audit-normal-p placement))
        detail
          (strcat "BORN_ANGLE_CONFIRM_VECTOR_V2{scale_h=" (rtos scale 2 3)
            ",born_style=" born-style
            ",style_write=0,semantic="
            (if (= born-style expected-style)
              "NATIVE_INCLUDED_ANGLE" "REJECT_NATIVE_OTHER")
            ",translation_while_helper_alive="
            (cx:bacv2-translate-detail translate-result)
            ",helper_deleted=" (if helper-deleted "YES" "NO")
            ",post_cleanup_survivor=" (if survivor "YES" "NO")
            "," (cx:asv4-placement-vector placement) "}"))
  (if (not valid) (cx:bacv2-delete-handles added))
  (list call-result (if valid added '()) placement valid detail))

(defun cx:gcp1-create-candidate
  (entity segment expected-style pick point audit-offset
    / scales scale attempt accepted last-result trace)
  (setq scales '(1.0 -1.0 2.0 -2.0)
        accepted nil last-result nil trace "")
  (while (and scales (null accepted))
    (setq scale (car scales)
          scales (cdr scales)
          attempt (cx:bacv2-attempt
                    entity segment expected-style pick point audit-offset scale)
          last-result attempt
          trace (strcat trace (if (= trace "") "" "|") (nth 4 attempt)))
    (if (nth 3 attempt) (setq accepted attempt)))
  (setq cx:*sp2-last-trace*
    (strcat cx:*sp2-last-trace* "|BORN_ANGLE_PROMOTION_VECTOR_V2{" trace "}"))
  (if accepted
    (list (nth 0 accepted) (nth 1 accepted) (nth 2 accepted) (nth 3 accepted))
    (if last-result
      (list (nth 0 last-result) '() (nth 2 last-result) nil)
      (list nil '()
        (list 0 "NO_BORN_ANGLE_VECTOR_V2_ATTEMPT" 0.0 audit-offset 1e99 0)
        nil))))

(princ)
