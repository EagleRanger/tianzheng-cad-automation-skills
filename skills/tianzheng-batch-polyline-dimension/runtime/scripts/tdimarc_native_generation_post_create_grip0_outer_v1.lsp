(vl-load-com)

;; V40: preserve run162's endpoint-associated five-stage creation grammar,
;; then move only grip 0 to the user-positive E6 outer dimension band.
;; The native mover owns the transaction and commits only after five-grip,
;; endpoint, response-direction and target-band checks all pass.

(defun cx:gm1-wcs-to-active-ucs-plane (point / converted)
  (if point
    (progn
      (setq converted (trans point 0 1))
      (list (car converted) (cadr converted) 0.0))
    nil))

(defun cx:gm1-active-ucs-plane (point)
  (if point (list (car point) (cadr point) 0.0) nil))

(defun cx:gm1-staged-tdimarc
  (pick-wcs confirm-wcs dimension-point-ucs
    / pick-ucs confirm-ucs final-ucs)
  (setq cx:*sp2-last-trace* ""
        pick-ucs (cx:gm1-wcs-to-active-ucs-plane pick-wcs)
        confirm-ucs (cx:gm1-wcs-to-active-ucs-plane confirm-wcs)
        final-ucs (cx:gm1-active-ucs-plane dimension-point-ucs))
  (if (and pick-ucs confirm-ucs final-ucs)
    (progn
      (cx:sp2-send-direct "START" "TDIMARC")
      (cx:sp2-send-direct "SELECT_OBJECT_UCS_PLANE_Z0" pick-ucs)
      (cx:sp2-send-direct "CONFIRM_ARC_UCS_PLANE_Z0" confirm-ucs)
      (cx:sp2-send-direct "FINAL_DIMENSION_POSITION_UCS_PLANE_Z0" final-ucs)
      (if (/= (getvar "CMDNAMES") "")
        (cx:sp2-send-direct "FINISH" ""))
      T)
    nil))

(defun cx:gm1-move-result-ok-p (result)
  (and (listp result) (>= (length result) 2) (= (car result) "PASS")))

(defun cx:gm1-move-detail (result)
  (if (cx:gm1-move-result-ok-p result)
    (strcat
      "POST_CREATE_GRIP0_OUTER_MOVE{status=PASS,mode=" (nth 1 result)
      ",requested=" (rtos (nth 8 result) 2 9)
      ",actual=" (rtos (nth 9 result) 2 9)
      ",direction_cosine=" (rtos (nth 10 result) 2 9)
      ",endpoint_before=" (rtos (nth 11 result) 2 12)
      ",endpoint_after=" (rtos (nth 12 result) 2 12)
      ",endpoint_drift=" (rtos (nth 13 result) 2 12)
      ",actual_band=" (rtos (nth 14 result) 2 9)
      ",target_band=" (rtos (nth 15 result) 2 9)
      ",band_error=" (rtos (nth 16 result) 2 12)
      ",grips=" (itoa (fix (nth 17 result))) "}")
    (strcat "POST_CREATE_GRIP0_OUTER_MOVE{status=FAIL,detail="
      (if (and (listp result) (> (length result) 1))
        (nth 1 result) "INVALID_RESULT") "}")))

(defun cx:gm1-move-grip0
  (entity segment handle target-band / source-handle result)
  (setq source-handle (vla-get-Handle (vlax-ename->vla-object entity))
        result
          (vl-catch-all-apply
            'CXNATIVEPLACEMENTMOVEGRIP0V1
            (list source-handle segment handle target-band)))
  (if (vl-catch-all-error-p result)
    (list "FAIL" (vl-catch-all-error-message result))
    result))

(defun cx:sp2-create-candidate
  (entity segment expected-style pick point audit-offset
    / geometry text-height target-band confirm-wcs before call-result after
      added valid move-result placement)
  (setq geometry (cx:ups-arc-geometry entity segment)
        text-height (cx:ups-text-height-from-effective audit-offset)
        target-band (* text-height cx:*ups-dimension-band-h*)
        confirm-wcs
          (if (and (listp geometry) (= (car geometry) "PASS"))
            (nth 3 geometry) nil)
        before (cx:fb-native-handles)
        call-result (cx:gm1-staged-tdimarc pick confirm-wcs point)
        after (cx:fb-native-handles)
        added (cx:fb-difference after before)
        valid
          (and (= (getvar "CMDNAMES") "")
               (cx:fb-created-object-valid-p added expected-style))
        move-result
          (if valid
            (cx:gm1-move-grip0 entity segment (car added) target-band)
            (list "FAIL" "NO_VALID_FIVE_STAGE_NATIVE_CANDIDATE"))
        cx:*sp2-last-trace*
          (strcat cx:*sp2-last-trace* "|" (cx:gm1-move-detail move-result))
        placement
          (if (and valid (cx:gm1-move-result-ok-p move-result))
            (cx:pg-audit entity "ARC" segment (car added) audit-offset)
            (list 0 (cx:gm1-move-detail move-result)
              0.0 audit-offset 1e99 0)))
  (list call-result added placement valid))

(defun cx:cs-create-candidate
  (entity segment expected-style pick point audit-offset)
  (cx:sp2-create-candidate
    entity segment expected-style pick point audit-offset))

(princ)
