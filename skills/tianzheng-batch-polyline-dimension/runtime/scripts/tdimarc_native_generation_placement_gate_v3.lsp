(vl-load-com)

;; Generation gate V3 separates native-object usability from final D3 layout.
;; Rank 2 is already in the normal generation band.  Rank 1 is directionally
;; correct and far enough from the source to preserve for later grip0 layout.
;; Rank 0 is wrong-side, endpoint-coincident, too close, too far, or invalid.
(if (not (boundp 'cx:*pg-seed-band-h*))
  (setq cx:*pg-seed-band-h* 1.85))
(if (not (boundp 'cx:*pg-minimum-usable-band-h*))
  (setq cx:*pg-minimum-usable-band-h* 1.10))
(if (not (boundp 'cx:*pg-normal-band-h*))
  (setq cx:*pg-normal-band-h* 1.60))
(if (not (boundp 'cx:*pg-maximum-usable-band-h*))
  (setq cx:*pg-maximum-usable-band-h* 2.35))

(defun cx:pg-audit
  (entity segment-type segment dimension-handle offset
    / source-object source-handle result)
  (setq source-object (vlax-ename->vla-object entity)
        source-handle (vla-get-Handle source-object)
        result
          (vl-catch-all-apply
            'CXNATIVEPLACEMENTAUDITV2
            (list source-handle segment-type segment dimension-handle offset
                  cx:*pg-seed-band-h* cx:*pg-minimum-usable-band-h*
                  cx:*pg-normal-band-h* cx:*pg-maximum-usable-band-h*)))
  (if (vl-catch-all-error-p result)
    (list 0
      (strcat "PLACEMENT_AUDIT_V2_CALL_FAILED:"
              (vl-catch-all-error-message result))
      0.0 0.0 1e99 0)
    result))

(defun cx:pg-audit-rank (result)
  (if (and (listp result) (numberp (car result))) (fix (car result)) 0))

(defun cx:pg-audit-pass-p (result)
  (> (cx:pg-audit-rank result) 0))

(defun cx:pg-audit-normal-p (result)
  (= (cx:pg-audit-rank result) 2))

(defun cx:pg-provisional-better-p (candidate current)
  (or (null current)
      (> (abs (nth 2 candidate)) (abs (nth 2 current)))))

(defun cx:pg-set-visible (handles visible / handle entity object)
  (foreach handle handles
    (setq entity (handent handle))
    (if (and entity (entget entity))
      (progn
        (setq object (vl-catch-all-apply 'vlax-ename->vla-object (list entity)))
        (if (and object (not (vl-catch-all-error-p object)))
          (vl-catch-all-apply 'vla-put-Visible
            (list object (if visible :vlax-true :vlax-false))))))))

(defun cx:pg-audit-diagnostic (result)
  (if (and (listp result) (>= (length result) 6))
    (strcat
      "placement=" (vl-princ-to-string (nth 1 result))
      ",rank=" (itoa (cx:pg-audit-rank result))
      ",actual=" (rtos (nth 2 result) 2 9)
      ",expected=" (rtos (nth 3 result) 2 9)
      ",residual=" (rtos (nth 4 result) 2 9)
      ",grips=" (itoa (fix (nth 5 result))))
    "placement=INVALID_AUDIT_RESULT,rank=0"))

(defun cx:pg-run-one
  (entity segment offset expected-style
    / fractions fraction points pick side before after added call-result result
       attempts info diagnostic placement dimension-handle normal-found
       provisional-added provisional-placement provisional-pick provisional-side
       provisional-call)
  (setq fractions '(0.35 0.65 0.20 0.80 0.50)
        result (list nil '() nil nil "")
        attempts '() normal-found nil provisional-added '()
        provisional-placement nil provisional-pick nil provisional-side nil
        provisional-call nil)
  (while (and fractions (not normal-found))
    (setq fraction (car fractions)
          fractions (cdr fractions)
          points (cx:fb-segment-points entity segment fraction offset))
    (if points
      (progn
        (setq pick (car points)
              side (cadr points)
              before (cx:fb-native-handles)
              call-result
                (vl-catch-all-apply
                  'command-s (list "TDIMARC" pick pick side ""))
              after (cx:fb-native-handles)
              added (cx:fb-difference after before)
              info (cx:fb-created-object-info added)
              diagnostic (cx:fb-call-diagnostic fraction call-result added)
              placement nil)
        (if (and (not (vl-catch-all-error-p call-result))
                 (cx:fb-created-object-valid-p added expected-style))
          (progn
            (setq dimension-handle (car added)
                  placement
                    (cx:pg-audit entity "ARC" segment dimension-handle offset))
            (cond
              ((cx:pg-audit-normal-p placement)
                (if provisional-added
                  (cx:fb-delete-handles provisional-added))
                (setq provisional-added '()
                      attempts
                        (append attempts
                          (list
                            (strcat diagnostic ",semantic=ACCEPTED_NORMAL,"
                                    (cx:pg-audit-diagnostic placement))))
                      result
                        (list call-result added pick side (cx:fb-join attempts))
                      normal-found T))
              ((cx:pg-audit-pass-p placement)
                (if (cx:pg-provisional-better-p
                      placement provisional-placement)
                  (progn
                    (if provisional-added
                      (cx:fb-delete-handles provisional-added))
                    (cx:pg-set-visible added nil)
                    (setq provisional-added added
                          provisional-placement placement
                          provisional-pick pick
                          provisional-side side
                          provisional-call call-result
                          attempts
                            (append attempts
                              (list
                                (strcat diagnostic
                                  ",semantic=HELD_LAYOUT_REQUIRED,"
                                  (cx:pg-audit-diagnostic placement))))))
                  (progn
                    (cx:fb-delete-handles added)
                    (setq attempts
                      (append attempts
                        (list
                          (strcat diagnostic
                            ",semantic=DISCARDED_WEAKER_LAYOUT_CANDIDATE,"
                            (cx:pg-audit-diagnostic placement))))))))
              (t
                (cx:fb-delete-handles added)
                (setq attempts
                  (append attempts
                    (list
                      (strcat diagnostic
                        ",semantic=DISCARDED_UNUSABLE_PLACEMENT,"
                        (cx:pg-audit-diagnostic placement))))))))
          (progn
            (if added (cx:fb-delete-handles added))
            (setq attempts
              (append attempts
                (list
                  (strcat diagnostic
                    ",semantic=DISCARDED"
                    ",object=" (cadr info)
                    ",layer=" (caddr info)
                    ",style=" (cadddr info))))))))))
  (if (and (not normal-found) provisional-added)
    (progn
      (cx:pg-set-visible provisional-added T)
      (setq attempts
        (append attempts
          (list
            (strcat "semantic=ACCEPTED_LAYOUT_REQUIRED,"
                    (cx:pg-audit-diagnostic provisional-placement)))))
      (setq result
        (list provisional-call provisional-added provisional-pick
              provisional-side (cx:fb-join attempts)))))
  result)

(defun cx:pg-run-line
  (entity segment offset
    / points p0 p1 side before after added call-result info placement
       dimension-handle diagnostic expected-style)
  (setq expected-style "_TCH_ARCH_M_M"
        points (cx:fb-line-points entity segment offset))
  (if points
    (progn
      (setq p0 (car points)
            p1 (cadr points)
            side (caddr points)
            before (cx:fb-native-handles)
            call-result
              (vl-catch-all-apply
                'command-s (list "TDimMP" p0 p1 side ""))
            after (cx:fb-native-handles)
            added (cx:fb-difference after before)
            info (cx:fb-created-object-info added)
            diagnostic (cx:fb-call-diagnostic 0.50 call-result added)
            placement nil)
      (if (and (not (vl-catch-all-error-p call-result))
               (cx:fb-created-object-valid-p added expected-style))
        (progn
          (setq dimension-handle (car added)
                placement
                  (cx:pg-audit entity "LINE" segment dimension-handle offset))
          (if (cx:pg-audit-pass-p placement)
            (list call-result added p0 side
              (strcat diagnostic
                (if (cx:pg-audit-normal-p placement)
                  ",semantic=ACCEPTED_NORMAL,"
                  ",semantic=ACCEPTED_LAYOUT_REQUIRED,")
                (cx:pg-audit-diagnostic placement)))
            (progn
              (cx:fb-delete-handles added)
              (list call-result '() p0 side
                (strcat diagnostic
                  ",semantic=DISCARDED_UNUSABLE_PLACEMENT,"
                  (cx:pg-audit-diagnostic placement))))))
        (progn
          (if added (cx:fb-delete-handles added))
          (list call-result '() p0 side
            (strcat diagnostic
              ",semantic=DISCARDED"
              ",object=" (cadr info)
              ",layer=" (caddr info)
              ",style=" (cadddr info))))))
    (list nil '() nil nil "LINE_POINTS_FAILED")))

(princ)
