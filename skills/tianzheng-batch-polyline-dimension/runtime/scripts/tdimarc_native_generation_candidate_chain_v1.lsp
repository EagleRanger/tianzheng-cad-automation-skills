(vl-load-com)

;; Generic fallback chain. Ordinary generation is handled by cx:dp4-run-one.
;; This chain runs only after the ordinary result is missing or below rank2.

(defun cx:gc1-rank2-p (result / placement)
  (setq placement (if (and (listp result) (> (length result) 2)) (nth 2 result) nil))
  (and (listp result) (> (length result) 3) (nth 3 result)
       (>= (cx:cs-safe-audit-rank placement) 2)))

(defun cx:gc1-delete-result (result / handles)
  (setq handles (if (and (listp result) (> (length result) 1)) (nth 1 result) nil))
  (if handles (cx:cs-delete-live-handles handles)))

(defun cx:ha1-create-candidate
  (entity segment expected-style pick point audit-offset / endpoint-result promotion-result)
  (setq endpoint-result
    (cx:geh1-create-candidate entity segment expected-style pick point audit-offset))
  (if (cx:gc1-rank2-p endpoint-result)
    endpoint-result
    (progn
      (cx:gc1-delete-result endpoint-result)
      (setq promotion-result
        (cx:gcp1-create-candidate entity segment expected-style pick point audit-offset))
      promotion-result)))

(princ)
