(vl-load-com)

;; Read-only typed-segment inventory for exact authorised source polylines.
;; It records ARC and LINE in source-local index order and never edits the DWG.

(if (not (boundp 'cx:*segment-inventory-target-handles*))
  (setq cx:*segment-inventory-target-handles* '()))
(if (not (boundp 'cx:*segment-inventory-expected-drawing*))
  (setq cx:*segment-inventory-expected-drawing* ""))
(if (not (boundp 'cx:*segment-inventory-details-path*))
  (setq cx:*segment-inventory-details-path* "C:/tmp/cx_target_polyline_segments.tsv"))
(if (not (boundp 'cx:*segment-inventory-summary-path*))
  (setq cx:*segment-inventory-summary-path* "C:/tmp/cx_target_polyline_segments_summary.tsv"))

(defun cxsi:normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cxsi:write-lines (path lines / temporary stream item)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach item lines (write-line item stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cxsi:point-text (point)
  (strcat (rtos (car point) 2 12) "\t" (rtos (cadr point) 2 12)))

(defun cxsi:inventory-one
  (handle / entity object object-name end-param index bulge-result bulge
            p0 pm p1 d0 d1 length segment-type arc-count line-count degenerate-count
            data layer entity-color constant-width)
  (setq entity (handent handle))
  (if (null entity)
    (list nil "HANDLE_NOT_FOUND" 0 0)
    (progn
      (setq object (vlax-ename->vla-object entity)
            object-name (vla-get-ObjectName object))
      (if (not (member object-name '("AcDbPolyline" "AcDb2dPolyline")))
        (list nil "NOT_POLYLINE" 0 0)
        (progn
          ;; Read common style fields from DXF data.  Legacy AcDb2dPolyline
          ;; may advertise COM width properties but throw Automation errors
          ;; when they are read, while DXF 8/62/43 stays deterministic.
          (setq data (entget entity)
                layer (cdr (assoc 8 data))
                entity-color (if (assoc 62 data) (abs (cdr (assoc 62 data))) 256)
                constant-width (if (assoc 43 data) (cdr (assoc 43 data)) 0.0)
                end-param (fix (vlax-curve-getEndParam entity))
                index 0 arc-count 0 line-count 0 degenerate-count 0)
          (while (< index end-param)
            (setq bulge-result (vl-catch-all-apply 'vla-GetBulge (list object index)))
            (if (vl-catch-all-error-p bulge-result)
              (setq index end-param arc-count -1 line-count -1)
              (progn
                (setq bulge bulge-result
                      p0 (vlax-curve-getPointAtParam entity index)
                      pm (vlax-curve-getPointAtParam entity (+ index 0.5))
                      p1 (vlax-curve-getPointAtParam entity (1+ index))
                      d0 (vlax-curve-getDistAtParam entity index)
                      d1 (vlax-curve-getDistAtParam entity (1+ index)))
                ;; Some legacy 2D polylines expose one terminal parameter whose
                ;; point/distance is NIL.  It is not drawable geometry and cannot
                ;; receive a native dimension.  Record it explicitly instead of
                ;; passing NIL to RTOS and aborting the entire selected batch.
                (if (and (listp p0) (listp pm) (listp p1)
                         (numberp (car p0)) (numberp (cadr p0))
                         (numberp (car pm)) (numberp (cadr pm))
                         (numberp (car p1)) (numberp (cadr p1))
                         (numberp d0) (numberp d1))
                  (progn
                    (setq length (- d1 d0)
                          segment-type (if (> (abs bulge) 1e-10) "ARC" "LINE"))
                    (if (= segment-type "ARC")
                      (setq arc-count (1+ arc-count))
                      (setq line-count (1+ line-count)))
                    (setq cx:*si-rows*
                      (append cx:*si-rows*
                        (list
                          (strcat handle "\t" (itoa index) "\t" segment-type "\t"
                            layer "\t" (itoa entity-color) "\t" (rtos constant-width 2 12) "\t"
                            (cxsi:point-text p0) "\t" (cxsi:point-text pm) "\t"
                            (cxsi:point-text p1) "\t" (rtos bulge 2 12) "\t"
                            (rtos length 2 12))))))
                  (progn
                    (setq degenerate-count (1+ degenerate-count))
                    (setq cx:*si-rows*
                      (append cx:*si-rows*
                        (list
                          (strcat handle "\t" (itoa index)
                            "\tDEGENERATE\t" layer "\t" (itoa entity-color) "\t"
                            (rtos constant-width 2 12) "\t\t\t\t\t\t\t"
                            (rtos bulge 2 12) "\t0.000000000000"))))))
                (setq index (1+ index)))))
          (if (< arc-count 0)
            (list nil "GET_BULGE_FAILED" 0 0 0)
            (list T "OK" arc-count line-count degenerate-count)))))))

(defun c:CXTARGETPOLYSEGMENTINVENTORY
  (/ started dbmod-before dbmod-after drawing handle result processed failed
      arc-count line-count degenerate-count status detail elapsed)
  (setq started (getvar "MILLISECS")
        dbmod-before (getvar "DBMOD")
        drawing (cxsi:normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))
        cx:*si-rows* (list "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tLAYER\tENTITY_COLOR\tCONSTANT_WIDTH\tSTART_X\tSTART_Y\tMID_X\tMID_Y\tEND_X\tEND_Y\tBULGE\tSEGMENT_LENGTH")
        processed 0 failed 0 arc-count 0 line-count 0 degenerate-count 0 status "FAIL" detail "")
  (if (and (/= cx:*segment-inventory-expected-drawing* "")
           (/= drawing (cxsi:normalize-path cx:*segment-inventory-expected-drawing*)))
    (setq detail "ACTIVE_DRAWING_MISMATCH")
    (progn
      (foreach handle cx:*segment-inventory-target-handles*
        (setq processed (1+ processed)
              result (cxsi:inventory-one (strcase handle)))
        (if (car result)
          (setq arc-count (+ arc-count (caddr result))
                line-count (+ line-count (cadddr result))
                degenerate-count (+ degenerate-count (nth 4 result)))
          (setq failed (1+ failed))))
      (setq status (if (= failed 0) "PASS" "FAIL")
            detail (if (= failed 0) "READ_ONLY_TYPED_SEGMENT_INVENTORY" "ONE_OR_MORE_TARGETS_FAILED"))))
  (setq dbmod-after (getvar "DBMOD") elapsed (- (getvar "MILLISECS") started))
  (if (/= dbmod-before dbmod-after)
    (setq status "FAIL" detail "INVENTORY_CHANGED_DBMOD"))
  (cxsi:write-lines cx:*segment-inventory-details-path* cx:*si-rows*)
  (cxsi:write-lines cx:*segment-inventory-summary-path*
    (list
      "STATUS\tDETAIL\tTARGET_COUNT\tPROCESSED\tFAILED\tARC_COUNT\tLINE_COUNT\tDEGENERATE_COUNT\tSEGMENT_COUNT\tDIMENSIONABLE_SEGMENT_COUNT\tDBMOD_BEFORE\tDBMOD_AFTER\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t"
        (itoa (length cx:*segment-inventory-target-handles*)) "\t"
        (itoa processed) "\t" (itoa failed) "\t" (itoa arc-count) "\t"
        (itoa line-count) "\t" (itoa degenerate-count) "\t"
        (itoa (+ arc-count line-count degenerate-count)) "\t"
        (itoa (+ arc-count line-count)) "\t"
        (itoa dbmod-before) "\t" (itoa dbmod-after) "\t" (itoa elapsed) "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (princ))

(c:CXTARGETPOLYSEGMENTINVENTORY)
