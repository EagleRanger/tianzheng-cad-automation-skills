;; V6 adds a second, minimal segment-local containment boundary around the
;; transactional V4 settlement.  Even an unexpected adapter error must return
;; the original survivor and allow the continuous batch summary to finish.

(defun cx:gr-result-detail (result)
  (if (and (listp result) (>= (length result) 5) (nth 4 result))
    (nth 4 result)
    "NO_RESULT_DETAIL"))

(defun cx:gr-add-history (history stage result / item)
  (setq item (strcat stage "{" (cx:gr-result-detail result) "}"))
  (if (= history "") item (strcat history "||" item)))

(defun cx:gr-with-history (result history)
  (if (and (listp result) (>= (length result) 5))
    (list (nth 0 result) (nth 1 result) (nth 2 result) (nth 3 result) history)
    (list nil '() nil nil history)))

(defun cx:gr-settle-contained
  (entity segment offset expected-style result / settled detail)
  (setq settled
    (vl-catch-all-apply
      'cx:cs-settle-final-result
      (list entity segment offset expected-style result)))
  (if (vl-catch-all-error-p settled)
    (progn
      (if (cx:cs-result-added result)
        (cx:pg-set-visible (cx:cs-result-added result) T))
      (setq detail
        (cx:cs-append-detail
          (cx:cs-result-detail result)
          (strcat "FINAL_CREATION_SETTLE_OUTER_CONTAINMENT{"
            (vl-catch-all-error-message settled) "}")))
      (cx:cs-with-detail result detail))
    settled))

(defun cx:fb-run-one
  (entity segment offset expected-style / result history)
  (if (cx:ss-switch-source entity)
    (progn
      (if (>= cx:*ss-current-count* 2)
        (progn
          (cx:ss-zoom-segment entity segment offset)
          (vl-catch-all-apply 'command-s (list "_.REGEN"))
          (setq cx:*ss-current-count* 0)))
      (setq result (cx:pg-run-one entity segment offset expected-style)
            history (cx:gr-add-history "" "PRIMARY_SAME_SIDE" result))
      (if (= (length (cadr result)) 0)
        (progn
          (setq result
            (cx:ss-run-fresh-exclusive-retry
              entity segment offset expected-style nil))
          (setq history
            (cx:gr-add-history history "FRESH_BROAD_SAME_SIDE" result))))
      (if (= (length (cadr result)) 0)
        (progn
          (setq result
            (cx:ss-run-fresh-exclusive-retry
              entity segment (- offset) expected-style nil))
          (setq history
            (cx:gr-add-history history "FRESH_BROAD_OPPOSITE_SIDE" result))))
      (if (= (length (cadr result)) 0)
        (progn
          (setq result
            (cx:ss-run-fresh-exclusive-retry
              entity segment offset expected-style T))
          (setq history
            (cx:gr-add-history history "FRESH_TIGHT_SAME_SIDE" result))))

      (if (= (length (cadr result)) 1)
        (progn
          (setq result
            (cx:gr-settle-contained
              entity segment offset expected-style result))
          (setq history
            (cx:gr-add-history history "FINAL_CREATION_SETTLE" result))))

      (if (= (length (cadr result)) 1)
        (setq cx:*ss-current-count* (1+ cx:*ss-current-count*)))
      (cx:gr-with-history result history))
    (list nil '() nil nil "SOURCE_SERIAL_VISIBILITY_SWITCH_FAILED")))

(defun cx:gr-fresh-line-attempt
  (entity segment offset tight / hidden zoom-ok result)
  (cx:ss-restore-current-source)
  (if (not (cx:ss-switch-source entity))
    (list nil '() nil nil "FRESH_LINE_SOURCE_RESET_FAILED")
    (progn
      (setq hidden (cx:ss-hide-other-visible entity))
      (vl-catch-all-apply 'command-s (list "_.REGEN"))
      (setq zoom-ok
        (if tight
          (cx:ss-zoom-segment-tight entity segment)
          (cx:ss-zoom-segment entity segment offset)))
      (vl-catch-all-apply 'command-s (list "_.REGEN"))
      (if zoom-ok
        (setq result (cx:pg-run-line entity segment offset))
        (setq result
          (list nil '() nil nil
            (if tight
              "FRESH_LINE_TIGHT_RETRY_ZOOM_FAILED"
              "FRESH_LINE_BROAD_RETRY_ZOOM_FAILED"))))
      (cx:ss-restore-visible hidden)
      (vl-catch-all-apply 'command-s (list "_.REGEN"))
      result)))

(defun cx:fb-run-line (entity segment offset / result history)
  (if (cx:ss-switch-source entity)
    (progn
      (if (>= cx:*ss-current-count* 2)
        (progn
          (cx:ss-zoom-segment entity segment offset)
          (vl-catch-all-apply 'command-s (list "_.REGEN"))
          (setq cx:*ss-current-count* 0)))
      (setq result (cx:pg-run-line entity segment offset)
            history (cx:gr-add-history "" "PRIMARY_SAME_SIDE" result))
      (if (= (length (cadr result)) 0)
        (progn
          (setq result (cx:gr-fresh-line-attempt entity segment offset nil))
          (setq history
            (cx:gr-add-history history "FRESH_BROAD_SAME_SIDE" result))))
      (if (= (length (cadr result)) 0)
        (progn
          (setq result (cx:gr-fresh-line-attempt entity segment (- offset) nil))
          (setq history
            (cx:gr-add-history history "FRESH_BROAD_OPPOSITE_SIDE" result))))
      (if (= (length (cadr result)) 0)
        (progn
          (setq result (cx:gr-fresh-line-attempt entity segment offset T))
          (setq history
            (cx:gr-add-history history "FRESH_TIGHT_SAME_SIDE" result))))
      (if (= (length (cadr result)) 1)
        (setq cx:*ss-current-count* (1+ cx:*ss-current-count*)))
      (cx:gr-with-history result history))
    (list nil '() nil nil "SOURCE_SERIAL_VISIBILITY_SWITCH_FAILED")))

(princ)
