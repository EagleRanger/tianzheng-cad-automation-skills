(vl-load-com)

;; Validation-only V4 source-serial adapter for the frozen typed V2 kernel.
;; Fast path: exactly one authorised source polyline is selectable.
;; Retry path: after the frozen kernel returns no candidate, temporarily hide
;; every other visible model-space object, narrow the view to the exact
;; segment, and replay the same verified native command sequence once.

(setq cx:*ss-batch-entities* '()
      cx:*ss-current-entity* nil
      cx:*ss-current-count* 0
      cx:*ss-straight-bulge-tolerance* 1e-8)

;; Preserve the frozen kernel while correcting only native type dispatch for
;; numerically nonzero bulges whose included angle is geometrically straight.
;; TDimMP still receives the original polyline segment endpoints; no helper
;; line, source edit, explode, or reconstruction is introduced.
(defun cx:fb-arc-indices (entity / data result vertex-index item end-param segment-count)
  (setq data (entget entity) result '() vertex-index -1)
  (setq end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list entity))
        segment-count (if (vl-catch-all-error-p end-param) 0 (fix end-param)))
  (foreach item data
    (cond
      ((= (car item) 10) (setq vertex-index (1+ vertex-index)))
      ((and (= (car item) 42) (>= vertex-index 0) (< vertex-index segment-count)
            (> (abs (cdr item)) cx:*ss-straight-bulge-tolerance*))
        (setq result (cons vertex-index result)))))
  (reverse result))

(defun cx:ss-append-valid-point (result points)
  (if (and result (not (vl-catch-all-error-p result)))
    (append points (list result))
    points))

(defun cx:ss-zoom-segment (entity segment offset / end-param first-segment last-segment
    current p0 pm p1 points xs ys margin result)
  ;; Keep roughly five source segments in view and always include a margin
  ;; larger than the native placement offset.  Invalid samples are skipped so
  ;; a valid final/closed segment cannot fail only because one endpoint query
  ;; returns nil.
  (setq end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list entity)))
  (if (or (vl-catch-all-error-p end-param) (null end-param))
    nil
    (progn
      (setq first-segment (max 0 (- segment 2))
            last-segment (min (1- (fix end-param)) (+ segment 2))
            current first-segment
            points '())
      (while (<= current last-segment)
        (setq p0 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity current))
              pm (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (+ current 0.5)))
              p1 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (1+ current)))
              points (cx:ss-append-valid-point p0 points)
              points (cx:ss-append-valid-point pm points)
              points (cx:ss-append-valid-point p1 points)
              current (1+ current)))
      (if (null points)
        nil
        (progn
          (setq xs (mapcar 'car points)
                ys (mapcar 'cadr points)
                margin (max 5.0 (+ (abs offset) 2.0))
                result
                  (vl-catch-all-apply 'command-s
                    (list "_.ZOOM" "_W"
                      (trans (list (- (apply 'min xs) margin)
                                   (- (apply 'min ys) margin) 0.0) 0 1)
                      (trans (list (+ (apply 'max xs) margin)
                                   (+ (apply 'max ys) margin) 0.0) 0 1))))
          (and (not (vl-catch-all-error-p result))
               (= (getvar "CMDNAMES") "")
               (or (= (getvar "CMDACTIVE") 0) (= (getvar "CMDACTIVE") 4))))))))
(defun cx:ss-zoom-segment-tight (entity segment / p0 pm p1 points xs ys margin result)
  ;; Broad context remains the default.  A final failed segment gets one
  ;; tighter deterministic view because nearby short arcs can collapse into
  ;; the same screen pick tolerance even when the WCS point is exact.
  (setq p0 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity segment))
        pm (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (+ segment 0.5)))
        p1 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (1+ segment)))
        points '()
        points (cx:ss-append-valid-point p0 points)
        points (cx:ss-append-valid-point pm points)
        points (cx:ss-append-valid-point p1 points)
        margin 0.50)
  (if (< (length points) 2)
    nil
    (progn
      (setq xs (mapcar 'car points)
            ys (mapcar 'cadr points)
            result
              (vl-catch-all-apply 'command-s
                (list "_.ZOOM" "_W"
                  (trans (list (- (apply 'min xs) margin)
                               (- (apply 'min ys) margin) 0.0) 0 1)
                  (trans (list (+ (apply 'max xs) margin)
                               (+ (apply 'max ys) margin) 0.0) 0 1))))
      (and (not (vl-catch-all-error-p result))
           (= (getvar "CMDNAMES") "")
           (or (= (getvar "CMDACTIVE") 0) (= (getvar "CMDACTIVE") 4))))))
(defun cx:ss-hide-other-visible (source-entity / doc space count index item visible hidden source-handle)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        count (vla-get-Count space)
        index 0 hidden '()
        source-handle (vla-get-Handle (vlax-ename->vla-object source-entity)))
  (repeat count
    (setq item (vl-catch-all-apply 'vla-Item (list space index)))
    (if (and (not (vl-catch-all-error-p item)) item
             (/= (vla-get-Handle item) source-handle))
      (progn
        (setq visible (vl-catch-all-apply 'vla-get-Visible (list item)))
        (if (and (not (vl-catch-all-error-p visible)) (= visible :vlax-true))
          (progn
            (vl-catch-all-apply 'vla-put-Visible (list item :vlax-false))
            (setq hidden (cons item hidden))))))
    (setq index (1+ index)))
  hidden)

(defun cx:ss-restore-visible (objects / item)
  (foreach item objects
    (if (and item (not (vlax-erased-p item)))
      (vl-catch-all-apply 'vla-put-Visible (list item :vlax-true)))))

(defun cx:ss-restore-current-source (/)
  (if (and (boundp 'cx:*fb-visibility*) cx:*fb-visibility*)
    (cx:fb-restore-visibility cx:*fb-visibility*))
  (setq cx:*fb-visibility* '()
        cx:*ss-current-entity* nil
        cx:*ss-current-count* 0)
  T)

(defun cx:ss-switch-source (entity / item object target-object visible result ok snapshot)
  (if (eq entity cx:*ss-current-entity*)
    T
    (progn
      (cx:ss-restore-current-source)
      (setq snapshot '() ok T)
      (foreach item cx:*ss-batch-entities*
        (if ok
          (progn
            (setq object (vl-catch-all-apply 'vlax-ename->vla-object (list item)))
            (if (or (vl-catch-all-error-p object) (null object))
              (setq ok nil)
              (progn
                (setq visible (vl-catch-all-apply 'vla-get-Visible (list object)))
                (if (vl-catch-all-error-p visible)
                  (setq ok nil)
                  (progn
                    (setq snapshot (cons (list object visible) snapshot)
                          cx:*fb-visibility* snapshot)
                    (if (eq item entity) (setq target-object object))
                    (setq result
                      (vl-catch-all-apply 'vla-put-Visible
                        (list object (if (eq item entity) :vlax-true :vlax-false))))
                    (if (vl-catch-all-error-p result) (setq ok nil)))))))))
      (if ok
        (progn
          (setq cx:*ss-current-entity* entity
                cx:*ss-current-count* 0)
          (if target-object (cx:fb-zoom-object target-object 3.0))
          (vl-catch-all-apply 'command-s (list "_.REGEN"))
          (and (= (getvar "CMDNAMES") "")
               (or (= (getvar "CMDACTIVE") 0) (= (getvar "CMDACTIVE") 4))))
        (progn (cx:ss-restore-current-source) nil)))))

(defun cx:ss-run-exclusive-retry (entity segment offset expected-style / hidden result)
  (setq hidden (cx:ss-hide-other-visible entity))
  (vl-catch-all-apply 'command-s (list "_.REGEN"))
  (if (cx:ss-zoom-segment entity segment offset)
    (setq result (cx:ss-v2-run-one entity segment offset expected-style))
    (setq result (list nil '() nil nil "EXCLUSIVE_RETRY_ZOOM_FAILED")))
  (cx:ss-restore-visible hidden)
  (vl-catch-all-apply 'command-s (list "_.REGEN"))
  result)

(defun cx:ss-run-tight-exclusive-retry (entity segment offset expected-style / hidden result)
  (setq hidden (cx:ss-hide-other-visible entity))
  (vl-catch-all-apply 'command-s (list "_.REGEN"))
  (if (cx:ss-zoom-segment-tight entity segment)
    (setq result (cx:ss-v2-run-one entity segment offset expected-style))
    (setq result (list nil '() nil nil "TIGHT_EXCLUSIVE_RETRY_ZOOM_FAILED")))
  (cx:ss-restore-visible hidden)
  (vl-catch-all-apply 'command-s (list "_.REGEN"))
  result)

(defun cx:ss-run-fresh-exclusive-retry
  (entity segment offset expected-style tight / hidden zoom-ok result)
  ;; A failed segment must not inherit Tianzheng's previous point-pick cache.
  ;; Rebuild the source visibility state, reframe the requested neighbourhood,
  ;; regenerate, then replay the frozen native command exactly once.
  (cx:ss-restore-current-source)
  (if (not (cx:ss-switch-source entity))
    (list nil '() nil nil "FRESH_RETRY_SOURCE_RESET_FAILED")
    (progn
      (setq hidden (cx:ss-hide-other-visible entity))
      (vl-catch-all-apply 'command-s (list "_.REGEN"))
      (setq zoom-ok
        (if tight
          (cx:ss-zoom-segment-tight entity segment)
          (cx:ss-zoom-segment entity segment offset)))
      (vl-catch-all-apply 'command-s (list "_.REGEN"))
      (if zoom-ok
        (setq result (cx:ss-v2-run-one entity segment offset expected-style))
        (setq result
          (list nil '() nil nil
            (if tight "FRESH_TIGHT_RETRY_ZOOM_FAILED" "FRESH_BROAD_RETRY_ZOOM_FAILED"))))
      (cx:ss-restore-visible hidden)
      (vl-catch-all-apply 'command-s (list "_.REGEN"))
      result)))
(defun cx:fb-isolate-entities (entities / result)
  (setq cx:*ss-batch-entities* entities
        cx:*ss-current-entity* nil
        cx:*ss-current-count* 0
        cx:*fb-visibility* '())
  (cx:ss-v2-isolate-entities entities))

(defun cx:fb-run-one (entity segment offset expected-style / result)
  (if (cx:ss-switch-source entity)
    (progn
      ;; Real T20 V10 evidence shows the point-pick cache can become stale on
      ;; the third consecutive segment of the same polyline.  Reframe inside
      ;; the same governed batch after every two accepted segments; this
      ;; reproduces the proven pair-chunk reset without dozens of external
      ;; command injections.
      (if (>= cx:*ss-current-count* 2)
        (progn
          (cx:ss-zoom-segment entity segment offset)
          (vl-catch-all-apply 'command-s (list "_.REGEN"))
          (setq cx:*ss-current-count* 0)))
      (setq result (cx:ss-v2-run-one entity segment offset expected-style))
      (if (and (= (length (cadr result)) 0)
               (cx:ss-zoom-segment entity segment offset))
        (setq result (cx:ss-v2-run-one entity segment offset expected-style)))
      (if (= (length (cadr result)) 0)
        (setq result (cx:ss-run-exclusive-retry entity segment offset expected-style)))
      (if (= (length (cadr result)) 1)
        (setq cx:*ss-current-count* (1+ cx:*ss-current-count*)))
      result)
    (list nil '() nil nil "SOURCE_SERIAL_VISIBILITY_SWITCH_FAILED")))

(defun cx:fb-run-line (entity segment offset / result)
  (if (cx:ss-switch-source entity)
    (progn
      (if (>= cx:*ss-current-count* 2)
        (progn
          (cx:ss-zoom-segment entity segment offset)
          (vl-catch-all-apply 'command-s (list "_.REGEN"))
          (setq cx:*ss-current-count* 0)))
      (setq result (cx:ss-v2-run-line entity segment offset))
      (if (= (length (cadr result)) 1)
        (setq cx:*ss-current-count* (1+ cx:*ss-current-count*)))
      result)
    (list nil '() nil nil "SOURCE_SERIAL_VISIBILITY_SWITCH_FAILED")))

(defun cx:fb-unisolate-objects (/ result)
  (cx:ss-restore-current-source)
  (cx:ss-v2-unisolate-objects))

(c:CXTDIMARCFULLBATCH)
