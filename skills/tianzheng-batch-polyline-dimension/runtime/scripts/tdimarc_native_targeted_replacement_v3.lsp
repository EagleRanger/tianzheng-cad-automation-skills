(vl-load-com)

;; Validation-only bounded-N successor for exact arc replacements.
;; It preserves the verified TDIMARC pick-pick-place kernel, but uses one
;; explicit fraction and signed offset per source segment.  It creates and
;; replaces each contract-paired obsolete dimension transactionally: erase one,
;; generate and validate its successor, then continue.  Any failure deletes all
;; new candidates and restores every erased original.  Source association remains
;; an external native-grip gate.

(if (not (boundp 'cx:*full-batch-tasks*)) (setq cx:*full-batch-tasks* '()))
(if (not (boundp 'cx:*full-batch-cleanup-handles*))
  (setq cx:*full-batch-cleanup-handles* '()))
(if (not (boundp 'cx:*full-batch-clean-slate-object-names*))
  (setq cx:*full-batch-clean-slate-object-names* '()))
(if (not (boundp 'cx:*targeted-replacement-layouts*))
  (setq cx:*targeted-replacement-layouts* '()))
(if (not (boundp 'cx:*targeted-replacement-zoom-margin*))
  (setq cx:*targeted-replacement-zoom-margin* 0.50))
(if (not (boundp 'cx:*full-batch-save-on-success*))
  (setq cx:*full-batch-save-on-success* nil))

(setq cx:tr-active-hidden '()
      cx:tr-created '()
      cx:tr-deleted-old '())

(defun cx:tr-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:tr-current-drawing ()
  (cx:tr-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))))

(defun cx:tr-write-lines (path lines / temporary file line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq file (open temporary "w"))
  (foreach line lines (write-line line file))
  (close file)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:tr-native-handles (/ doc space count index item name result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        count (vla-get-Count space)
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

(defun cx:tr-difference (after before / result item)
  (setq result '())
  (foreach item after
    (if (not (member item before)) (setq result (cons item result))))
  (reverse result))

(defun cx:tr-safe-property (object property / result)
  (setq result (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (vl-catch-all-error-p result) "" (vl-princ-to-string result)))

(defun cx:tr-object-info (handle / entity object)
  (setq entity (handent handle))
  (if entity
    (progn
      (setq object (vl-catch-all-apply 'vlax-ename->vla-object (list entity)))
      (if (not (vl-catch-all-error-p object))
        (list (vla-get-ObjectName object)
              (vla-get-Layer object)
              (cx:tr-safe-property object 'DimStyle))
        '("" "" "")))
    '("" "" "")))

(defun cx:tr-delete-handles (handles / handle entity deleted)
  (setq deleted '())
  (foreach handle handles
    (setq entity (handent handle))
    (if (and entity (entget entity) (entdel entity))
      (setq deleted (cons handle deleted))))
  (reverse deleted))

(defun cx:tr-restore-erased (handles / handle entity restored)
  (setq restored '())
  (foreach handle handles
    (setq entity (handent handle))
    (if (and entity (not (entget entity)) (entdel entity))
      (setq restored (cons handle restored))))
  (reverse restored))

(defun cx:tr-polyline-bulges (entity / data result started current pair)
  (setq data (entget entity) result '() started nil current 0.0)
  (foreach pair data
    (cond
      ((= (car pair) 10)
        (if started (setq result (append result (list current))))
        (setq started T current 0.0))
      ((and started (= (car pair) 42)) (setq current (cdr pair)))))
  (if started (setq result (append result (list current))))
  result)

(defun cx:tr-arc-segment-p (entity segment / bulges)
  (setq bulges (cx:tr-polyline-bulges entity))
  (and (>= segment 0) (< segment (length bulges))
       (> (abs (nth segment bulges)) 1e-12)))

(defun cx:tr-segment-points
  (entity segment fraction offset / parameter pick-result deriv-result
    pick-wcs deriv magnitude normal side-wcs)
  (setq parameter (+ segment fraction)
        pick-result (vl-catch-all-apply 'vlax-curve-getPointAtParam
          (list entity parameter))
        deriv-result (vl-catch-all-apply 'vlax-curve-getFirstDeriv
          (list entity parameter)))
  (if (not (vl-catch-all-error-p pick-result)) (setq pick-wcs pick-result))
  (if (not (vl-catch-all-error-p deriv-result)) (setq deriv deriv-result))
  (setq magnitude (if deriv (distance '(0.0 0.0 0.0) deriv) 0.0))
  (if (and pick-wcs (> magnitude 1e-9))
    (progn
      (setq normal (list (/ (- (cadr deriv)) magnitude)
                         (/ (car deriv) magnitude) 0.0)
            side-wcs (mapcar '+ pick-wcs
              (mapcar '(lambda (value) (* value offset)) normal)))
      (list (trans pick-wcs 0 1) (trans side-wcs 0 1)))
    nil))

(defun cx:tr-hide-non-source (source-entity / doc space count index item visible hidden source-handle)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        count (vla-get-Count space)
        index 0 hidden '()
        source-handle (vla-get-Handle (vlax-ename->vla-object source-entity)))
  (repeat count
    (setq item (vl-catch-all-apply 'vla-Item (list space index)))
    (if (and (not (vl-catch-all-error-p item))
             (/= (vla-get-Handle item) source-handle))
      (progn
        (setq visible (vl-catch-all-apply 'vla-get-Visible (list item)))
        (if (and (not (vl-catch-all-error-p visible)) (= visible :vlax-true))
          (progn
            (vl-catch-all-apply 'vla-put-Visible (list item :vlax-false))
            (setq hidden (cons item hidden))))))
    (setq index (1+ index)))
  hidden)

(defun cx:tr-restore-visible (objects / item)
  (foreach item objects
    (if (and item (not (vlax-erased-p item)))
      (vl-catch-all-apply 'vla-put-Visible (list item :vlax-true)))))

(defun cx:tr-zoom-segment (entity segment selection-margin / p0 pm p1 xs ys margin)
  (setq p0 (vlax-curve-getPointAtParam entity segment)
        pm (vlax-curve-getPointAtParam entity (+ segment 0.5))
        p1 (vlax-curve-getPointAtParam entity (1+ segment))
        xs (list (car p0) (car pm) (car p1))
        ys (list (cadr p0) (cadr pm) (cadr p1))
        ;; Selection aperture is part of the verified generation recipe, not a
        ;; universal aesthetic formula.  Final aesthetic offset is handled only
        ;; after native source association has passed.
        margin selection-margin)
  (vl-catch-all-apply 'command-s
    (list "_.ZOOM" "_W"
      (trans (list (- (apply 'min xs) margin)
                   (- (apply 'min ys) margin) 0.0) 0 1)
      (trans (list (+ (apply 'max xs) margin)
                   (+ (apply 'max ys) margin) 0.0) 0 1))))

(defun cx:tr-task-pairs (/ pairs task item)
  (setq pairs '())
  (foreach task cx:*full-batch-tasks*
    (foreach item (cadr task)
      (setq pairs (cons (strcat (strcase (car task)) ":"
        (strcase (car item)) ":" (itoa (cadr item))) pairs))))
  (vl-sort pairs '<))

(defun cx:tr-layout-pairs (/ pairs row)
  (setq pairs '())
  (foreach row cx:*targeted-replacement-layouts*
    (setq pairs (cons (strcat (strcase (car row)) ":ARC:"
      (itoa (cadr row))) pairs)))
  (vl-sort pairs '<))

(defun cx:tr-valid-input-p (/ target-count)
  (setq target-count (length cx:*targeted-replacement-layouts*))
  (and (> target-count 0) (<= target-count 64)
       (vl-every
         '(lambda (row)
            (and (listp row) (= (length row) 6)
                 (= (type (car row)) 'STR) (numberp (cadr row))
                 (numberp (nth 2 row)) (> (nth 2 row) 0.0) (< (nth 2 row) 1.0)
                 (numberp (nth 3 row)) (> (abs (nth 3 row)) 1e-9)
                 (= (type (nth 4 row)) 'STR)
                 (numberp (nth 5 row)) (> (nth 5 row) 0.0)))
         cx:*targeted-replacement-layouts*)
       (= (length cx:*full-batch-cleanup-handles*) target-count)
       (= (length cx:*full-batch-clean-slate-object-names*) 0)
       (not cx:*full-batch-save-on-success*)
       (boundp 'cx:*full-batch-expected-drawing*)
       (= (type cx:*full-batch-expected-drawing*) 'STR)
       (> (strlen cx:*full-batch-expected-drawing*) 0)
       (boundp 'cx:*full-batch-summary-path*)
       (= (type cx:*full-batch-summary-path*) 'STR)
       (boundp 'cx:*full-batch-details-path*)
       (= (type cx:*full-batch-details-path*) 'STR)
       (equal (cx:tr-task-pairs) (cx:tr-layout-pairs))))

(defun cx:tr-generate-one (row / source-handle segment fraction offset group selection-margin
  entity hidden points pick side before after added call-result info result)
  (setq source-handle (car row) segment (cadr row) fraction (nth 2 row)
        offset (nth 3 row) group (nth 4 row) selection-margin (nth 5 row)
        entity (handent source-handle)
        result (list "FAIL" "SOURCE_OR_SEGMENT_INVALID" "" group source-handle
          segment fraction offset nil nil '("" "" "")))
  (if (and entity (= (cdr (assoc 0 (entget entity))) "LWPOLYLINE")
           (cx:tr-arc-segment-p entity segment))
    (progn
      (setq hidden (cx:tr-hide-non-source entity)
            cx:tr-active-hidden hidden)
      (vl-catch-all-apply 'command-s (list "_.REGEN"))
      (cx:tr-zoom-segment entity segment selection-margin)
      (setq points (cx:tr-segment-points entity segment fraction offset))
      (if points
        (progn
          (setq pick (car points) side (cadr points)
                before (cx:tr-native-handles)
                call-result (vl-catch-all-apply 'command-s
                  (list "TDIMARC" pick pick side ""))
                after (cx:tr-native-handles)
                added (cx:tr-difference after before))
          (cond
            ((vl-catch-all-error-p call-result)
              (if added (cx:tr-delete-handles added))
              (setq result (list "FAIL" "TDIMARC_COMMAND_ERROR" "" group
                source-handle segment fraction offset pick side '("" "" ""))))
            ((/= (length added) 1)
              (if added (cx:tr-delete-handles added))
              (setq result (list "FAIL" "CANDIDATE_COUNT_INVALID" "" group
                source-handle segment fraction offset pick side '("" "" ""))))
            (T
              (setq info (cx:tr-object-info (car added)))
              (if (and (= (car info) "TDbDimension2")
                       (= (cadr info) "PUB_DIM")
                       (= (caddr info) "_TCH_ARROW"))
                (progn
                  (setq cx:tr-created (append cx:tr-created added))
                  (setq result (list "PASS"
                    "CANDIDATE_CREATED_PENDING_SOURCE_AUDIT" (car added) group
                    source-handle segment fraction offset pick side info)))
                (progn
                  (cx:tr-delete-handles added)
                  (setq result (list "FAIL" "WRONG_NATIVE_CONTRACT" "" group
                    source-handle segment fraction offset pick side info)))))))
        (setq result (list "FAIL" "SEGMENT_POINT_FAILED" "" group
          source-handle segment fraction offset nil nil '("" "" ""))))
      (cx:tr-restore-visible hidden)
      (setq cx:tr-active-hidden '())
      (vl-catch-all-apply 'command-s (list "_.REGEN"))))
  result)

(defun cx:tr-detail-line (result / pick side info)
  (setq pick (nth 8 result) side (nth 9 result) info (nth 10 result))
  (strcat (nth 3 result) "\t" (nth 4 result) "\tARC\t"
    (itoa (nth 5 result)) "\t" (car result) "\t" (nth 2 result) "\t"
    (car info) "\t" (cadr info) "\t" (caddr info) "\t"
    (rtos (nth 6 result) 2 4) "\t" (rtos (nth 7 result) 2 8) "\t"
    (if pick (rtos (car pick) 2 8) "") "\t"
    (if pick (rtos (cadr pick) 2 8) "") "\t"
    (if side (rtos (car side) 2 8) "") "\t"
    (if side (rtos (cadr side) 2 8) "") "\t"
    (cadr result) "\t" (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES")))

(defun c:CXTDIMARCTARGETEDREPLACE
  (/ old-error started status detail before-count after-count results row result
    deleted restored cleanup-ok all-pass summary details elapsed rows cleanup
    cleanup-handle erased-one)
  (setq old-error *error*
        started (getvar "MILLISECS") status "FAIL" detail "UNINITIALIZED"
        results '() cx:tr-active-hidden '() cx:tr-created '()
        cx:tr-deleted-old '()
        before-count (length (cx:tr-native-handles))
        details (list
          "GROUP\tSOURCE_HANDLE\tSEGMENT_TYPE\tSEGMENT_INDEX\tSTATUS\tADDED_HANDLE\tOBJECT_NAME\tLAYER\tDIM_STYLE\tPICK_FRACTION\tOFFSET\tPICK_X\tPICK_Y\tSIDE_X\tSIDE_Y\tDETAIL\tCMDACTIVE\tCMDNAMES"))
  (defun *error* (message)
    (if cx:tr-created (cx:tr-delete-handles cx:tr-created))
    (if cx:tr-deleted-old (cx:tr-restore-erased cx:tr-deleted-old))
    (cx:tr-restore-visible cx:tr-active-hidden)
    (setq cx:tr-active-hidden '())
    (vl-catch-all-apply 'command-s (list "_.REGEN"))
    (if (and (boundp 'cx:*full-batch-summary-path*)
             (= (type cx:*full-batch-summary-path*) 'STR))
      (cx:tr-write-lines cx:*full-batch-summary-path*
        (list "STATUS\tDETAIL\tTASK_COUNT\tTARGET_SEGMENTS\tSUCCESS_COUNT\tROAD_COUNT\tSHORE_COUNT\tADDED_HANDLES\tFAILED\tCLEANUP_DELETED\tCLEAN_SLATE_DELETED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
          (strcat "FAIL\tUNHANDLED_ERROR:" message
            "\t0\t" (itoa (length cx:*targeted-replacement-layouts*))
            "\t0\t0\t0\t\t\t\t\t0\t"
            (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES")))))
    (setq *error* old-error)
    (princ))
  (cond
    ((not (cx:tr-valid-input-p)) (setq detail "TARGETED_INPUT_CONTRACT_INVALID"))
    ((/= (cx:tr-current-drawing)
         (cx:tr-normalize-path cx:*full-batch-expected-drawing*))
      (setq detail "EXPECTED_DRAWING_MISMATCH"))
    (T
      (setq all-pass T
            rows cx:*targeted-replacement-layouts*
            cleanup cx:*full-batch-cleanup-handles*)
      (while (and all-pass rows cleanup)
        (setq row (car rows)
              cleanup-handle (car cleanup)
              erased-one (cx:tr-delete-handles (list cleanup-handle)))
        (if (/= (length erased-one) 1)
          (progn
            (setq result (list "FAIL" "PAIRED_OBSOLETE_ERASE_FAILED" ""
              (nth 4 row) (car row) (cadr row) (nth 2 row) (nth 3 row)
              nil nil '("" "" ""))
              results (append results (list result))
              details (append details (list (cx:tr-detail-line result)))
              all-pass nil))
          (progn
            (setq cx:tr-deleted-old (append cx:tr-deleted-old erased-one))
            ;; Tianzheng caches native dimension/source associations.  Force the
            ;; erased pair out of the graphics and command state before asking
            ;; TDIMARC to recreate that same source segment.
            (vl-catch-all-apply 'command-s (list "_.REGEN"))
            (setq result (cx:tr-generate-one row)
                  results (append results (list result))
                  details (append details (list (cx:tr-detail-line result))))
            (if (/= (car result) "PASS") (setq all-pass nil))))
        (setq rows (cdr rows) cleanup (cdr cleanup)))
      (if all-pass
        (setq status "PASS"
              detail "PAIRED_TRANSACTIONAL_REPLACEMENT_COMPLETE_PENDING_SOURCE_AUDIT")
        (progn
          (cx:tr-delete-handles cx:tr-created)
          (setq restored (cx:tr-restore-erased cx:tr-deleted-old)
                cx:tr-created '() cx:tr-deleted-old '()
                detail (strcat "PAIRED_REPLACEMENT_FAILED_ROLLED_BACK:"
                  (if result (cadr result) "UNKNOWN")))))))
  (setq after-count (length (cx:tr-native-handles))
        elapsed (- (getvar "MILLISECS") started)
        summary (list
          "STATUS\tDETAIL\tTASK_COUNT\tTARGET_SEGMENTS\tSUCCESS_COUNT\tROAD_COUNT\tSHORE_COUNT\tADDED_HANDLES\tFAILED\tCLEANUP_DELETED\tCLEAN_SLATE_DELETED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES\tNATIVE_COUNT_BEFORE\tNATIVE_COUNT_AFTER"
          (strcat status "\t" detail "\t" (itoa (length cx:*full-batch-tasks*))
            "\t" (itoa (length cx:*targeted-replacement-layouts*)) "\t"
            (if (= status "PASS") (itoa (length cx:*targeted-replacement-layouts*)) "0") "\t0\t"
            (if (= status "PASS") (itoa (length cx:*targeted-replacement-layouts*)) "0") "\t"
            (if cx:tr-created (vl-string-right-trim ","
              (apply 'strcat (mapcar '(lambda (h) (strcat h ",")) cx:tr-created))) "")
            "\t\t"
            (if cx:tr-deleted-old (vl-string-right-trim ","
              (apply 'strcat (mapcar '(lambda (h) (strcat h ",")) cx:tr-deleted-old))) "")
            "\t\t" (itoa elapsed) "\t" (itoa (getvar "CMDACTIVE")) "\t"
            (getvar "CMDNAMES") "\t" (itoa before-count) "\t" (itoa after-count))))
  (if (and (boundp 'cx:*full-batch-details-path*)
           (= (type cx:*full-batch-details-path*) 'STR))
    (cx:tr-write-lines cx:*full-batch-details-path* details))
  (if (and (boundp 'cx:*full-batch-summary-path*)
           (= (type cx:*full-batch-summary-path*) 'STR))
    (cx:tr-write-lines cx:*full-batch-summary-path* summary))
  (setq *error* old-error)
  (princ))

(c:CXTDIMARCTARGETEDREPLACE)
