(vl-load-com)

;; Reversible batch extraction of text bounding boxes from native Tianzheng
;; dimensions.  Each source is copied, exploded twice, inventoried, and all
;; temporary entities are deleted before the next source is processed.

(if (not (boundp 'cx:*text-bbox-target-handles*)) (setq cx:*text-bbox-target-handles* '()))
(if (not (boundp 'cx:*text-bbox-handles-path*)) (setq cx:*text-bbox-handles-path* ""))
(if (not (boundp 'cx:*text-bbox-expected-drawing*)) (setq cx:*text-bbox-expected-drawing* ""))
(if (not (boundp 'cx:*text-bbox-details-path*))
  (setq cx:*text-bbox-details-path* "C:/tmp/cx_tz_dimension_text_bboxes.tsv"))
(if (not (boundp 'cx:*text-bbox-summary-path*))
  (setq cx:*text-bbox-summary-path* "C:/tmp/cx_tz_dimension_text_bbox_summary.tsv"))

(defun cx:tb-normalize-path (value) (strcase (vl-string-translate "\\" "/" value)))

(defun cx:tb-write-lines (path lines / temporary stream line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach line lines (write-line line stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:tb-read-handles (path / stream line result)
  (setq result '())
  (if (and (/= path "") (findfile path))
    (progn
      (setq stream (open path "r"))
      (while (setq line (read-line stream))
        (if (/= line "") (setq result (append result (list (strcase line))))))
      (close stream)))
  result)

(defun cx:tb-space-handles (/ doc space index count object result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc) index 0 count (vla-get-Count space) result '())
  (repeat count
    (setq object (vla-Item space index)
          result (cons (vla-get-Handle object) result)
          index (1+ index)))
  result)

(defun cx:tb-difference (after before / result handle)
  (setq result '())
  (foreach handle after (if (not (member handle before)) (setq result (cons handle result))))
  (reverse result))

(defun cx:tb-bbox (object / result minimum maximum min-list max-list)
  (setq result (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
  (if (vl-catch-all-error-p result) nil
    (progn
      (setq min-list (vlax-safearray->list minimum) max-list (vlax-safearray->list maximum))
      (list (car min-list) (cadr min-list) (car max-list) (cadr max-list)))))

(defun cx:tb-safe-text (object / value)
  (setq value (vl-catch-all-apply 'vlax-get-property (list object 'TextString)))
  (if (vl-catch-all-error-p value) "" (vl-string-translate "\t\r\n" "   " value)))

(defun cx:tb-safe-real-property (object property / value)
  (setq value (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (or (vl-catch-all-error-p value) (not (numberp value))) ""
    (rtos value 2 9)))

(defun cx:tb-delete-handles (handles / handle entity)
  (foreach handle handles
    (if (setq entity (handent handle))
      (vl-catch-all-apply 'vla-Delete (list (vlax-ename->vla-object entity))))))

(defun cx:tb-process-one
  (source-handle / source source-object clone clone-handle before1 after1 added1 first-object
     before2 after2 added2 handle entity object bbox text-count child-count error-text status)
  (setq status "FAIL" error-text "" text-count 0 child-count 0 added1 '() added2 '())
  (cond
    ((null (setq source (handent source-handle)))
      (list "TARGET_NOT_FOUND" 0 0 "" '()))
    ((/= (vla-get-ObjectName (setq source-object (vlax-ename->vla-object source))) "TDbDimension2")
      (list "NOT_TDBDIMENSION2" 0 0 "" '()))
    (t
      (setq clone (vl-catch-all-apply 'vla-Copy (list source-object)))
      (if (vl-catch-all-error-p clone)
        (list "COPY_FAILED" 0 0 (vl-catch-all-error-message clone) '())
        (progn
          (setq clone-handle (vla-get-Handle clone)
                before1 (cx:tb-space-handles))
          (setq result (vl-catch-all-apply 'command-s
                         (list "_.EXPLODE" (vlax-vla-object->ename clone) "")))
          (if (vl-catch-all-error-p result)
            (setq error-text (vl-catch-all-error-message result))
            (progn
              (setq after1 (cx:tb-space-handles) added1 (cx:tb-difference after1 before1))
              (if (and (= (length added1) 1)
                       (setq entity (handent (car added1)))
                       (wcmatch (vla-get-ObjectName (setq first-object (vlax-ename->vla-object entity))) "*Dimension"))
                (progn
                  (setq before2 (cx:tb-space-handles))
                  (vl-catch-all-apply 'command-s (list "_.EXPLODE" entity ""))
                  (setq after2 (cx:tb-space-handles) added2 (cx:tb-difference after2 before2)))
                (setq added2 added1))
              (setq child-count (length added2) status "PASS")
              (foreach handle added2
                (if (and (setq entity (handent handle))
                         (member (vla-get-ObjectName (setq object (vlax-ename->vla-object entity)))
                                 '("AcDbText" "AcDbMText"))
                         (setq bbox (cx:tb-bbox object)))
                  (progn
                    (setq text-count (1+ text-count))
                    (setq cx:*tb-rows*
                      (append cx:*tb-rows*
                        (list
                          (strcat source-handle "\t" (itoa text-count) "\t"
                            (cx:tb-safe-text object) "\t"
                            (rtos (nth 0 bbox) 2 9) "\t" (rtos (nth 1 bbox) 2 9) "\t"
                            (rtos (nth 2 bbox) 2 9) "\t" (rtos (nth 3 bbox) 2 9) "\t"
                            (vla-get-ObjectName object) "\t"
                            (cx:tb-safe-real-property object 'Height) "\t"
                            (cx:tb-safe-real-property object 'TextHeight) "\t"
                            (cx:tb-safe-real-property object 'Rotation))))))))))
          (cx:tb-delete-handles added2)
          (cx:tb-delete-handles added1)
          (cx:tb-delete-handles (list clone-handle))
          (if clone (vl-catch-all-apply 'vla-Delete (list clone)))
          (list status child-count text-count error-text added2))))))

(defun c:CXAUDITTZDIMTEXTBBOXES
  (/ started drawing doc space before-count after-count handle one processed passed failed text-total
     status detail elapsed)
  (setq started (getvar "MILLISECS")
        drawing (cx:tb-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))
        doc (vla-get-ActiveDocument (vlax-get-acad-object)) space (vla-get-ModelSpace doc)
        before-count (vla-get-Count space)
        cx:*tb-rows* (list "SOURCE_HANDLE\tTEXT_INDEX\tTEXT\tMIN_X\tMIN_Y\tMAX_X\tMAX_Y\tOBJECT_NAME\tHEIGHT\tTEXT_HEIGHT\tROTATION")
        processed 0 passed 0 failed 0 text-total 0 status "FAIL" detail "")
  (if (and (= cx:*text-bbox-target-handles* '())
           (/= cx:*text-bbox-handles-path* ""))
    (setq cx:*text-bbox-target-handles* (cx:tb-read-handles cx:*text-bbox-handles-path*)))
  (if (and (/= cx:*text-bbox-expected-drawing* "")
           (/= drawing (cx:tb-normalize-path cx:*text-bbox-expected-drawing*)))
    (setq detail "ACTIVE_DRAWING_MISMATCH")
    (progn
      (foreach handle cx:*text-bbox-target-handles*
        (setq processed (1+ processed) one (cx:tb-process-one handle))
        (if (= (car one) "PASS")
          (setq passed (1+ passed) text-total (+ text-total (nth 2 one)))
          (setq failed (1+ failed))))
      (setq status (if (= failed 0) "PASS" "FAIL")
            detail (if (= failed 0) "TEXT_BBOX_AUDIT_COMPLETE" "ONE_OR_MORE_TARGETS_FAILED"))))
  (setq after-count (vla-get-Count space))
  (if (/= before-count after-count)
    (setq status "FAIL" detail "TEMPORARY_OBJECT_SET_NOT_RESTORED"))
  (setq elapsed (- (getvar "MILLISECS") started))
  (cx:tb-write-lines cx:*text-bbox-details-path* cx:*tb-rows*)
  (cx:tb-write-lines cx:*text-bbox-summary-path*
    (list
      "STATUS\tDETAIL\tREQUESTED\tPROCESSED\tPASSED\tFAILED\tTEXT_COUNT\tELAPSED_MS\tSPACE_BEFORE\tSPACE_AFTER\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t" (itoa (length cx:*text-bbox-target-handles*)) "\t"
        (itoa processed) "\t" (itoa passed) "\t" (itoa failed) "\t" (itoa text-total) "\t"
        (itoa elapsed) "\t" (itoa before-count) "\t" (itoa after-count) "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (princ))

(c:CXAUDITTZDIMTEXTBBOXES)
