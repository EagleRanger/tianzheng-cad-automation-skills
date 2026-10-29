(vl-load-com)

;; Observer-only candidate-chain diagnostic vector V1.
;; The bundle builder renames the three active business functions and this
;; module restores their public names as transparent wrappers.  It writes
;; evidence only: no command, retry, save, style write, coordinate change or
;; candidate decision is introduced here.

(defun cx:cdv1-clean (value / text)
  (setq text (if value (vl-princ-to-string value) ""))
  (vl-string-translate (strcat (chr 9) (chr 10) (chr 13)) "   " text))

(defun cx:cdv1-write (stage route fraction detail / stream line)
  (setq line
    (strcat (cx:cdv1-clean stage) (chr 9)
            (cx:cdv1-clean route) (chr 9)
            (if (numberp fraction) (rtos fraction 2 6) "") (chr 9)
            (cx:cdv1-clean detail)))
  (setq stream (vl-catch-all-apply 'open (list cx:*cdv1-trace-path* "a")))
  (if (not (vl-catch-all-error-p stream))
    (progn
      (vl-catch-all-apply 'write-line (list line stream))
      (vl-catch-all-apply 'close (list stream)))))

(defun cx:cdv1-result-handles (result)
  (if (and (listp result) (> (length result) 1) (listp (nth 1 result)))
    (nth 1 result) '()))

(defun cx:cdv1-result-placement (result)
  (if (and (listp result) (> (length result) 2) (listp (nth 2 result)))
    (nth 2 result) nil))

(defun cx:cdv1-result-valid (result)
  (and (listp result) (> (length result) 3) (nth 3 result)))

(defun cx:cdv1-fraction (entity segment pick / raw)
  (setq raw (vl-catch-all-apply 'vlax-curve-getParamAtPoint (list entity pick)))
  (if (or (vl-catch-all-error-p raw) (not (numberp raw))) nil (- raw segment)))

(defun cx:cdv1-result-detail
  (entity segment expected-style result / handles handle placement audit)
  (setq handles (cx:cdv1-result-handles result)
        handle (if (= (length handles) 1) (car handles) "")
        placement (cx:cdv1-result-placement result)
        audit (if (/= handle "")
                (cx:asv4-semantic-audit entity segment handle 0.011)
                (list "FAIL" "" nil nil nil)))
  (strcat
    "handles=" (cx:fb-join handles)
    ",valid=" (if (cx:cdv1-result-valid result) "YES" "NO")
    ",born_style=" (if (/= handle "") (cx:asv4-style handle) "")
    "," (cx:asv4-placement-vector placement)
    ",semantic=" (car audit)
    "," (cx:asv4-semantic-vector audit)))

(defun cx:geh1-create-candidate
  (entity segment expected-style pick point audit-offset / fraction result)
  (setq fraction (cx:cdv1-fraction entity segment pick))
  (cx:cdv1-write "ENTER" "ENDPOINT_HELPER" fraction "delegating_to_unchanged_business_function")
  (setq result
    (cx:cdv1-base-endpoint-candidate
      entity segment expected-style pick point audit-offset))
  (cx:cdv1-write "RETURN" "ENDPOINT_HELPER" fraction
    (cx:cdv1-result-detail entity segment expected-style result))
  result)

(defun cx:gcp1-create-candidate
  (entity segment expected-style pick point audit-offset / fraction result)
  (setq fraction (cx:cdv1-fraction entity segment pick))
  (cx:cdv1-write "ENTER" "COMPLETE_POLYLINE_PROMOTION" fraction "delegating_to_unchanged_business_function")
  (setq result
    (cx:cdv1-base-promotion-candidate
      entity segment expected-style pick point audit-offset))
  (cx:cdv1-write "RETURN" "COMPLETE_POLYLINE_PROMOTION" fraction
    (cx:cdv1-result-detail entity segment expected-style result))
  result)

(defun cx:ha1-create-candidate
  (entity segment expected-style ignored-pick point audit-offset / result)
  (setq cx:*cdv1-last-entity* entity
        cx:*cdv1-last-segment* segment
        cx:*cdv1-last-expected-style* expected-style
        cx:*cdv1-last-result* nil)
  (cx:cdv1-write "ENTER" "ANGLE_VECTOR_V4" nil "delegating_to_unchanged_business_function")
  (setq result
    (cx:cdv1-base-angle-vector
      entity segment expected-style ignored-pick point audit-offset)
        cx:*cdv1-last-result* result)
  (cx:cdv1-write "RETURN" "ANGLE_VECTOR_V4" nil
    (cx:cdv1-result-detail entity segment expected-style result))
  result)

(defun cx:cdv1-post-batch-audit (/ result handles handle audit detail)
  (setq result cx:*cdv1-last-result*
        handles (cx:cdv1-result-handles result)
        handle (if (= (length handles) 1) (car handles) ""))
  (if (and cx:*cdv1-last-entity* (numberp cx:*cdv1-last-segment*) (/= handle ""))
    (setq audit
      (cx:asv4-semantic-audit
        cx:*cdv1-last-entity* cx:*cdv1-last-segment* handle 0.011)
          detail
      (strcat "handle=" handle
        ",born_style=" (cx:asv4-style handle)
        ",semantic=" (car audit)
        "," (cx:asv4-semantic-vector audit)))
    (setq detail "handle=,born_style=,semantic=FAIL,reason=ANGLE_VECTOR_DID_NOT_RETURN_ONE_HANDLE"))
  (cx:cdv1-write "POST_BATCH" "TEXTCONTENT_HARD_GATE" nil detail)
  (if (= (car audit) "PASS") "PASS" "FAIL"))

(princ)
