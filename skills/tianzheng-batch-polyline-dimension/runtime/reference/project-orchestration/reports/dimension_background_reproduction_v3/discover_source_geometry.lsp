(vl-load-com)
;; This is a read-only selection adapter, not a generation implementation.
;; The executor binds all paths and the expected document in the frozen run.
(defun cxbg:discover-sources (/ doc item name handles path)
  (if (or (not (boundp 'cxbg:expected-drawing))
          (not (boundp 'cxbg:geometry-output))
          (not (boundp 'cxbg:geometry-summary))
          (not (boundp 'cxbg:frozen-inventory-entry)))
    (error "BACKGROUND_DISCOVERY_MISSING_BOUND_INPUTS"))
  (setq path (strcase (vl-string-translate "\\" "/" (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))))
  (if (/= path (strcase (vl-string-translate "\\" "/" cxbg:expected-drawing)))
    (error "BACKGROUND_DISCOVERY_WRONG_DOCUMENT"))
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) handles '())
  (vlax-for item (vla-get-ModelSpace doc)
    (setq name (vla-get-ObjectName item))
    (if (member name '("AcDbPolyline" "AcDb2dPolyline"))
      (setq handles (cons (vla-get-Handle item) handles))))
  (if (null handles) (error "BACKGROUND_DISCOVERY_NO_NATIVE_POLYLINES"))
  (setq cx:*segment-inventory-target-handles* (reverse handles)
        cx:*segment-inventory-expected-drawing* cxbg:expected-drawing
        cx:*segment-inventory-details-path* cxbg:geometry-output
        cx:*segment-inventory-summary-path* cxbg:geometry-summary)
  ;; The accepted module performs the actual native geometry read and its
  ;; DBMOD preservation check; this adapter does not duplicate its arithmetic.
  (load cxbg:frozen-inventory-entry)
  (princ))
(cxbg:discover-sources)
