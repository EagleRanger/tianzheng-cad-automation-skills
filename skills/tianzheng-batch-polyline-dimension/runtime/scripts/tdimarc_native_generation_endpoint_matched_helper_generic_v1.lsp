(vl-load-com)

;; Generic endpoint-matched helper candidate.
;; No drawing handle, segment index, coordinate, bbox, or target-count literal
;; is used. The helper arc is selected solely by runtime endpoint error.

(defun cx:geh1-delete (object)
  (if (and object (not (vlax-erased-p object)))
    (vl-catch-all-apply 'vla-Delete (list object))))

(defun cx:geh1-point-list (value)
  (cond
    ((listp value) value)
    ((= (type value) 'VARIANT) (vlax-safearray->list (vlax-variant-value value)))
    ((= (type value) 'SAFEARRAY) (vlax-safearray->list value))
    (T nil)))

(defun cx:geh1-distance-xy (first second)
  (if (and first second)
    (sqrt (+ (expt (- (car first) (car second)) 2.0)
             (expt (- (cadr first) (cadr second)) 2.0)))
    1e99))

(defun cx:geh1-endpoint-error (object start end / object-start object-end direct reverse)
  (setq object-start (cx:geh1-point-list (vlax-get object 'StartPoint))
        object-end (cx:geh1-point-list (vlax-get object 'EndPoint))
        direct (max (cx:geh1-distance-xy object-start start)
                    (cx:geh1-distance-xy object-end end))
        reverse (max (cx:geh1-distance-xy object-start end)
                     (cx:geh1-distance-xy object-end start)))
  (min direct reverse))

(defun cx:geh1-helper-arc (entity segment / source start end copy raw parts best best-error error object-name)
  (setq source (vlax-ename->vla-object entity)
        start (vlax-curve-getPointAtParam entity segment)
        end (vlax-curve-getPointAtParam entity (1+ segment))
        copy (vl-catch-all-apply 'vla-Copy (list source))
        best nil best-error 1e99 cx:*geh1-last-helper-detail* "COPY_FAILED")
  (if (not (vl-catch-all-error-p copy))
    (progn
      (setq raw (vl-catch-all-apply 'vla-Explode (list copy)))
      (cx:geh1-delete copy)
      (if (not (vl-catch-all-error-p raw))
        (progn
          (setq parts (vlax-safearray->list (vlax-variant-value raw)))
          (foreach object parts
            (setq object-name (strcase (vla-get-ObjectName object)))
            (if (= object-name "ACDBARC")
              (progn
                (setq error (cx:geh1-endpoint-error object start end))
                (if (< error best-error)
                  (progn (if best (cx:geh1-delete best))
                         (setq best object best-error error))
                  (cx:geh1-delete object)))
              (cx:geh1-delete object)))
          (if (<= best-error 0.000001)
            (setq cx:*geh1-last-helper-detail*
              (strcat "MATCHED{endpoint_error=" (rtos best-error 2 12) "}"))
            (progn
              (if best (cx:geh1-delete best))
              (setq best nil
                    cx:*geh1-last-helper-detail*
                      (strcat "NO_EXACT_MATCH{best_error=" (rtos best-error 2 12) "}")))))
        (setq cx:*geh1-last-helper-detail* "EXPLODE_FAILED"))))
  best)

(defun cx:geh1-create-candidate
  (entity segment expected-style pick point audit-offset
    / geometry text-height target-band confirm-wcs before source helper call call-result
      after added valid move-result placement)
  (setq geometry (cx:ups-arc-geometry entity segment)
        text-height (cx:ups-text-height-from-effective audit-offset)
        target-band (* text-height cx:*ups-dimension-band-h*)
        confirm-wcs (if (and (listp geometry) (= (car geometry) "PASS")) (nth 3 geometry) nil)
        before (cx:fb-native-handles)
        source (vlax-ename->vla-object entity)
        helper (cx:geh1-helper-arc entity segment)
        call-result nil)
  (if (and helper confirm-wcs point)
    (progn
      (vla-put-Visible source :vlax-false)
      (setq call (vl-catch-all-apply 'cx:gm1-staged-tdimarc
                   (list confirm-wcs confirm-wcs point)))
      (vla-put-Visible source :vlax-true)
      (cx:geh1-delete helper)
      (setq call-result (if (vl-catch-all-error-p call) nil call)))
    (progn
      (vla-put-Visible source :vlax-true)
      (cx:geh1-delete helper)))
  (setq after (cx:fb-native-handles)
        added (cx:fb-difference after before)
        valid (and (= (getvar "CMDNAMES") "")
                   (cx:fb-created-object-valid-p added expected-style))
        move-result (if valid
          (cx:gm1-move-grip0 entity segment (car added) target-band)
          (list "FAIL" "NO_VALID_GENERIC_ENDPOINT_HELPER_CANDIDATE"))
        cx:*sp2-last-trace*
          (strcat cx:*sp2-last-trace*
            "|GENERIC_ENDPOINT_MATCHED_HELPER_V1{" cx:*geh1-last-helper-detail* "}|"
            (cx:gm1-move-detail move-result))
        placement (if (and valid (cx:gm1-move-result-ok-p move-result))
          (cx:pg-audit entity "ARC" segment (car added) audit-offset)
          (list 0 (cx:gm1-move-detail move-result) 0.0 audit-offset 1e99 0)))
  (list call-result added placement valid))

(princ)
