(vl-load-com)

;; V5 business acceptance for fallback angle creation. Endpoint-helper results
;; keep the existing semantic contract. Complete-polyline promotion is accepted
;; only when the active promotion route returned a native candidate born with
;; the requested angle style and the existing placement audit is rank2.
;; Text display is verified later by the observer-side temporary-copy probe.

(defun cx:bav5-result-handle (result / handles)
  (setq handles
    (if (and (listp result) (> (length result) 1) (listp (nth 1 result)))
      (nth 1 result) '()))
  (if (= (length handles) 1) (car handles) ""))

(defun cx:bav5-result-placement (result)
  (if (and (listp result) (> (length result) 2) (listp (nth 2 result)))
    (nth 2 result) nil))

(defun cx:bav5-result-valid (result)
  (and (listp result) (> (length result) 3) (nth 3 result)))

(defun cx:bav5-born-angle-pass-p
  (result expected-style / handle placement)
  (setq handle (cx:bav5-result-handle result)
        placement (cx:bav5-result-placement result))
  (and (cx:bav5-result-valid result)
       (/= handle "")
       (= (cx:asv4-style handle) expected-style)
       (cx:pg-audit-normal-p placement)))

(defun cx:ha1-create-candidate
  (entity segment expected-style ignored-pick point audit-offset
    / fractions fraction pick endpoint-result endpoint-placement endpoint-valid
      endpoint-handle endpoint-audit endpoint-state promotion-result
      promotion-placement promotion-handle accepted attempt-details last-result)
  (setq fractions '(0.35 0.65 0.20 0.80 0.50)
        accepted nil attempt-details "" last-result nil)
  (while (and fractions (null accepted))
    (setq fraction (car fractions)
          fractions (cdr fractions)
          pick (vlax-curve-getPointAtParam entity (+ segment fraction))
          endpoint-result
            (cx:geh1-create-candidate
              entity segment expected-style pick point audit-offset)
          endpoint-placement (cx:bav5-result-placement endpoint-result)
          endpoint-valid (cx:bav5-result-valid endpoint-result)
          endpoint-handle (cx:bav5-result-handle endpoint-result)
          endpoint-audit
            (if (and endpoint-valid (/= endpoint-handle "")
                     (cx:pg-audit-normal-p endpoint-placement))
              (cx:asv4-semantic-audit
                entity segment endpoint-handle 0.011)
              (list "FAIL" "INVALID_PLACEMENT_OR_STYLE" nil nil nil))
          endpoint-state (cx:asv4-endpoint-state endpoint-audit)
          attempt-details
            (strcat attempt-details (if (= attempt-details "") "" "|")
              "NATIVE_ANGLE_VECTOR_V5{route=ENDPOINT_HELPER,fraction="
              (rtos fraction 2 2)
              ",born_style=" (cx:asv4-style endpoint-handle)
              "," (cx:asv4-placement-vector endpoint-placement)
              ",semantic_state=" endpoint-state
              "," (cx:asv4-semantic-vector endpoint-audit) "}"))
    (if (/= endpoint-state "FAIL")
      (setq accepted endpoint-result last-result endpoint-result)
      (progn
        (cx:asv4-delete-result endpoint-result)
        (setq promotion-result
          (cx:gcp1-create-candidate
            entity segment expected-style pick point audit-offset)
              last-result promotion-result
              promotion-placement
                (cx:bav5-result-placement promotion-result)
              promotion-handle
                (cx:bav5-result-handle promotion-result)
              attempt-details
                (strcat attempt-details
                  "|NATIVE_ANGLE_VECTOR_V5{route=BORN_ANGLE_PROMOTION,fraction="
                  (rtos fraction 2 2)
                  ",born_style=" (cx:asv4-style promotion-handle)
                  "," (cx:asv4-placement-vector promotion-placement)
                  ",semantic_state="
                  (if (cx:bav5-born-angle-pass-p
                        promotion-result expected-style)
                    "BORN_INCLUDED_ANGLE_BY_PROMPT_VECTOR"
                    "FAIL")
                  ",style_write=0,display_text_wait=0}"))
        (if (cx:bav5-born-angle-pass-p promotion-result expected-style)
          (setq accepted promotion-result)
          (cx:asv4-delete-result promotion-result)))))
  (setq cx:*sp2-last-trace*
    (strcat cx:*sp2-last-trace*
      "|GENERIC_ANGLE_SEMANTIC_VECTOR_V5{" attempt-details "}"))
  (if accepted
    accepted
    (if last-result
      last-result
      (list nil '()
        (list 0 "NO_BORN_ANGLE_CANDIDATE" 0.0 audit-offset 1e99 0)
        nil))))

(princ)
