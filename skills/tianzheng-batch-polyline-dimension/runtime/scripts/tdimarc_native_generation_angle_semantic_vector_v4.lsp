(vl-load-com)

;; Versioned native-angle vector contract.  This module intentionally does
;; not redefine cx:gcp1-normalize-style: the semantic read-only gate and the
;; historical candidate-promotion normalizer must have different identities.

(defun cx:asv4-clean-text (value / text)
  (setq text (if value (vl-princ-to-string value) ""))
  (vl-string-translate (strcat (chr 9) (chr 10) (chr 13)) "   " text))

(defun cx:asv4-degree-p (text / upper)
  (setq upper (strcase (if text text "")))
  (or (not (null (vl-string-search "%%D" upper)))
      (not (null (vl-string-search "\\U+00B0" upper)))
      (not (null (vl-string-search (chr 176) upper)))))

(defun cx:asv4-first-number (values / value number found)
  (while (and values (null found))
    (setq value (car values) number (atof value))
    (if (or (/= number 0.0)
            (and (> (strlen value) 0) (= (substr value 1 1) "0")))
      (setq found number))
    (setq values (cdr values)))
  found)

(defun cx:asv4-native-text-content (handle / entity object value)
  (setq entity (handent handle))
  (if (null entity) ""
    (progn
      (setq object (vlax-ename->vla-object entity)
            value (vl-catch-all-apply 'vlax-get-property (list object 'TextContent)))
      (if (vl-catch-all-error-p value) "" (cx:asv4-clean-text value)))))

(defun cx:asv4-semantic-audit
  (entity segment handle tolerance / geometry bulge expected actual degree ok raw)
  (setq geometry (cx:ups-arc-geometry entity segment)
        bulge (if (and (listp geometry) (= (car geometry) "PASS")) (nth 1 geometry) nil)
        expected (if bulge (* (/ 180.0 pi) (* 4.0 (atan (abs bulge)))) nil)
        raw (cx:asv4-native-text-content handle)
        actual (cx:asv4-first-number (if (= raw "") '() (list raw)))
        degree (cx:asv4-degree-p raw)
        ok (and (numberp expected) (numberp actual) degree
                (<= (abs (- actual expected)) tolerance)))
  (list (if ok "PASS" "FAIL") raw actual expected degree))

(defun cx:asv4-empty-creation-text-p (audit)
  (and (listp audit) (> (length audit) 4)
       (= (car audit) "FAIL")
       (= (nth 1 audit) "")
       (null (nth 2 audit))
       (null (nth 4 audit))))

(defun cx:asv4-endpoint-state (audit)
  (cond
    ((= (car audit) "PASS") "PASS")
    ((cx:asv4-empty-creation-text-p audit)
      (if (numberp (nth 3 audit))
        "DEFER_EMPTY_TEXTCONTENT_ANGLE_KNOWN"
        "DEFER_EMPTY_TEXTCONTENT_ANGLE_SETTLES_POST_GENERATION"))
    (T "FAIL")))

(defun cx:asv4-delete-result (result / handles)
  (setq handles (if (and (listp result) (> (length result) 1)) (cadr result) '()))
  (foreach handle handles
    (if (handent handle)
      (cx:gcp1-delete-object (vlax-ename->vla-object (handent handle))))))

(defun cx:asv4-style (handle / entity)
  (setq entity (handent handle))
  (if entity (cx:fb-safe-property (vlax-ename->vla-object entity) 'DimStyle) ""))

(defun cx:asv4-placement-vector (placement / rank grips)
  (setq rank (if placement (cx:cs-safe-audit-rank placement) 0)
        grips (if (and (listp placement) (> (length placement) 5) (numberp (nth 5 placement)))
                (fix (nth 5 placement)) 0))
  (strcat "rank=" (itoa rank) ",grips=" (itoa grips)
    "," (if placement (cx:cs-safe-audit-diagnostic placement) "placement=NONE")))

(defun cx:asv4-semantic-vector (audit)
  (strcat "raw=" (cx:asv4-clean-text (nth 1 audit))
    ",actual=" (if (numberp (nth 2 audit)) (rtos (nth 2 audit) 2 6) "")
    ",expected=" (if (numberp (nth 3 audit)) (rtos (nth 3 audit) 2 6) "")
    ",degree=" (if (nth 4 audit) "YES" "NO")))

(defun cx:ha1-create-candidate
  (entity segment expected-style ignored-pick point audit-offset
    / fractions fraction pick endpoint-result endpoint-placement endpoint-valid
      endpoint-handle endpoint-audit endpoint-state promotion-result
      promotion-placement promotion-valid promotion-handle promotion-audit
      accepted attempt-details last-result)
  (setq fractions '(0.35 0.65 0.20 0.80 0.50)
        attempt-details "" accepted nil last-result nil)
  (while (and fractions (null accepted))
    (setq fraction (car fractions) fractions (cdr fractions)
          pick (vlax-curve-getPointAtParam entity (+ segment fraction))
          endpoint-result (cx:geh1-create-candidate entity segment expected-style pick point audit-offset)
          endpoint-placement (if (and (listp endpoint-result) (> (length endpoint-result) 2)) (nth 2 endpoint-result) nil)
          endpoint-valid (if (and (listp endpoint-result) (> (length endpoint-result) 3)) (nth 3 endpoint-result) nil)
          endpoint-handle (if (and (listp endpoint-result) (= (length (cadr endpoint-result)) 1)) (car (cadr endpoint-result)) "")
          endpoint-audit (if (and endpoint-valid (/= endpoint-handle "") (cx:pg-audit-normal-p endpoint-placement))
                           (cx:asv4-semantic-audit entity segment endpoint-handle 0.011)
                           (list "FAIL" "INVALID_PLACEMENT_OR_STYLE" nil nil nil))
          endpoint-state (cx:asv4-endpoint-state endpoint-audit)
          attempt-details (strcat attempt-details (if (= attempt-details "") "" "|")
            "NATIVE_ANGLE_VECTOR_V4{route=ENDPOINT_HELPER,fraction=" (rtos fraction 2 2)
            ",born_style=" (cx:asv4-style endpoint-handle)
            "," (cx:asv4-placement-vector endpoint-placement)
            ",semantic_state=" endpoint-state
            ",post_generation_textcontent_hard_gate=REQUIRED,"
            (cx:asv4-semantic-vector endpoint-audit) "}"))
    (if (/= endpoint-state "FAIL")
      (setq accepted endpoint-result last-result endpoint-result)
      (progn
        (cx:asv4-delete-result endpoint-result)
        (setq promotion-result (cx:gcp1-create-candidate entity segment expected-style pick point audit-offset)
              last-result promotion-result
              promotion-placement (if (and (listp promotion-result) (> (length promotion-result) 2)) (nth 2 promotion-result) nil)
              promotion-valid (if (and (listp promotion-result) (> (length promotion-result) 3)) (nth 3 promotion-result) nil)
              promotion-handle (if (and (listp promotion-result) (= (length (cadr promotion-result)) 1)) (car (cadr promotion-result)) "")
              promotion-audit (if (and promotion-valid (/= promotion-handle "") (cx:pg-audit-normal-p promotion-placement))
                                (cx:asv4-semantic-audit entity segment promotion-handle 0.011)
                                (list "FAIL" "INVALID_PLACEMENT_OR_STYLE" nil nil nil))
              attempt-details (strcat attempt-details
                "|NATIVE_ANGLE_VECTOR_V4{route=COMPLETE_POLYLINE_PROMOTION,fraction=" (rtos fraction 2 2)
                ",born_style=" (cx:asv4-style promotion-handle)
                "," (cx:asv4-placement-vector promotion-placement)
                ",semantic_state=" (car promotion-audit)
                ",creation_empty_text_defer=FORBIDDEN,"
                (cx:asv4-semantic-vector promotion-audit) "}"))
        ;; Promotion may have passed through a writable style normalizer; it is
        ;; accepted only with immediate non-empty angle semantic PASS.
        (if (= (car promotion-audit) "PASS")
          (setq accepted promotion-result)
          (cx:asv4-delete-result promotion-result)))))
  (setq cx:*sp2-last-trace* (strcat cx:*sp2-last-trace*
    "|GENERIC_ANGLE_SEMANTIC_VECTOR_V4{" attempt-details "}"))
  (if accepted accepted
    (if last-result last-result
      (list nil '() (list 0 "NO_SEMANTIC_CANDIDATE" 0.0 audit-offset 1e99 0) nil))))

(princ)
