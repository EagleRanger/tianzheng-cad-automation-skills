(vl-load-com)

;; Transactional final-survivor settlement V5.
;; V4 proved that segment-local exceptions no longer suppress the continuous
;; batch report.  Run87 exposed two independent formula defects:
;; 1. entdel toggles a previously deleted entity back to life when called a
;;    second time, so the final commit must delete only live candidates.
;; 2. the correction cursor must preserve the sign of the native actual band,
;;    not the sign of whichever positive/negative audit row won a tie.

(defun cx:cs-safe-number (value fallback)
  (if (numberp value) value fallback))

(defun cx:cs-safe-audit-rank (result)
  (if (and (listp result) (numberp (car result))) (fix (car result)) 0))

(defun cx:cs-safe-audit-residual (result)
  (if (and (listp result) (>= (length result) 5) (numberp (nth 4 result)))
    (abs (nth 4 result))
    1e99))

(defun cx:cs-safe-audit-diagnostic (result / diagnostic)
  (setq diagnostic
    (vl-catch-all-apply 'cx:pg-audit-diagnostic (list result)))
  (if (vl-catch-all-error-p diagnostic)
    (strcat "placement=INVALID_AUDIT_RESULT,error="
      (vl-catch-all-error-message diagnostic))
    diagnostic))

(defun cx:cs-placement-better-p (candidate current / candidate-rank current-rank)
  (setq candidate-rank (cx:cs-safe-audit-rank candidate)
        current-rank (cx:cs-safe-audit-rank current))
  (or (> candidate-rank current-rank)
      (and (= candidate-rank current-rank)
           (< (cx:cs-safe-audit-residual candidate)
              (cx:cs-safe-audit-residual current)))))

(defun cx:cs-audit-side-better-p (candidate current)
  (cx:cs-placement-better-p candidate current))

(defun cx:cs-native-band-sign (placement fallback / actual)
  (setq actual
    (if (and (listp placement) (>= (length placement) 3))
      (cx:cs-safe-number (nth 2 placement) 0.0)
      0.0))
  (if (> (abs actual) 1e-9)
    (cx:cs-sign actual)
    (cx:cs-sign fallback)))

(defun cx:cs-best-seed-audit
  (entity segment dimension-handle offset / magnitude positive negative chosen seed)
  ;; Rank/residual still selects the most informative audit result.  The seed
  ;; sign, however, comes from the native object's actual band.  This keeps a
  ;; negative-side survivor negative while moving farther away from zero.
  (setq magnitude (abs offset)
        positive (cx:pg-audit entity "ARC" segment dimension-handle magnitude)
        negative (cx:pg-audit entity "ARC" segment dimension-handle (- magnitude))
        chosen
          (if (cx:cs-audit-side-better-p positive negative)
            positive
            negative)
        seed (* (cx:cs-native-band-sign chosen offset) magnitude))
  (list chosen seed))

(defun cx:cs-entry-detail (added placement seed-offset)
  (strcat
    "FINAL_STAGE_CREATION_SETTLE_ENTRY"
    "{added=" (cx:fb-join added)
    ",seed=" (rtos (cx:cs-safe-number seed-offset 0.0) 2 9)
    "," (cx:cs-safe-audit-diagnostic placement) "}"))

(defun cx:cs-correction-detail
  (index cursor-offset added placement accepted)
  (strcat
    "CREATION_SIGNED_FINAL_POINT_" (itoa index)
    "{cursor=" (rtos (cx:cs-safe-number cursor-offset 0.0) 2 9)
    ",added=" (cx:fb-join added)
    ",accepted=" (if accepted "YES" "NO")
    "," (cx:cs-safe-audit-diagnostic placement) "}"))

(defun cx:cs-opposite-detail (cursor-offset added placement accepted)
  (strcat
    "CREATION_OPPOSITE_SIDE_FINAL_POINT_1"
    "{cursor=" (rtos (cx:cs-safe-number cursor-offset 0.0) 2 9)
    ",added=" (cx:fb-join added)
    ",accepted=" (if accepted "YES" "NO")
    "," (cx:cs-safe-audit-diagnostic placement) "}"))

(defun cx:cs-transaction-error-detail (message)
  (strcat "FINAL_CREATION_SETTLE_ERROR_ROLLBACK_TO_ORIGINAL{"
    (vl-princ-to-string message) "}"))

(defun cx:cs-delete-live-handles (handles / handle entity)
  ;; AutoLISP entdel is a toggle.  entget is nil for an already-deleted entity,
  ;; so this guard makes settlement cleanup idempotent and prevents resurrection.
  (foreach handle handles
    (setq entity (handent handle))
    (if (and entity (entget entity)) (entdel entity))))

(defun cx:cs-delete-handles-except (handles keep / victims item)
  (setq victims '())
  (foreach item handles
    (if (not (member item keep)) (setq victims (cons item victims))))
  (if victims
    (vl-catch-all-apply 'cx:cs-delete-live-handles (list victims)))
  victims)

(defun cx:cs-settle-final-result-core
  (entity segment offset expected-style result
    / detail original-added all-created pick seed-side audit-pair seed-offset
       placement best-result best-placement best-added cursor-offset
       correction-index gap corrected-side attempt candidate-call
       candidate-added candidate-placement candidate-valid candidate-better
       candidate-result opposite-offset opposite-side commit-result)
  (setq detail (cx:cs-result-detail result)
        original-added (cx:cs-result-added result)
        all-created '())
  (if (/= (length original-added) 1)
    result
    (progn
      (setq pick (nth 2 result)
            seed-side (nth 3 result)
            audit-pair
              (cx:cs-best-seed-audit
                entity segment (car original-added) offset)
            placement (car audit-pair)
            seed-offset (cadr audit-pair)
            detail
              (cx:cs-append-detail detail
                (cx:cs-entry-detail original-added placement seed-offset))
            best-result (cx:cs-with-detail result detail)
            best-placement placement
            best-added original-added
            cursor-offset seed-offset
            correction-index 0)

      (while (and (< correction-index cx:*cs-max-creation-corrections*)
                  (= (cx:cs-safe-audit-rank best-placement) 1))
        (setq correction-index (1+ correction-index)
              gap (- (abs (cx:cs-safe-number (nth 3 best-placement) 0.0))
                     (abs (cx:cs-safe-number (nth 2 best-placement) 0.0))))
        (if (< (abs gap) cx:*cs-correction-minimum*)
          (setq correction-index cx:*cs-max-creation-corrections*)
          (progn
            (setq cursor-offset
                    (cx:cs-next-signed-cursor
                      cursor-offset
                      (cx:cs-safe-number (nth 3 best-placement) seed-offset)
                      (cx:cs-safe-number (nth 2 best-placement) seed-offset))
                  corrected-side
                    (cx:cs-corrected-side
                      pick seed-side seed-offset cursor-offset))
            (if corrected-side
              (progn
                (cx:pg-set-visible best-added nil)
                (setq attempt
                        (cx:cs-create-candidate
                          entity segment expected-style pick corrected-side
                          seed-offset)
                      candidate-call (nth 0 attempt)
                      candidate-added (nth 1 attempt)
                      all-created (append candidate-added all-created)
                      candidate-placement (nth 2 attempt)
                      candidate-valid (nth 3 attempt)
                      candidate-better
                        (and candidate-valid
                             (cx:pg-audit-pass-p candidate-placement)
                             (cx:cs-placement-better-p
                               candidate-placement best-placement))
                      detail
                        (cx:cs-append-detail detail
                          (cx:cs-correction-detail correction-index
                            cursor-offset candidate-added
                            candidate-placement candidate-better)))
                (if candidate-better
                  (progn
                    (setq candidate-result
                            (list candidate-call candidate-added
                              pick corrected-side detail)
                          best-result candidate-result
                          best-placement candidate-placement
                          best-added candidate-added))
                  (progn
                    (if candidate-added
                      (cx:cs-delete-live-handles candidate-added))
                    (cx:pg-set-visible best-added T)))
                (setq best-result (cx:cs-with-detail best-result detail)))
              (setq correction-index cx:*cs-max-creation-corrections*)))))

      (if (and (= cx:*cs-max-opposite-side-fallbacks* 1)
               (= (cx:cs-safe-audit-rank best-placement) 1))
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
                    all-created (append candidate-added all-created)
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
                          candidate-added candidate-placement
                          candidate-better)))
              (if candidate-better
                (setq candidate-result
                        (list candidate-call candidate-added
                          pick opposite-side detail)
                      best-result candidate-result
                      best-placement candidate-placement
                      best-added candidate-added)
                (progn
                  (if candidate-added
                    (cx:cs-delete-live-handles candidate-added))
                  (cx:pg-set-visible best-added T)))
              (setq best-result (cx:cs-with-detail best-result detail))))))

      (setq commit-result (cx:cs-with-detail best-result detail))
      (cx:pg-set-visible best-added T)
      (vl-catch-all-apply
        'cx:cs-delete-handles-except
        (list (append original-added all-created) best-added))
      commit-result)))

(defun cx:cs-settle-final-result
  (entity segment offset expected-style result
    / before original-added settled after new-handles detail)
  (setq before (cx:fb-native-handles)
        original-added (cx:cs-result-added result)
        settled
          (vl-catch-all-apply
            'cx:cs-settle-final-result-core
            (list entity segment offset expected-style result)))
  (if (vl-catch-all-error-p settled)
    (progn
      (setq after (cx:fb-native-handles)
            new-handles (cx:fb-difference after before))
      (if new-handles
        (vl-catch-all-apply 'cx:cs-delete-live-handles (list new-handles)))
      (if original-added (cx:pg-set-visible original-added T))
      (setq detail
        (cx:cs-append-detail
          (cx:cs-result-detail result)
          (cx:cs-transaction-error-detail
            (vl-catch-all-error-message settled))))
      (cx:cs-with-detail result detail))
    settled))

(princ)
