(vl-load-com)

;; Validation-only source-serial adapter for the frozen TDIMARC V2 kernel.
;; The dispatcher loads a staged copy of the frozen kernel without its final
;; autorun call.  In that staged copy, only the four wrapped DEFUN declarations
;; are deterministically renamed to cx:ss-v2-*.  Calls inside the frozen core
;; remain unchanged and therefore reach the wrappers below.  This avoids
;; unsupported function-cell introspection while keeping the verified per-arc
;; TDIMARC command sequence byte-for-byte unchanged in the protected source.
;; This adapter only makes one authorised source polyline visible at a time so
;; overlapping blue geometry cannot win Tianzheng point picking.

(setq cx:*ss-batch-entities* '()
      cx:*ss-current-entity* nil)

(defun cx:ss-zoom-segment (entity segment / p0 pm p1 xs ys margin result)
  ;; Fast path keeps one zoom per source.  Only after Tianzheng creates no
  ;; native candidate do we narrow the selection aperture to the exact arc and
  ;; replay the unchanged verified per-arc kernel once.  This handles crowded
  ;; closing/short arcs without slowing every successful segment.
  (setq p0 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity segment))
        pm (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (+ segment 0.5)))
        p1 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (1+ segment)))
        margin 0.50)
  (if (or (vl-catch-all-error-p p0) (null p0)
          (vl-catch-all-error-p pm) (null pm)
          (vl-catch-all-error-p p1) (null p1))
    nil
    (progn
      (setq xs (list (car p0) (car pm) (car p1))
            ys (list (cadr p0) (cadr pm) (cadr p1))
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

(defun cx:ss-restore-current-source (/)
  (if (and (boundp 'cx:*fb-visibility*) cx:*fb-visibility*)
    (cx:fb-restore-visibility cx:*fb-visibility*))
  (setq cx:*fb-visibility* '()
        cx:*ss-current-entity* nil)
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
                    ;; Store every state before mutation so the frozen runtime
                    ;; error handler can restore the drawing on any later fault.
                    (setq snapshot (cons (list object visible) snapshot)
                          cx:*fb-visibility* snapshot)
                    (if (eq item entity) (setq target-object object))
                    (setq result
                      (vl-catch-all-apply 'vla-put-Visible
                        (list object (if (eq item entity) :vlax-true :vlax-false))))
                    (if (vl-catch-all-error-p result) (setq ok nil)))))))))
      (if ok
        (progn
          (setq cx:*ss-current-entity* entity)
          ;; The frozen kernel zoomed this task while the next source was still
          ;; hidden by the serial adapter.  T20 then retained the previous
          ;; source in its point-pick cache after several source transitions.
          ;; Reframe the newly visible source once, before its first arc, so
          ;; the existing per-arc TDIMARC sequence receives a live selectable
          ;; entity without adding a mouse or prompt-level workaround.
          (if target-object (cx:fb-zoom-object target-object 3.0))
          (vl-catch-all-apply 'command-s (list "_.REGEN"))
          (and (= (getvar "CMDNAMES") "")
               (or (= (getvar "CMDACTIVE") 0) (= (getvar "CMDACTIVE") 4))))
        (progn
          (cx:ss-restore-current-source)
          nil)))))

(defun cx:fb-isolate-entities (entities / result)
  (setq cx:*ss-batch-entities* entities
        cx:*ss-current-entity* nil
        cx:*fb-visibility* '())
  (cx:ss-v2-isolate-entities entities))

(defun cx:fb-run-one (entity segment offset expected-style / result)
  (if (cx:ss-switch-source entity)
    (progn
      (setq result (cx:ss-v2-run-one entity segment offset expected-style))
      (if (and (= (length (cadr result)) 0)
               (cx:ss-zoom-segment entity segment))
        (setq result (cx:ss-v2-run-one entity segment offset expected-style)))
      result)
    (list nil '() nil nil "SOURCE_SERIAL_VISIBILITY_SWITCH_FAILED")))

(defun cx:fb-run-line (entity segment offset / result)
  (if (cx:ss-switch-source entity)
    (cx:ss-v2-run-line entity segment offset)
    (list nil '() nil nil "SOURCE_SERIAL_VISIBILITY_SWITCH_FAILED")))

(defun cx:fb-unisolate-objects (/ result)
  (cx:ss-restore-current-source)
  (cx:ss-v2-unisolate-objects))

(c:CXTDIMARCFULLBATCH)
