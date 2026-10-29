(vl-load-com)

;; V10 keeps the verified true-WCS helper route and makes only its exceptional
;; no-candidate source pick adaptive.  Fractions are normalized arc parameters;
;; no drawing handle, coordinate, segment key, bbox or object count is used.

(defun cx:tw10-visible (object / value)
  (setq value (vl-catch-all-apply 'vlax-get-property (list object 'Visible)))
  (if (vl-catch-all-error-p value) :vlax-true value))

(defun cx:tw10-set-visible (object value)
  (not
    (vl-catch-all-error-p
      (vl-catch-all-apply 'vlax-put-property (list object 'Visible value)))))

(defun cx:tw10-delete (object)
  (not
    (vl-catch-all-error-p
      (vl-catch-all-apply 'vla-Delete (list object)))))

(defun cx:tw10-promotable-p
  (result expected-style / added placement grips handle candidate)
  (setq added
          (if (and (listp result) (> (length result) 1))
            (cadr result) '())
        placement
          (if (and (listp result) (> (length result) 2))
            (nth 2 result) nil)
        grips
          (if (and (listp placement) (> (length placement) 5)
                   (numberp (nth 5 placement)))
            (fix (nth 5 placement)) 0)
        handle (if (= (length added) 1) (car added) "")
        candidate
          (if (and (/= handle "") (handent handle) (entget (handent handle)))
            (vlax-ename->vla-object (handent handle)) nil))
  (and candidate
       (= (vla-get-ObjectName candidate) "TDbDimension2")
       (= (vla-get-Layer candidate) "PUB_DIM")
       (= (cx:fb-safe-property candidate 'DimStyle) expected-style)
       (= grips 5)
       (= (getvar "CMDNAMES") "")))

(defun cx:tw10-attempt
  (entity segment expected-style point audit-offset fraction probe-index
    / source source-visible helper helper-entity pick geometry confirm-wcs
      before call-result idle helper-deleted after added valid placement
      handle accepted)
  (setq source (vlax-ename->vla-object entity)
        source-visible (cx:tw10-visible source)
        helper (vl-catch-all-apply 'vla-Copy (list source)))
  (if (vl-catch-all-error-p helper)
    (list nil '()
      (list 0 "TRUE_WCS_FULL_POLYLINE_COPY_FAILED" 0.0 audit-offset 1e99 0)
      nil)
    (progn
      (setq helper-entity (vlax-vla-object->ename helper)
            pick (vlax-curve-getPointAtParam helper-entity (+ segment fraction))
            geometry (cx:ups-arc-geometry helper-entity segment)
            confirm-wcs
              (if (and (listp geometry) (= (car geometry) "PASS"))
                (nth 3 geometry) nil)
            before (cx:fb-native-handles))
      (cx:tw10-set-visible source :vlax-false)
      (setq call-result
        (if (and pick confirm-wcs)
          (cx:gm1-staged-tdimarc pick confirm-wcs point)
          nil))
      (cx:tw10-set-visible source source-visible)
      (setq idle (= (getvar "CMDNAMES") "")
            helper-deleted (if idle (cx:tw10-delete helper) nil)
            after (cx:fb-native-handles)
            added (cx:fb-difference after before)
            valid
              (and idle helper-deleted
                   (cx:fb-created-object-valid-p added expected-style))
            handle (if (= (length added) 1) (car added) "")
            placement
              (if valid
                (cx:pg-audit entity "ARC" segment handle audit-offset)
                (list 0 "TRUE_WCS_POST_CLEANUP_INVALID"
                  0.0 audit-offset 1e99 0))
            accepted (and valid (cx:pg-audit-normal-p placement))
            cx:*sp2-last-trace*
              (strcat cx:*sp2-last-trace*
                "|BORN_ANGLE_TRUE_WCS_ADAPTIVE_V10{"
                "probe_index=" (itoa probe-index)
                ",fraction=" (rtos fraction 2 2)
                ",source_hidden_during_pick=YES"
                ",helper_wcs_translation_count=0"
                ",candidate_back_translation_count=0"
                ",transformby_count=0"
                ",ucs_mutation_count=0"
                ",helper_deleted=" (if helper-deleted "YES" "NO")
                ",native_signature="
                  (if (cx:tw10-promotable-p
                        (list call-result added placement accepted)
                        expected-style)
                    "YES" "NO")
                ",post_cleanup_rank2=" (if accepted "YES" "NO")
                ",born_style=" (cx:asv4-style handle)
                ",style_write=0"
                "," (cx:asv4-placement-vector placement) "}"))
      (list call-result added placement accepted))))

(defun cx:ha1-create-candidate
  (entity segment expected-style ignored-pick point audit-offset
    / fractions probe-index result selected added)
  (setq fractions '(0.50 0.35)
        probe-index 0
        result nil
        selected nil)
  (while (and fractions (null selected))
    (setq probe-index (1+ probe-index)
          result
            (cx:tw10-attempt entity segment expected-style point audit-offset
              (car fractions) probe-index))
    (if (or (nth 3 result) (cx:tw10-promotable-p result expected-style))
      (setq selected result)
      (progn
        (setq added (if (and (listp result) (> (length result) 1))
                      (cadr result) '()))
        (if added (cx:cs-delete-live-handles added))))
    (setq fractions (cdr fractions)))
  (if selected
    selected
    (if result
      (list (car result) '() (nth 2 result) nil)
      (list nil '()
        (list 0 "TRUE_WCS_ADAPTIVE_NO_RESULT" 0.0 audit-offset 1e99 0)
        nil))))

(princ)
