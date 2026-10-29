(vl-load-com)

;; V7 leaves every V6 success path unchanged.  Only after all proven stages
;; return no native object does it run a broad-neighbourhood retry whose pick
;; point must resolve back to the requested source polyline through NENTSELP.
;; Tianzheng TDIMARC uses a graphical selector, so a correct WCS point alone is
;; not enough when the display cache is stale.

(setq cx:*gr-require-graphical-hit* nil
      cx:*gr-last-graphical-hit-detail* "")

(defun cx:gr-raw-segment-points
  (entity segment fraction offset / parameter pick-result deriv-result
     before-result after-result pick-wcs deriv before-wcs after-wcs magnitude
     normal side-wcs)
  (setq parameter (+ segment fraction)
        pick-result
          (vl-catch-all-apply
            'vlax-curve-getPointAtParam (list entity parameter))
        deriv-result
          (vl-catch-all-apply
            'vlax-curve-getFirstDeriv (list entity parameter)))
  (if (not (vl-catch-all-error-p pick-result)) (setq pick-wcs pick-result))
  (if (not (vl-catch-all-error-p deriv-result)) (setq deriv deriv-result))
  (if (and pick-wcs (null deriv))
    (progn
      (setq before-result
        (vl-catch-all-apply 'vlax-curve-getPointAtParam
          (list entity (+ segment (max 0.05 (- fraction 0.05)))))
            after-result
        (vl-catch-all-apply 'vlax-curve-getPointAtParam
          (list entity (+ segment (min 0.95 (+ fraction 0.05))))))
      (if (and (not (vl-catch-all-error-p before-result))
               (not (vl-catch-all-error-p after-result))
               before-result after-result)
        (setq before-wcs before-result
              after-wcs after-result
              deriv (mapcar '- after-wcs before-wcs)))))
  (setq magnitude (if deriv (distance '(0.0 0.0 0.0) deriv) 0.0))
  (if (and pick-wcs (> magnitude 1e-9))
    (progn
      (setq normal
              (list (/ (- (cadr deriv)) magnitude)
                    (/ (car deriv) magnitude) 0.0)
            side-wcs
              (mapcar '+ pick-wcs
                (mapcar '(lambda (value) (* value offset)) normal)))
      (list (trans pick-wcs 0 1) (trans side-wcs 0 1)))
    nil))

(defun cx:fb-segment-points
  (entity segment fraction offset / points selected selected-entity)
  (setq points (cx:gr-raw-segment-points entity segment fraction offset))
  (if (or (not cx:*gr-require-graphical-hit*) (null points))
    points
    (progn
      (setq selected (vl-catch-all-apply 'nentselp (list (car points))))
      (if (and (not (vl-catch-all-error-p selected))
               selected
               (setq selected-entity (car selected))
               (eq selected-entity entity))
        (progn
          (setq cx:*gr-last-graphical-hit-detail*
            (strcat "PASS:fraction=" (rtos fraction 2 2)))
          points)
        (progn
          (setq cx:*gr-last-graphical-hit-detail*
            (strcat "MISS:fraction=" (rtos fraction 2 2)))
          nil)))))

(defun cx:gr-append-result-detail (result item / detail)
  (setq detail
    (if (and (listp result) (>= (length result) 5) (nth 4 result))
      (nth 4 result)
      ""))
  (if (and (listp result) (>= (length result) 5))
    (list (nth 0 result) (nth 1 result) (nth 2 result) (nth 3 result)
      (if (= detail "") item (strcat detail "||" item)))
    (list nil '() nil nil item)))

(defun cx:gr-fresh-verified-hit-attempt
  (entity segment offset expected-style / result detail)
  (setq cx:*gr-require-graphical-hit* T
        cx:*gr-last-graphical-hit-detail* "UNSET")
  (setq result
    (vl-catch-all-apply 'cx:ss-run-fresh-exclusive-retry
      (list entity segment offset expected-style nil)))
  (setq cx:*gr-require-graphical-hit* nil
        detail
          (strcat "GRAPHICAL_HIT_GATE{"
                  cx:*gr-last-graphical-hit-detail* "}"))
  (if (vl-catch-all-error-p result)
    (list nil '() nil nil
      (strcat detail ",error=" (vl-catch-all-error-message result)))
    (cx:gr-append-result-detail result detail)))

;; Override only the ARC dispatcher.  The LINE path remains V6.
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
      (if (= (length (cadr result)) 0)
        (progn
          (setq result
            (cx:gr-fresh-verified-hit-attempt
              entity segment offset expected-style))
          (setq history
            (cx:gr-add-history history
              "FRESH_BROAD_VERIFIED_GRAPHIC_HIT_SAME_SIDE" result))))
      (if (= (length (cadr result)) 0)
        (progn
          (setq result
            (cx:gr-fresh-verified-hit-attempt
              entity segment (- offset) expected-style))
          (setq history
            (cx:gr-add-history history
              "FRESH_BROAD_VERIFIED_GRAPHIC_HIT_OPPOSITE_SIDE" result))))
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

(princ)
