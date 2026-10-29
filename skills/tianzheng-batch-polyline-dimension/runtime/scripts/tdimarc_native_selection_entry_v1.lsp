(vl-load-com)

(if (not (boundp 'cx:*continuous-offset*))
  (setq cx:*continuous-offset* 3.30225))
(if (not (boundp 'cx:*continuous-group*))
  (setq cx:*continuous-group* "SHORE"))
(if (not (boundp 'cx:*continuous-auto-select-all-polylines*))
  (setq cx:*continuous-auto-select-all-polylines* nil))

(defun cx:cs-segment-items (entity / arcs lines end-param count index result)
  (setq arcs (cx:fb-arc-indices entity)
        lines (cx:fb-straight-indices entity arcs)
        end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list entity))
        count (if (vl-catch-all-error-p end-param) 0 (fix end-param))
        index 0 result '())
  (repeat count
    (cond
      ((member index arcs)
        (setq result (append result (list (list "ARC" index)))))
      ((member index lines)
        (setq result (append result (list (list "LINE" index))))))
    (setq index (1+ index)))
  result)

(defun cx:cs-selection-tasks (selection / index entity object segments tasks)
  (setq index 0 tasks '())
  (repeat (sslength selection)
    (setq entity (ssname selection index)
          object (vl-catch-all-apply 'vlax-ename->vla-object (list entity)))
    (if (and object (not (vl-catch-all-error-p object))
             (= (vla-get-ObjectName object) "AcDbPolyline"))
      (progn
        (setq segments (cx:cs-segment-items entity))
        (if segments
          (setq tasks
            (append tasks
              (list
                (list (vla-get-Handle object) segments
                      cx:*continuous-offset* cx:*continuous-group*)))))))
    (setq index (1+ index)))
  tasks)

(defun c:CXTDIMSELECTALL (/ selection drawing)
  (setq selection
    (cond
      (cx:*continuous-auto-select-all-polylines*
        (ssget "_X" '((0 . "LWPOLYLINE") (410 . "Model"))))
      ((ssget "_I" '((0 . "LWPOLYLINE"))))
      (t (ssget '((0 . "LWPOLYLINE"))))))
  (if (null selection)
    (prompt "\nNo target polylines selected.")
    (progn
      (setq drawing
        (cx:fb-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))
        cx:*full-batch-tasks* (cx:cs-selection-tasks selection)
        cx:*full-batch-cleanup-handles* '()
        cx:*full-batch-clean-slate-object-names* '()
        cx:*full-batch-expected-drawing* drawing
        cx:*full-batch-summary-path* "C:/tmp/cx_tdimarc_continuous_summary.tsv"
        cx:*full-batch-details-path* "C:/tmp/cx_tdimarc_continuous_details.tsv"
        cx:*full-batch-save-on-success* nil)
      (if cx:*full-batch-tasks*
        (c:CXTDIMARCFULLBATCH)
        (prompt "\nSelection contains no dimensionable polyline segments."))))
  (princ))

(princ "\nCXTDIMSELECTALL loaded: one selection, internal ARC/LINE dispatch.")
(princ)
