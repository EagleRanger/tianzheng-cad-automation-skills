(vl-load-com)

;; Read-only native Tianzheng dimension bbox inventory for collision planning.

(if (not (boundp 'cx:*bbox-expected-drawing*)) (setq cx:*bbox-expected-drawing* ""))
(if (not (boundp 'cx:*bbox-details-path*))
  (setq cx:*bbox-details-path* "C:/tmp/cx_tz_dimension_bboxes.tsv"))
(if (not (boundp 'cx:*bbox-summary-path*))
  (setq cx:*bbox-summary-path* "C:/tmp/cx_tz_dimension_bbox_summary.tsv"))

(defun cx:db-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:db-safe-property (object property / result)
  (setq result (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (vl-catch-all-error-p result) "" (vl-princ-to-string result)))

(defun cx:db-write-lines (path lines / temporary stream line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach line lines (write-line line stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:db-bbox-row (object / result minimum maximum min-list max-list)
  (setq result (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
  (if (vl-catch-all-error-p result)
    nil
    (progn
      (setq min-list (vlax-safearray->list minimum)
            max-list (vlax-safearray->list maximum))
      (list (car min-list) (cadr min-list) (caddr min-list)
            (car max-list) (cadr max-list) (caddr max-list)))))

(defun c:CXAUDITTZDIMBBOXES
  (/ started drawing doc space count index object bbox rows native-count bbox-count status detail elapsed)
  (setq started (getvar "MILLISECS")
        drawing (cx:db-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))
        rows (list "HANDLE\tOBJECT_NAME\tLAYER\tDIM_STYLE\tMIN_X\tMIN_Y\tMIN_Z\tMAX_X\tMAX_Y\tMAX_Z")
        native-count 0 bbox-count 0 status "FAIL" detail "")
  (if (and (/= cx:*bbox-expected-drawing* "")
           (/= drawing (cx:db-normalize-path cx:*bbox-expected-drawing*)))
    (setq detail "ACTIVE_DRAWING_MISMATCH")
    (progn
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
            space (vla-get-ModelSpace doc)
            count (vla-get-Count space) index 0)
      (repeat count
        (setq object (vla-Item space index))
        (if (= (vla-get-ObjectName object) "TDbDimension2")
          (progn
            (setq native-count (1+ native-count)
                  bbox (cx:db-bbox-row object))
            (if bbox
              (progn
                (setq bbox-count (1+ bbox-count))
                (setq rows
                  (append rows
                    (list
                      (strcat
                        (vla-get-Handle object) "\t"
                        (vla-get-ObjectName object) "\t"
                        (vla-get-Layer object) "\t"
                        (cx:db-safe-property object 'DimStyle) "\t"
                        (rtos (nth 0 bbox) 2 9) "\t" (rtos (nth 1 bbox) 2 9) "\t" (rtos (nth 2 bbox) 2 9) "\t"
                        (rtos (nth 3 bbox) 2 9) "\t" (rtos (nth 4 bbox) 2 9) "\t" (rtos (nth 5 bbox) 2 9)))))))))
        (setq index (1+ index)))
      (setq status "PASS" detail "READ_ONLY_AUDIT")))
  (setq elapsed (- (getvar "MILLISECS") started))
  (cx:db-write-lines cx:*bbox-details-path* rows)
  (cx:db-write-lines cx:*bbox-summary-path*
    (list
      "STATUS\tDETAIL\tNATIVE_COUNT\tBBOX_COUNT\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t" (itoa native-count) "\t" (itoa bbox-count) "\t"
        (itoa elapsed) "\t" (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (princ))

(c:CXAUDITTZDIMBBOXES)
