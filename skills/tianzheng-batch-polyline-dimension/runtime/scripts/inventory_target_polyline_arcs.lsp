(vl-load-com)

;; Read-only geometry inventory for explicitly authorised source polylines.
;; This implementation follows the already proven curve-point/bulge pattern
;; used by the route inventories in this project.  It never edits the DWG.

(if (not (boundp 'cx:*arc-inventory-target-handles*))
  (setq cx:*arc-inventory-target-handles* '()))
(if (not (boundp 'cx:*arc-inventory-expected-drawing*))
  (setq cx:*arc-inventory-expected-drawing* ""))
(if (not (boundp 'cx:*arc-inventory-details-path*))
  (setq cx:*arc-inventory-details-path* "C:/tmp/cx_target_polyline_arcs.tsv"))
(if (not (boundp 'cx:*arc-inventory-summary-path*))
  (setq cx:*arc-inventory-summary-path* "C:/tmp/cx_target_polyline_arcs_summary.tsv"))

(defun cxai_normalize_path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cxai_write_lines (path lines / temporary stream item)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach item lines (write-line item stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cxai_point_text (point)
  (strcat (rtos (car point) 2 9) "\t" (rtos (cadr point) 2 9)))

(defun cxai_center_from_bulge (p0 p1 bulge / dx dy chord mx my offset)
  (setq dx (- (car p1) (car p0))
        dy (- (cadr p1) (cadr p0))
        chord (distance p0 p1)
        mx (/ (+ (car p0) (car p1)) 2.0)
        my (/ (+ (cadr p0) (cadr p1)) 2.0))
  (if (and (> chord 1e-8) (> (abs bulge) 1e-10))
    (progn
      (setq offset (/ (* chord (- 1.0 (* bulge bulge))) (* 4.0 bulge)))
      (list (- mx (* (/ dy chord) offset))
            (+ my (* (/ dx chord) offset))
            0.0))
    nil))

(defun cxai_inventory_one
  (handle / entity object object_name end_param index bulge_result bulge p0 pm p1 center chord radius sweep count)
  (setq entity (handent handle))
  (if (null entity)
    (list nil "HANDLE_NOT_FOUND" 0)
    (progn
      (setq object (vlax-ename->vla-object entity)
            object_name (vla-get-ObjectName object))
      (if (not (member object_name '("AcDbPolyline" "AcDb2dPolyline")))
        (list nil "NOT_POLYLINE" 0)
        (progn
          (setq end_param (fix (vlax-curve-getEndParam entity))
                index 0
                count 0)
          (while (< index end_param)
            (setq bulge_result (vl-catch-all-apply 'vla-GetBulge (list object index)))
            (if (not (vl-catch-all-error-p bulge_result))
              (progn
                (setq bulge bulge_result)
                (if (> (abs bulge) 1e-10)
                  (progn
                    (setq p0 (vlax-curve-getPointAtParam entity index)
                          pm (vlax-curve-getPointAtParam entity (+ index 0.5))
                          p1 (vlax-curve-getPointAtParam entity (1+ index))
                          center (cxai_center_from_bulge p0 p1 bulge)
                          chord (distance p0 p1)
                          radius (/ (* chord (+ 1.0 (* bulge bulge))) (* 4.0 (abs bulge)))
                          sweep (* 4.0 (atan bulge) (/ 180.0 pi)))
                    (if center
                      (progn
                        (setq cx:*ai-rows*
                          (append cx:*ai-rows*
                            (list
                              (strcat handle "\t" (itoa index) "\t"
                                (cxai_point_text p0) "\t"
                                (cxai_point_text pm) "\t"
                                (cxai_point_text p1) "\t"
                                (cxai_point_text center) "\t"
                                (rtos radius 2 9) "\t"
                                (rtos sweep 2 9)))))
                        (setq count (1+ count))))))))
            (setq index (1+ index)))
          (list T "OK" count))))))

(defun c:CXTARGETPOLYARCINVENTORY
  (/ started drawing handle result processed failed arc_count status detail elapsed)
  (setq started (getvar "MILLISECS")
        drawing (cxai_normalize_path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))
        cx:*ai-rows* (list "SOURCE_HANDLE\tSEGMENT_INDEX\tSTART_X\tSTART_Y\tMID_X\tMID_Y\tEND_X\tEND_Y\tCENTER_X\tCENTER_Y\tRADIUS\tSWEEP_DEGREES")
        processed 0
        failed 0
        arc_count 0
        status "FAIL"
        detail "")
  (if (and (/= cx:*arc-inventory-expected-drawing* "")
           (/= drawing (cxai_normalize_path cx:*arc-inventory-expected-drawing*)))
    (setq detail "ACTIVE_DRAWING_MISMATCH")
    (progn
      (foreach handle cx:*arc-inventory-target-handles*
        (setq processed (1+ processed)
              result (cxai_inventory_one (strcase handle)))
        (if (car result)
          (setq arc_count (+ arc_count (caddr result)))
          (setq failed (1+ failed))))
      (setq status (if (= failed 0) "PASS" "FAIL")
            detail (if (= failed 0) "READ_ONLY_ARC_GEOMETRY_INVENTORY" "ONE_OR_MORE_TARGETS_FAILED"))))
  (setq elapsed (- (getvar "MILLISECS") started))
  (cxai_write_lines cx:*arc-inventory-details-path* cx:*ai-rows*)
  (cxai_write_lines cx:*arc-inventory-summary-path*
    (list
      "STATUS\tDETAIL\tTARGET_COUNT\tPROCESSED\tFAILED\tARC_COUNT\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t"
        (itoa (length cx:*arc-inventory-target-handles*)) "\t"
        (itoa processed) "\t"
        (itoa failed) "\t"
        (itoa arc_count) "\t"
        (itoa elapsed) "\t"
        (itoa (getvar "CMDACTIVE")) "\t"
        (getvar "CMDNAMES"))))
  (princ))

(c:CXTARGETPOLYARCINVENTORY)
