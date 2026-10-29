(vl-load-com)

(defun cx:ov-value (pair default)
  (if pair (cdr pair) default))

(defun cx:ov-point-string (value)
  (if (= (type value) 'VARIANT) (setq value (vlax-variant-value value)))
  (if (= (type value) 'SAFEARRAY) (setq value (vlax-safearray->list value)))
  (vl-princ-to-string value))

(defun cx:ov-bbox (object / lo hi result)
  (setq result (vl-catch-all-apply 'vla-GetBoundingBox (list object 'lo 'hi)))
  (if (vl-catch-all-error-p result)
    (strcat "ERROR:" (vl-catch-all-error-message result))
    (strcat (cx:ov-point-string lo) "|" (cx:ov-point-string hi))))

(defun cx:ov-layer-info (layer-name / record flags color)
  (setq record (tblsearch "LAYER" layer-name)
        flags (cx:ov-value (assoc 70 record) -1)
        color (cx:ov-value (assoc 62 record) 0))
  (strcat (itoa flags) "|" (itoa color) "|"
          (if (= 1 (logand flags 1)) "FROZEN" "THAWED") "|"
          (if (< color 0) "OFF" "ON")))

(defun c:CXAUDITOBJECTVISIBILITY (/ file handle entity data object layer visible dxf60)
  (if (or (not (boundp 'cx:*ov-report-path*))
          (not (boundp 'cx:*ov-handles*)))
    (princ "\nCX_OBJECT_VISIBILITY_ARGUMENTS_REQUIRED")
    (progn
      (setq file (open cx:*ov-report-path* "w"))
      (if file
        (progn
          (write-line "HANDLE\tSTATUS\tOBJECT_NAME\tLAYER\tDXF60\tVLA_VISIBLE\tLAYER_FLAGS_COLOR_STATE\tBBOX" file)
          (foreach handle cx:*ov-handles*
            (setq entity (handent handle))
            (if entity
              (progn
                (setq data (entget entity)
                      object (vlax-ename->vla-object entity)
                      layer (cx:ov-value (assoc 8 data) "")
                      dxf60 (cx:ov-value (assoc 60 data) 0)
                      visible (vl-catch-all-apply 'vla-get-Visible (list object)))
                (write-line
                  (strcat handle "\tFOUND\t" (vla-get-ObjectName object) "\t" layer "\t"
                          (itoa dxf60) "\t"
                          (if (vl-catch-all-error-p visible) "ERROR" (vl-princ-to-string visible)) "\t"
                          (cx:ov-layer-info layer) "\t" (cx:ov-bbox object)) file))
              (write-line (strcat handle "\tMISSING\t\t\t\t\t\t") file)))
          (close file)
          (princ "\nCX_AUDIT_OBJECT_VISIBILITY_COMPLETE"))
        (princ "\nCX_OBJECT_VISIBILITY_REPORT_OPEN_FAILED"))))
  (princ))

(princ)
