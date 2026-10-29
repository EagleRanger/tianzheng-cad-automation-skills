(vl-load-com)

;; Reversible one-object probe: copy and explode one native Tianzheng
;; dimension, inventory the exploded child types and bounding boxes, then
;; delete every temporary object.  The original entity is untouched.

(if (not (boundp 'cx:*explode-target-handle*)) (setq cx:*explode-target-handle* ""))
(if (not (boundp 'cx:*explode-expected-drawing*)) (setq cx:*explode-expected-drawing* ""))
(if (not (boundp 'cx:*explode-details-path*))
  (setq cx:*explode-details-path* "C:/tmp/cx_tz_dimension_explode_details.tsv"))
(if (not (boundp 'cx:*explode-summary-path*))
  (setq cx:*explode-summary-path* "C:/tmp/cx_tz_dimension_explode_summary.tsv"))

(defun cx:de-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:de-write-lines (path lines / temporary stream line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach line lines (write-line line stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:de-bbox (object / result minimum maximum min-list max-list)
  (setq result (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
  (if (vl-catch-all-error-p result)
    '("" "" "" "")
    (progn
      (setq min-list (vlax-safearray->list minimum)
            max-list (vlax-safearray->list maximum))
      (list (rtos (car min-list) 2 9) (rtos (cadr min-list) 2 9)
            (rtos (car max-list) 2 9) (rtos (cadr max-list) 2 9)))))

(defun cx:de-space-handles (/ doc space index count object result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        index 0 count (vla-get-Count space) result '())
  (repeat count
    (setq object (vla-Item space index)
          result (cons (vla-get-Handle object) result)
          index (1+ index)))
  result)

(defun cx:de-difference (after before / result handle)
  (setq result '())
  (foreach handle after
    (if (not (member handle before)) (setq result (cons handle result))))
  (reverse result))

(defun cx:de-delete-all (objects / object)
  (foreach object objects
    (if object (vl-catch-all-apply 'vla-Delete (list object)))))

(defun c:CXPROBETZDIMEXPLODE
  (/ started drawing source source-object clone result objects object bbox
     rows status detail error-text child-count text-count before-count after-count
     doc space elapsed before-handles after-handles added-handles handle entity
     first-objects first-object second-before second-after second-added)
  (setq started (getvar "MILLISECS")
        drawing (cx:de-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))
        rows (list "INDEX\tOBJECT_NAME\tLAYER\tMIN_X\tMIN_Y\tMAX_X\tMAX_Y")
        objects '() status "FAIL" detail "" error-text "" child-count 0 text-count 0
        doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        before-count (vla-get-Count space))
  (cond
    ((and (/= cx:*explode-expected-drawing* "")
          (/= drawing (cx:de-normalize-path cx:*explode-expected-drawing*)))
      (setq detail "ACTIVE_DRAWING_MISMATCH"))
    ((null (setq source (handent cx:*explode-target-handle*)))
      (setq detail "TARGET_HANDLE_NOT_FOUND"))
    ((/= (vla-get-ObjectName (setq source-object (vlax-ename->vla-object source)))
         "TDbDimension2")
      (setq detail "TARGET_IS_NOT_TDBDIMENSION2"))
    (t
      (setq clone (vl-catch-all-apply 'vla-Copy (list source-object)))
      (if (vl-catch-all-error-p clone)
        (setq detail "COPY_FAILED" error-text (vl-catch-all-error-message clone))
        (progn
          (setq before-handles (cx:de-space-handles)
                result (vl-catch-all-apply 'command-s
                         (list "_.EXPLODE" (vlax-vla-object->ename clone) "")))
          (if (vl-catch-all-error-p result)
            (setq detail "EXPLODE_FAILED" error-text (vl-catch-all-error-message result))
            (progn
              (setq after-handles (cx:de-space-handles)
                    added-handles (cx:de-difference after-handles before-handles)
                    objects '())
              (foreach handle added-handles
                (if (setq entity (handent handle))
                  (setq objects (append objects (list (vlax-ename->vla-object entity))))))
              ;; TDbDimension2 first becomes a native AutoCAD dimension.  A
              ;; second standard EXPLODE exposes its text and graphic pieces.
              (if (and (= (length objects) 1)
                       (wcmatch (vla-get-ObjectName (car objects)) "*Dimension"))
                (progn
                  (setq first-objects objects
                        first-object (car objects)
                        second-before (cx:de-space-handles))
                  (vl-catch-all-apply 'command-s
                    (list "_.EXPLODE" (vlax-vla-object->ename first-object) ""))
                  (setq second-after (cx:de-space-handles)
                        second-added (cx:de-difference second-after second-before)
                        objects '())
                  (foreach handle second-added
                    (if (setq entity (handent handle))
                      (setq objects (append objects (list (vlax-ename->vla-object entity))))))))
              (setq child-count (length objects))
              (foreach object objects
                (setq bbox (cx:de-bbox object))
                (if (member (vla-get-ObjectName object) '("AcDbText" "AcDbMText"))
                  (setq text-count (1+ text-count)))
                (setq rows
                  (append rows
                    (list
                      (strcat (itoa (length rows)) "\t" (vla-get-ObjectName object) "\t"
                        (vla-get-Layer object) "\t" (nth 0 bbox) "\t" (nth 1 bbox) "\t"
                        (nth 2 bbox) "\t" (nth 3 bbox))))))
              (setq status "PASS" detail "COMMAND_EXPLODE_INVENTORIED")))
          (cx:de-delete-all objects)
          (if (and clone (not (vlax-erased-p clone)))
            (vl-catch-all-apply 'vla-Delete (list clone)))))))
  (setq after-count (vla-get-Count space))
  (if (/= before-count after-count)
    (setq status "FAIL" detail "TEMPORARY_OBJECT_SET_NOT_RESTORED"))
  (setq elapsed (- (getvar "MILLISECS") started))
  (cx:de-write-lines cx:*explode-details-path* rows)
  (cx:de-write-lines cx:*explode-summary-path*
    (list
      "STATUS\tDETAIL\tTARGET_HANDLE\tCHILD_COUNT\tTEXT_COUNT\tERROR_TEXT\tELAPSED_MS\tSPACE_BEFORE\tSPACE_AFTER\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t" cx:*explode-target-handle* "\t"
        (itoa child-count) "\t" (itoa text-count) "\t" error-text "\t" (itoa elapsed) "\t"
        (itoa before-count) "\t" (itoa after-count) "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (princ))

(c:CXPROBETZDIMEXPLODE)
