(vl-load-com)

;; Validation-only creation-time settlement V3.
;; The verified V3 placement gate still owns every ordinary TDIMARC attempt.
;; Unlike V2, this adapter does not settle each inner attempt.  The outer retry
;; chain first selects its one final survivor, then calls
;; cx:cs-settle-final-result exactly once.  This prevents a rank-1 survivor
;; found by a later broad/opposite/tight stage from bypassing settlement.

(if (not (boundp 'cx:*cs-max-creation-corrections*))
  (setq cx:*cs-max-creation-corrections* 2))
(if (not (boundp 'cx:*cs-max-opposite-side-fallbacks*))
  (setq cx:*cs-max-opposite-side-fallbacks* 1))
(if (not (boundp 'cx:*cs-correction-minimum*))
  (setq cx:*cs-correction-minimum* 1e-6))

(defun cx:cs-result-added (result)
  (if (and (listp result) (>= (length result) 2) (listp (nth 1 result)))
    (nth 1 result)
    '()))

(defun cx:cs-result-detail (result)
  (if (and (listp result) (>= (length result) 5) (nth 4 result))
    (nth 4 result)
    ""))

(defun cx:cs-append-detail (base item)
  (cond
    ((or (null base) (= base "")) item)
    ((or (null item) (= item "")) base)
    (t (strcat base "||" item))))

(defun cx:cs-with-detail (result detail)
  (if (and (listp result) (>= (length result) 4))
    (list (nth 0 result) (nth 1 result) (nth 2 result) (nth 3 result) detail)
    (list nil '() nil nil detail)))

(defun cx:cs-placement-better-p (candidate current / candidate-rank current-rank)
  (setq candidate-rank (cx:pg-audit-rank candidate)
        current-rank (cx:pg-audit-rank current))
  (or (> candidate-rank current-rank)
      (and (= candidate-rank current-rank)
           (< (abs (nth 4 candidate)) (abs (nth 4 current))))))

(defun cx:cs-sign (value)
  (if (< value 0.0) -1.0 1.0))

(defun cx:cs-next-signed-cursor (cursor-offset desired-band actual-band)
  ;; Preserve the accepted side.  A negative seed becomes more negative when
  ;; the native band magnitude is too small.
  (+ cursor-offset
     (* (cx:cs-sign cursor-offset)
        (- (abs desired-band) (abs actual-band)))))

(defun cx:cs-corrected-side
  (pick seed-side seed-offset cursor-offset / vector scale)
  (if (and pick seed-side (numberp seed-offset) (> (abs seed-offset) 1e-9))
    (progn
      (setq vector (mapcar '- seed-side pick)
            scale (/ cursor-offset seed-offset))
      (mapcar '+ pick (mapcar '(lambda (value) (* value scale)) vector)))
    nil))

(defun cx:cs-audit-side-better-p (candidate current / candidate-rank current-rank)
  (setq candidate-rank (cx:pg-audit-rank candidate)
        current-rank (cx:pg-audit-rank current))
  (or (> candidate-rank current-rank)
      (and (= candidate-rank current-rank)
           (< (abs (nth 4 candidate)) (abs (nth 4 current))))))

(defun cx:cs-best-seed-audit
  (entity segment dimension-handle offset / magnitude positive negative)
  ;; The outer retry may have found the survivor on either side.  Re-audit both
  ;; signed bands and let the native object identify its real seed side.
  (setq magnitude (abs offset)
        positive (cx:pg-audit entity "ARC" segment dimension-handle magnitude)
        negative (cx:pg-audit entity "ARC" segment dimension-handle (- magnitude)))
  (if (cx:cs-audit-side-better-p positive negative)
    (list positive magnitude)
    (list negative (- magnitude))))

(defun cx:cs-entry-detail (added placement seed-offset)
  (strcat
    "FINAL_STAGE_CREATION_SETTLE_ENTRY"
    "{added=" (cx:fb-join added)
    ",seed=" (rtos seed-offset 2 9)
    "," (cx:pg-audit-diagnostic placement) "}"))

(defun cx:cs-correction-detail
  (index cursor-offset added placement accepted)
  (strcat
    "CREATION_SIGNED_FINAL_POINT_" (itoa index)
    "{cursor=" (rtos cursor-offset 2 9)
    ",added=" (cx:fb-join added)
    ",accepted=" (if accepted "YES" "NO")
    "," (cx:pg-audit-diagnostic placement) "}"))

(defun cx:cs-opposite-detail (cursor-offset added placement accepted)
  (strcat
    "CREATION_OPPOSITE_SIDE_FINAL_POINT_1"
    "{cursor=" (rtos cursor-offset 2 9)
    ",added=" (cx:fb-join added)
    ",accepted=" (if accepted "YES" "NO")
    "," (cx:pg-audit-diagnostic placement) "}"))

(defun cx:cs-create-candidate
  (entity segment expected-style pick point audit-offset
    / before call-result after added valid placement)
  (setq before (cx:fb-native-handles)
        call-result
          (vl-catch-all-apply
            'command-s (list "TDIMARC" pick pick point ""))
        after (cx:fb-native-handles)
        added (cx:fb-difference after before)
        valid
          (and (not (vl-catch-all-error-p call-result))
               (cx:fb-created-object-valid-p added expected-style))
        placement
          (if valid
            (cx:pg-audit entity "ARC" segment (car added) audit-offset)
            (list 0 "INVALID_CREATION_CANDIDATE"
              0.0 audit-offset 1e99 0)))
  (list call-result added placement valid))

(defun cx:pg-run-one (entity segment offset expected-style / result detail added)
  ;; Keep the normal kernel unchanged.  Only an empty inner attempt receives
  ;; one explicit render recovery replay.  Final placement settlement happens
  ;; after the outer retry chain has selected its survivor.
  (setq result (cx:pg-v3-run-one entity segment offset expected-style)
        detail (cx:cs-result-detail result)
        added (cx:cs-result-added result))
  (if (= (length added) 0)
    (progn
      (vl-catch-all-apply 'command-s (list "_.REGEN"))
      (vl-catch-all-apply 'redraw '())
      (setq result (cx:pg-v3-run-one entity segment offset expected-style)
            detail
              (cx:cs-append-detail detail
                (strcat "EXPLICIT_REGEN_REPLAY{" (cx:cs-result-detail result) "}"))
            result (cx:cs-with-detail result detail))))
  result)

(defun cx:cs-settle-final-result
  (entity segment offset expected-style result
    / detail added pick seed-side audit-pair seed-offset placement
       best-result best-placement best-added cursor-offset correction-index
       gap corrected-side attempt candidate-call candidate-added
       candidate-placement candidate-valid candidate-better candidate-result
       opposite-offset opposite-side)
  (setq detail (cx:cs-result-detail result)
        added (cx:cs-result-added result))
  (if (= (length added) 1)
    (progn
      (setq pick (nth 2 result)
            seed-side (nth 3 result)
            audit-pair
              (cx:cs-best-seed-audit entity segment (car added) offset)
            placement (car audit-pair)
            seed-offset (cadr audit-pair)
            detail
              (cx:cs-append-detail detail
                (cx:cs-entry-detail added placement seed-offset))
            best-result (cx:cs-with-detail result detail)
            best-placement placement
            best-added added
            cursor-offset seed-offset
            correction-index 0)

      (while (and (< correction-index cx:*cs-max-creation-corrections*)
                  (= (cx:pg-audit-rank best-placement) 1))
        (setq correction-index (1+ correction-index)
              gap (- (abs (nth 3 best-placement))
                     (abs (nth 2 best-placement))))
        (if (< (abs gap) cx:*cs-correction-minimum*)
          (setq correction-index cx:*cs-max-creation-corrections*)
          (progn
            (setq cursor-offset
                    (cx:cs-next-signed-cursor
                      cursor-offset
                      (nth 3 best-placement)
                      (nth 2 best-placement))
                  corrected-side
                    (cx:cs-corrected-side
                      pick seed-side seed-offset cursor-offset))
            (if corrected-side
              (progn
                (cx:pg-set-visible best-added nil)
                (setq attempt
                        (cx:cs-create-candidate
                          entity segment expected-style pick corrected-side seed-offset)
                      candidate-call (nth 0 attempt)
                      candidate-added (nth 1 attempt)
                      candidate-placement (nth 2 attempt)
                      candidate-valid (nth 3 attempt)
                      candidate-better
                        (and candidate-valid
                             (cx:pg-audit-pass-p candidate-placement)
                             (cx:cs-placement-better-p
                               candidate-placement best-placement))
                      detail
                        (cx:cs-append-detail detail
                          (cx:cs-correction-detail correction-index cursor-offset
                            candidate-added candidate-placement candidate-better)))
                (if candidate-better
                  (progn
                    (cx:fb-delete-handles best-added)
                    (setq candidate-result
                            (list candidate-call candidate-added
                              pick corrected-side detail)
                          best-result candidate-result
                          best-placement candidate-placement
                          best-added candidate-added))
                  (progn
                    (if candidate-added
                      (cx:fb-delete-handles candidate-added))
                    (cx:pg-set-visible best-added T)))
                (setq best-result (cx:cs-with-detail best-result detail)))
              (setq correction-index cx:*cs-max-creation-corrections*)))))

      (if (and (= cx:*cs-max-opposite-side-fallbacks* 1)
               (= (cx:pg-audit-rank best-placement) 1))
        (progn
          (setq opposite-offset (- seed-offset)
                opposite-side
                  (cx:cs-corrected-side
                    pick seed-side seed-offset opposite-offset))
          (if opposite-side
            (progn
              (cx:pg-set-visible best-added nil)
              (setq attempt
                      (cx:cs-create-candidate
                        entity segment expected-style pick
                        opposite-side opposite-offset)
                    candidate-call (nth 0 attempt)
                    candidate-added (nth 1 attempt)
                    candidate-placement (nth 2 attempt)
                    candidate-valid (nth 3 attempt)
                    candidate-better
                      (and candidate-valid
                           (cx:pg-audit-pass-p candidate-placement)
                           (cx:cs-placement-better-p
                             candidate-placement best-placement))
                    detail
                      (cx:cs-append-detail detail
                        (cx:cs-opposite-detail opposite-offset
                          candidate-added candidate-placement candidate-better)))
              (if candidate-better
                (progn
                  (cx:fb-delete-handles best-added)
                  (setq candidate-result
                          (list candidate-call candidate-added
                            pick opposite-side detail)
                        best-result candidate-result
                        best-placement candidate-placement
                        best-added candidate-added))
                (progn
                  (if candidate-added
                    (cx:fb-delete-handles candidate-added))
                  (cx:pg-set-visible best-added T)))
              (setq best-result (cx:cs-with-detail best-result detail)))))
      best-result)
    result)))

(princ)
