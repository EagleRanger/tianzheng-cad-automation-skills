(vl-load-com)

;; V9 generic recovery route.
;; The complete runtime source polyline is copied at its original WCS position.
;; The source is hidden only while TDIMARC selects the coincident copy.  Neither
;; the helper nor the native candidate is translated, and UCS is never changed.

(defun cx:tw9-visible (object / value)
  (setq value (vl-catch-all-apply 'vlax-get-property (list object 'Visible)))
  (if (vl-catch-all-error-p value) :vlax-true value))

(defun cx:tw9-set-visible (object value)
  (not
    (vl-catch-all-error-p
      (vl-catch-all-apply 'vlax-put-property (list object 'Visible value)))))

(defun cx:tw9-delete (object)
  (not
    (vl-catch-all-error-p
      (vl-catch-all-apply 'vla-Delete (list object)))))

(defun cx:tw9-attempt
  (entity segment expected-style point audit-offset
    / source source-visible helper helper-entity pick geometry confirm-wcs
      before call-result idle helper-deleted after added valid placement
      handle accepted)
  (setq source (vlax-ename->vla-object entity)
        source-visible (cx:tw9-visible source)
        helper (vl-catch-all-apply 'vla-Copy (list source)))
  (if (vl-catch-all-error-p helper)
    (list nil '()
      (list 0 "TRUE_WCS_FULL_POLYLINE_COPY_FAILED" 0.0 audit-offset 1e99 0)
      nil)
    (progn
      (setq helper-entity (vlax-vla-object->ename helper)
            pick (vlax-curve-getPointAtParam helper-entity (+ segment 0.50))
            geometry (cx:ups-arc-geometry helper-entity segment)
            confirm-wcs
              (if (and (listp geometry) (= (car geometry) "PASS"))
                (nth 3 geometry) nil)
            before (cx:fb-native-handles))
      (cx:tw9-set-visible source :vlax-false)
      (setq call-result
        (if (and pick confirm-wcs)
          (cx:gm1-staged-tdimarc pick confirm-wcs point)
          nil))
      (cx:tw9-set-visible source source-visible)
      (setq idle (= (getvar "CMDNAMES") "")
            helper-deleted (if idle (cx:tw9-delete helper) nil)
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
                "|BORN_ANGLE_TRUE_WCS_FULL_POLYLINE_V9{"
                "fraction=0.50"
                ",source_hidden_during_pick=YES"
                ",helper_wcs_translation_count=0"
                ",candidate_back_translation_count=0"
                ",transformby_count=0"
                ",ucs_mutation_count=0"
                ",helper_deleted=" (if helper-deleted "YES" "NO")
                ",post_cleanup_survivor=" (if accepted "YES" "NO")
                ",born_style=" (cx:asv4-style handle)
                ",style_write=0"
                "," (cx:asv4-placement-vector placement) "}"))
      (list call-result added placement accepted))))

(defun cx:ha1-create-candidate
  (entity segment expected-style ignored-pick point audit-offset)
  (cx:tw9-attempt entity segment expected-style point audit-offset))

(princ)
