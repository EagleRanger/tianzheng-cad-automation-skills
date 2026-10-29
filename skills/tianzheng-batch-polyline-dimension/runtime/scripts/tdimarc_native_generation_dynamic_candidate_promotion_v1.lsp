(vl-load-com)

;; Generic native candidate promotion and cleanup.
;;
;; The algorithm has no drawing-specific handle, coordinate, segment, count,
;; or known-failure key.  It operates only on the runtime source entity,
;; runtime segment index, candidate handle set, expected semantic style,
;; native grip TransformBy evidence, and the existing source-mapping audit.

(defun cx:gcp1-delete-object (object)
  (if (and object (not (vlax-erased-p object)))
    (vl-catch-all-apply 'vla-Delete (list object))))

(defun cx:gcp1-shifted-copy
  (entity segment / midpoint shift back source helper moved)
  (setq midpoint (vlax-curve-getPointAtParam entity (+ segment 0.5))
        shift (list (- (car midpoint)) (- (cadr midpoint)) 0.0)
        back (list (car midpoint) (cadr midpoint) 0.0)
        source (vlax-ename->vla-object entity)
        helper (vl-catch-all-apply 'vla-Copy (list source)))
  (if (vl-catch-all-error-p helper)
    nil
    (progn
      (setq moved
        (vl-catch-all-apply 'vla-Move
          (list helper (vlax-3d-point '(0.0 0.0 0.0))
                       (vlax-3d-point shift))))
      (if (vl-catch-all-error-p moved)
        (progn (cx:gcp1-delete-object helper) nil)
        (list helper shift back)))))

(defun cx:gcp1-shift-wcs (point shift)
  (if (and point shift) (mapcar '+ point shift) nil))

(defun cx:gcp1-shift-ucs (point-ucs shift / point-wcs)
  (if (and point-ucs shift)
    (progn
      (setq point-wcs (trans point-ucs 1 0))
      (trans (mapcar '+ point-wcs shift) 0 1))
    nil))

(defun cx:gcp1-zoom-segment (entity segment / p0 pm p1 xs ys margin)
  (setq p0 (vlax-curve-getPointAtParam entity segment)
        pm (vlax-curve-getPointAtParam entity (+ segment 0.5))
        p1 (vlax-curve-getPointAtParam entity (1+ segment))
        xs (list (car p0) (car pm) (car p1))
        ys (list (cadr p0) (cadr pm) (cadr p1))
        margin 0.50)
  (vl-catch-all-apply 'command-s
    (list "_.ZOOM" "_W"
      (trans (list (- (apply 'min xs) margin)
                   (- (apply 'min ys) margin) 0.0) 0 1)
      (trans (list (+ (apply 'max xs) margin)
                   (+ (apply 'max ys) margin) 0.0) 0 1))))

(defun cx:gcp1-translate-result-ok-p (result)
  (and (listp result) (>= (length result) 2) (= (car result) "PASS")))

(defun cx:gcp1-translate-handle (handle displacement / result)
  (setq result
    (vl-catch-all-apply
      'CXNATIVEPLACEMENTTRANSLATEV2
      (list handle (car displacement) (cadr displacement) (caddr displacement))))
  (if (vl-catch-all-error-p result)
    (list "FAIL" (vl-catch-all-error-message result))
    result))

(defun cx:gcp1-translate-detail (result)
  (if (cx:gcp1-translate-result-ok-p result)
    (strcat "NATIVE_TRANSFORMBY{status=PASS,mode=" (nth 1 result)
      ",dx=" (rtos (nth 2 result) 2 9)
      ",dy=" (rtos (nth 3 result) 2 9)
      ",dz=" (rtos (nth 4 result) 2 9)
      ",max_grip_vector_error=" (rtos (nth 5 result) 2 12)
      ",grips=" (itoa (fix (nth 6 result))) "}")
    (strcat "NATIVE_TRANSFORMBY{status=FAIL,detail="
      (if (and (listp result) (> (length result) 1))
        (nth 1 result) "INVALID_RESULT") "}")))

(defun cx:gcp1-style-result-ok-p (result)
  (and (listp result) (>= (length result) 4) (= (car result) "PASS")))

(defun cx:gcp1-normalize-style
  (handle expected-style / entity object before writable put-result update-result after)
  (setq entity (handent handle))
  (if (null entity)
    (list "FAIL" "HANDLE_NOT_FOUND" "" "")
    (progn
      (setq object (vl-catch-all-apply 'vlax-ename->vla-object (list entity)))
      (if (or (null object) (vl-catch-all-error-p object))
        (list "FAIL" "OBJECT_OPEN_FAILED" "" "")
        (progn
          (setq before (cx:fb-safe-property object 'DimStyle))
          (cond
            ((= before expected-style)
              (list "PASS" "ALREADY_EXPECTED" before before))
            (t
              (setq writable
                (vl-catch-all-apply 'vlax-property-available-p
                  (list object 'DimStyle T)))
              (if (or (vl-catch-all-error-p writable) (not writable))
                (list "FAIL" "DIMSTYLE_NOT_WRITABLE" before before)
                (progn
                  (setq put-result
                    (vl-catch-all-apply 'vlax-put-property
                      (list object 'DimStyle expected-style)))
                  (if (vl-catch-all-error-p put-result)
                    (list "FAIL" "DIMSTYLE_WRITE_FAILED" before before)
                    (progn
                      (setq update-result
                        (vl-catch-all-apply 'vla-Update (list object))
                            after (cx:fb-safe-property object 'DimStyle))
                      (if (and (not (vl-catch-all-error-p update-result))
                               (= after expected-style))
                        (list "PASS" "NORMALIZED" before after)
                        (list "FAIL" "DIMSTYLE_READBACK_MISMATCH" before after)))))))))))))

(defun cx:gcp1-style-detail (result)
  (strcat "DIMSTYLE_NORMALIZATION{status="
    (if (cx:gcp1-style-result-ok-p result) "PASS" "FAIL")
    ",detail=" (if (and (listp result) (> (length result) 1)) (nth 1 result) "INVALID_RESULT")
    ",before=" (if (and (listp result) (> (length result) 2)) (nth 2 result) "")
    ",after=" (if (and (listp result) (> (length result) 3)) (nth 3 result) "") "}"))

(defun cx:gcp1-poststyle-audit-detail (placement)
  (strcat "POSTSTYLE_AUDIT{" (cx:pg-audit-diagnostic placement) "}"))

;; This generic direct-candidate adapter is reached only when the ordinary
;; route did not already produce an acceptable rank2 survivor.  It uses the
;; runtime complete source polyline as a temporary helper, translates the new
;; native object back transactionally, normalizes its expected style, and
;; re-audits the original runtime source segment before promotion.
(defun cx:ha1-create-candidate
  (entity segment expected-style pick point audit-offset
    / geometry text-height target-band confirm-wcs stage helper shift back
      helper-entity shifted-pick shifted-confirm shifted-point before call-result
      after added valid translate-result translated style-result styled
      poststyle-placement move-result placement source-handle segment-key)
  (setq geometry (cx:ups-arc-geometry entity segment)
        text-height (cx:ups-text-height-from-effective audit-offset)
        target-band (* text-height cx:*ups-dimension-band-h*)
        confirm-wcs
          (if (and (listp geometry) (= (car geometry) "PASS"))
            (nth 3 geometry) nil)
        source-handle (strcase (vla-get-Handle (vlax-ename->vla-object entity)))
        segment-key (strcat source-handle "/ARC/" (itoa segment))
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
        valid
          (and (= (getvar "CMDNAMES") "")
               (not (vl-catch-all-error-p call-result))
               (= (length added) 1))
        translate-result
          (if valid
            (cx:gcp1-translate-handle (car added) back)
            (list "FAIL" "NO_SINGLE_VALID_NATIVE_CANDIDATE"))
        translated (cx:gcp1-translate-result-ok-p translate-result)
        style-result
          (if translated
            (cx:gcp1-normalize-style (car added) expected-style)
            (list "FAIL" "TRANSLATION_NOT_ACCEPTED" "" ""))
        styled (cx:gcp1-style-result-ok-p style-result)
        poststyle-placement
          (if styled
            (cx:pg-audit entity "ARC" segment (car added) audit-offset)
            (list 0 "STYLE_NORMALIZATION_FAILED" 0.0 audit-offset 1e99 0))
        valid (and valid translated styled))
  (if (and valid (cx:pg-audit-normal-p poststyle-placement))
    (setq move-result nil placement poststyle-placement
          cx:*sp2-last-trace*
            (strcat cx:*sp2-last-trace*
              "|GENERIC_DYNAMIC_CANDIDATE_PROMOTION_V1{target=" segment-key
              ",selection=RUNTIME_COMPLETE_SOURCE_POLYLINE_COPY"
              ",grip_policy=DYNAMIC_AT_LEAST5_SAME_COUNT_ALL_VECTORS"
              ",candidate_back_translation=PASS,source_mutation=0}"
              "|" (cx:gcp1-translate-detail translate-result)
              "|" (cx:gcp1-style-detail style-result)
              "|POSTSTYLE_ALREADY_NORMAL|"
              (cx:gcp1-poststyle-audit-detail poststyle-placement)))
    (progn
      (setq move-result
        (if valid
          (cx:gm1-move-grip0 entity segment (car added) target-band)
          (list "FAIL" "TRANSLATED_OR_STYLE_NORMALIZATION_INVALID"))
            placement
              (if (and valid (cx:gm1-move-result-ok-p move-result))
                (cx:pg-audit entity "ARC" segment (car added) audit-offset)
                (list 0 (cx:gm1-move-detail move-result)
                      0.0 audit-offset 1e99 0))
            cx:*sp2-last-trace*
              (strcat cx:*sp2-last-trace*
                "|GENERIC_DYNAMIC_CANDIDATE_PROMOTION_V1{target=" segment-key
                ",selection=RUNTIME_COMPLETE_SOURCE_POLYLINE_COPY"
                ",grip_policy=DYNAMIC_AT_LEAST5_SAME_COUNT_ALL_VECTORS"
                ",candidate_back_translation="
                (if translated "PASS" "FAIL") ",source_mutation=0}"
                "|" (cx:gcp1-translate-detail translate-result)
                "|" (cx:gcp1-style-detail style-result)
                "|" (cx:gcp1-poststyle-audit-detail poststyle-placement)
                "|" (cx:gm1-move-detail move-result)))))
  (list call-result added placement valid))

;; Harden the unchanged final semantic gate.  A rejected result may name only
;; handles created by that result.  Delete those handles immediately on the
;; rejection branch so they cannot sit outside both all-added and rollback.
;; The accepted branch never calls cleanup and returns the same handle that is
;; subsequently appended to all-added and written to the PASS row/summary.
(defun cx:gcp1-final-accept
  (result expected-style / call-result added handle entity object object-name layer dim-style accepted cleanup-ok)
  (setq call-result (car result) added (cadr result)
        handle "" object-name "" layer "" dim-style "" cleanup-ok T)
  (if (= (length added) 1)
    (progn
      (setq handle (car added) entity (handent handle))
      (if entity
        (progn
          (setq object (vlax-ename->vla-object entity)
                object-name (vla-get-ObjectName object)
                layer (vla-get-Layer object)
                dim-style (cx:fb-safe-property object 'DimStyle))))))
  (setq accepted
    (and (not (vl-catch-all-error-p call-result)) (= (length added) 1)
         (= object-name "TDbDimension2") (= layer "PUB_DIM")
         (= dim-style expected-style) (= (getvar "CMDNAMES") "")
         (or (= (getvar "CMDACTIVE") 0) (= (getvar "CMDACTIVE") 4))))
  (if (and (not accepted) entity (entget entity))
    (progn
      (entdel entity)
      (setq cleanup-ok (null (entget entity)))))
  (list accepted handle object-name layer dim-style
        (if accepted "PROMOTED_TO_SURVIVOR"
          (if cleanup-ok "REJECTED_CANDIDATE_DELETED" "REJECTED_CANDIDATE_DELETE_FAILED"))))

(defun cx:fb-accept-one (result expected-style)
  (cx:gcp1-final-accept result expected-style))

(princ)

