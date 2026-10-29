(vl-load-com)

;; P3 validation-only repair adapter.  It does not replace or modify the
;; frozen TDIMARC generation workflow.  It creates at most one candidate from
;; a data-only task spec, or deletes only explicitly listed candidate/obsolete
;; handles.  Source association is accepted externally from native grip data.

(if (not (boundp 'cx:*full-batch-tasks*)) (setq cx:*full-batch-tasks* '()))
(if (not (boundp 'cx:*full-batch-cleanup-handles*))
  (setq cx:*full-batch-cleanup-handles* '()))
(if (not (boundp 'cx:*full-batch-fractions*))
  (setq cx:*full-batch-fractions* '(0.50)))
(if (not (boundp 'cx:*source-repair-zoom-margin*))
  (setq cx:*source-repair-zoom-margin* 0.50))
(if (not (boundp 'cx:*source-repair-use-temp-arc*))
  (setq cx:*source-repair-use-temp-arc* nil))

(defun cx:sr-write-lines (path lines / temporary file line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq file (open temporary "w"))
  (foreach line lines (write-line line file))
  (close file)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:sr-native-handles (/ doc space count index item name result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc) count (vla-get-Count space)
        index 0 result '())
  (repeat count
    (setq item (vl-catch-all-apply 'vla-Item (list space index)))
    (if (not (vl-catch-all-error-p item))
      (progn
        (setq name (vl-catch-all-apply 'vla-get-ObjectName (list item)))
        (if (and (not (vl-catch-all-error-p name)) (= name "TDbDimension2"))
          (setq result (cons (vla-get-Handle item) result)))))
    (setq index (1+ index)))
  result)

(defun cx:sr-difference (after before / result item)
  (setq result '())
  (foreach item after (if (not (member item before)) (setq result (cons item result))))
  (reverse result))

(defun cx:sr-join (items / result item)
  (setq result "")
  (foreach item items
    (setq result (if (= result "") item (strcat result "," item))))
  result)

(defun cx:sr-delete-handles (handles / handle entity deleted)
  ;; ENTDEL toggles an erased entity back to live when called twice.  Treat an
  ;; already-erased or absent exact handle as settled, and call ENTDEL only
  ;; when ENTGET proves that the entity is currently live.
  (setq deleted '())
  (foreach handle handles
    (setq entity (handent handle))
    (cond
      ((and entity (entget entity))
        (if (entdel entity) (setq deleted (cons handle deleted))))
      (T (setq deleted (cons handle deleted)))))
  (reverse deleted))

(defun cx:sr-safe-property (object property / result)
  (setq result (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (vl-catch-all-error-p result) "" (vl-princ-to-string result)))

(defun cx:sr-segment-points
  (entity segment fraction offset / parameter pick-result deriv-result
    pick-wcs deriv magnitude normal side-wcs)
  (setq parameter (+ segment fraction)
        pick-result (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity parameter))
        deriv-result (vl-catch-all-apply 'vlax-curve-getFirstDeriv (list entity parameter)))
  (if (not (vl-catch-all-error-p pick-result)) (setq pick-wcs pick-result))
  (if (not (vl-catch-all-error-p deriv-result)) (setq deriv deriv-result))
  (setq magnitude (if deriv (distance '(0.0 0.0 0.0) deriv) 0.0))
  (if (and pick-wcs (> magnitude 1e-9))
    (progn
      (setq normal (list (/ (- (cadr deriv)) magnitude) (/ (car deriv) magnitude) 0.0)
            side-wcs (mapcar '+ pick-wcs (mapcar '(lambda (value) (* value offset)) normal)))
      (list (trans pick-wcs 0 1) (trans side-wcs 0 1)))
    nil))

(defun cx:sr-angle-0-2pi (value / full)
  (setq full (* 2.0 pi))
  (while (< value 0.0) (setq value (+ value full)))
  (while (>= value full) (setq value (- value full)))
  value)

(defun cx:sr-ccw-delta (from to)
  (cx:sr-angle-0-2pi (- to from)))

(defun cx:sr-temp-arc-from-segment
  (entity segment / original-pm shift back source-object temporary-object temporary move-result)
  ;; Copy the complete source polyline, including every adjacent segment and
  ;; object property, to an empty coordinate neighbourhood.  Synthetic ARC or
  ;; short-chain substitutes are rejected because T20 classifies them as arc-
  ;; length targets instead of the verified polyline-segment angle target.
  (setq original-pm (vlax-curve-getPointAtParam entity (+ segment 0.5))
        shift (list (- (car original-pm)) (- (cadr original-pm)) 0.0)
        back (list (car original-pm) (cadr original-pm) 0.0)
        source-object (vlax-ename->vla-object entity)
        temporary-object (vl-catch-all-apply 'vla-Copy (list source-object)))
  (if (not (vl-catch-all-error-p temporary-object))
    (progn
      (setq move-result
        (vl-catch-all-apply 'vla-Move
          (list temporary-object (vlax-3d-point '(0.0 0.0 0.0)) (vlax-3d-point shift))))
      (if (not (vl-catch-all-error-p move-result))
        (setq temporary (vlax-vla-object->ename temporary-object)))))
  (if temporary (list temporary shift back) nil))

(defun cx:sr-move-handles (handles displacement / handle entity object result)
  (setq result T)
  (foreach handle handles
    (setq entity (handent handle))
    (if entity
      (progn
        (setq object (vlax-ename->vla-object entity))
        (if (vl-catch-all-error-p
              (vl-catch-all-apply 'vla-Move
                (list object (vlax-3d-point '(0.0 0.0 0.0)) (vlax-3d-point displacement))))
          (setq result nil)))
      (setq result nil)))
  result)

(defun cx:sr-object-info (handle / entity object)
  (setq entity (handent handle))
  (if entity
    (progn
      (setq object (vl-catch-all-apply 'vlax-ename->vla-object (list entity)))
      (if (not (vl-catch-all-error-p object))
        (list (vla-get-ObjectName object) (vla-get-Layer object)
              (cx:sr-safe-property object 'DimStyle))
        '("" "" "")))
    '("" "" "")))

(defun cx:sr-hide-other-curves (source-entity / doc space count index item name visible hidden source-handle)
  ;; Object isolation is not sufficient for T20's cached curve picker.  Native
  ;; Tianzheng dimensions and proxy objects can also participate in hit testing,
  ;; so temporarily hide every other visible model-space object.  Remember the
  ;; exact object list and restore only those objects afterwards.
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        count (vla-get-Count space)
        index 0 hidden '()
        source-handle (vla-get-Handle (vlax-ename->vla-object source-entity)))
  (repeat count
    (setq item (vl-catch-all-apply 'vla-Item (list space index)))
    (if (not (vl-catch-all-error-p item))
      (progn
        (setq name (vl-catch-all-apply 'vla-get-ObjectName (list item)))
        (if (and (not (vl-catch-all-error-p name))
                 (/= (vla-get-Handle item) source-handle))
          (progn
            (setq visible (vl-catch-all-apply 'vla-get-Visible (list item)))
            (if (and (not (vl-catch-all-error-p visible)) (= visible :vlax-true))
              (progn
                (vl-catch-all-apply 'vla-put-Visible (list item :vlax-false))
                (setq hidden (cons item hidden))))))))
    (setq index (1+ index)))
  hidden)

(defun cx:sr-restore-visible (objects / item)
  (foreach item objects
    (if (and item (not (vlax-erased-p item)))
      (vl-catch-all-apply 'vla-put-Visible (list item :vlax-true)))))

(defun cx:sr-zoom-object (object offset / minimum maximum min-list max-list margin)
  (vla-GetBoundingBox object 'minimum 'maximum)
  (setq min-list (vlax-safearray->list minimum)
        max-list (vlax-safearray->list maximum)
        margin (+ 5.0 (* 2.0 (abs offset))))
  (vl-catch-all-apply 'command-s
    (list "_.ZOOM" "_W"
      (trans (list (- (car min-list) margin) (- (cadr min-list) margin) 0.0) 0 1)
      (trans (list (+ (car max-list) margin) (+ (cadr max-list) margin) 0.0) 0 1))))

(defun cx:sr-zoom-segment (entity segment offset / p0 pm p1 xs ys margin)
  (setq p0 (vlax-curve-getPointAtParam entity segment)
        pm (vlax-curve-getPointAtParam entity (+ segment 0.5))
        p1 (vlax-curve-getPointAtParam entity (1+ segment))
        xs (list (car p0) (car pm) (car p1))
        ys (list (cadr p0) (cadr pm) (cadr p1))
        ;; Keep the on-screen selection aperture small enough to distinguish a
        ;; short arc from its adjacent segments.  The scripted placement point
        ;; may lie outside this selection view; TDIMARC still receives its
        ;; exact model coordinate as the third prompt value.
        margin cx:*source-repair-zoom-margin*)
  (vl-catch-all-apply 'command-s
    (list "_.ZOOM" "_W"
      (trans (list (- (apply 'min xs) margin) (- (apply 'min ys) margin) 0.0) 0 1)
      (trans (list (+ (apply 'max xs) margin) (+ (apply 'max ys) margin) 0.0) 0 1))))

(defun c:CXTDIMARCSOURCEREPAIR
  (/ started task source-handle segment-item segment offset group fraction entity
    work-entity temp-data temp-arc temp-shift temp-back hidden-curves
    points pick side before after added call-result info status detail deleted elapsed
    summary details)
  (setq started (getvar "MILLISECS") status "FAIL" detail "UNINITIALIZED"
        added '() deleted '()
        details (list "GROUP\tSOURCE_HANDLE\tSEGMENT_TYPE\tSEGMENT_INDEX\tSTATUS\tADDED_HANDLE\tOBJECT_NAME\tLAYER\tDIM_STYLE\tPICK_X\tPICK_Y\tSIDE_X\tSIDE_Y\tCMDACTIVE\tCMDNAMES\tATTEMPTS"))
  (cond
    ((and (= (length cx:*full-batch-tasks*) 0) cx:*full-batch-cleanup-handles*)
      (setq deleted (cx:sr-delete-handles cx:*full-batch-cleanup-handles*)
            status (if (= (length deleted) (length cx:*full-batch-cleanup-handles*)) "PASS" "FAIL")
            detail (if (= status "PASS") "EXACT_HANDLES_DELETED" "EXACT_HANDLE_DELETE_FAILED")))
    ((/= (length cx:*full-batch-tasks*) 1)
      (setq detail "REPAIR_REQUIRES_EXACTLY_ONE_TASK"))
    (T
      (setq task (car cx:*full-batch-tasks*) source-handle (car task)
            segment-item (car (cadr task)) offset (nth 2 task) group (nth 3 task)
            segment (cadr segment-item) fraction (car cx:*full-batch-fractions*)
            entity (handent source-handle))
      (if (and entity (= (length (cadr task)) 1) (= (strcase (car segment-item)) "ARC"))
        (progn
          (setq work-entity entity)
          (if cx:*source-repair-use-temp-arc*
            (progn
              (setq temp-data (cx:sr-temp-arc-from-segment entity segment))
              (if temp-data
                (setq temp-arc (car temp-data) temp-shift (cadr temp-data)
                      temp-back (caddr temp-data) work-entity temp-arc))))
          (if (and cx:*source-repair-use-temp-arc* (not temp-arc))
            (setq detail "TEMP_ARC_CREATE_FAILED")
            (progn
          (setq hidden-curves (cx:sr-hide-other-curves work-entity))
          (vl-catch-all-apply 'command-s (list "_.REGEN"))
          (cx:sr-zoom-segment work-entity segment offset)
          (setq points (cx:sr-segment-points entity segment fraction offset))
          (if (and points temp-shift)
            (setq points
              (list (trans (mapcar '+ (trans (car points) 1 0) temp-shift) 0 1)
                    (trans (mapcar '+ (trans (cadr points) 1 0) temp-shift) 0 1))))
          (if points
            (progn
              (setq pick (car points) side (cadr points) before (cx:sr-native-handles)
                    call-result (vl-catch-all-apply 'command-s (list "TDIMARC" pick pick side ""))
                    after (cx:sr-native-handles) added (cx:sr-difference after before))
              (if (= (length added) 1)
                (progn
                  (setq info (cx:sr-object-info (car added)))
                  (if (and (= (car info) "TDbDimension2") (= (cadr info) "PUB_DIM")
                           (= (caddr info) "_TCH_ARROW"))
                    (if (or (not temp-back) (cx:sr-move-handles added temp-back))
                      (setq status "PASS" detail "CANDIDATE_CREATED_PENDING_ENDPOINT_AUDIT")
                      (progn
                        (setq detail "CANDIDATE_TRANSLATION_FAILED")
                        (cx:sr-delete-handles added)
                        (setq added '())))
                    (progn
                      (setq detail
                        (strcat "WRONG_NATIVE_STYLE_ROLLED_BACK:"
                          (car info) ":" (cadr info) ":" (caddr info)))
                      (cx:sr-delete-handles added)
                      (setq added '()))))
                (progn (if added (cx:sr-delete-handles added)) (setq added '() detail "CANDIDATE_COUNT_INVALID"))))
            (setq detail "SEGMENT_POINT_FAILED"))
          (cx:sr-restore-visible hidden-curves)
          (if (and temp-arc (entget temp-arc)) (entdel temp-arc))
          (vl-catch-all-apply 'command-s (list "_.REGEN")))))
        (setq detail "SOURCE_OR_TASK_INVALID"))))
  (if (and (= status "PASS") added)
    (setq details (append details
      (list (strcat group "\t" source-handle "\tARC\t" (itoa segment) "\tPASS\t"
        (car added) "\t" (car info) "\t" (cadr info) "\t" (caddr info) "\t"
        (rtos (car pick) 2 8) "\t" (rtos (cadr pick) 2 8) "\t"
        (rtos (car side) 2 8) "\t" (rtos (cadr side) 2 8) "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES") "\tfraction=" (rtos fraction 2 2))))))
  (setq elapsed (- (getvar "MILLISECS") started)
        summary (list
          "STATUS\tDETAIL\tTASK_COUNT\tTARGET_SEGMENTS\tSUCCESS_COUNT\tROAD_COUNT\tSHORE_COUNT\tADDED_HANDLES\tFAILED\tCLEANUP_DELETED\tCLEAN_SLATE_DELETED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
          (strcat status "\t" detail "\t" (if task "1" "0") "\t" (if task "1" "0") "\t"
            (if added "1" "0") "\t0\t" (if added "1" "0") "\t"
            (if added (car added) "") "\t\t"
            (cx:sr-join deleted) "\t\t" (itoa elapsed) "\t"
            (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (cx:sr-write-lines cx:*full-batch-details-path* details)
  (cx:sr-write-lines cx:*full-batch-summary-path* summary)
  (princ))

(c:CXTDIMARCSOURCEREPAIR)
