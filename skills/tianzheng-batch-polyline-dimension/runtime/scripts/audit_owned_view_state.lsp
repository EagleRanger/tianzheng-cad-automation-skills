(vl-load-com)

(defun cx:view-value (name / value)
  (setq value (vl-catch-all-apply 'getvar (list name)))
  (if (vl-catch-all-error-p value) "<ERROR>" (vl-princ-to-string value)))

(defun cx:view-write-row (file name)
  (write-line (strcat name "\t" (cx:view-value name)) file))

(defun cx:count-modelspace (/ block count entity)
  (setq block (tblobjname "BLOCK" "*Model_Space")
        count 0)
  (if block
    (progn
      (setq entity (entnext block))
      (while entity
        (setq count (1+ count)
              entity (entnext entity)))))
  count)

(defun c:CXAUDITOWNEDVIEW (/ file)
  (if (or (not (boundp 'cx:*view-report-path*))
          (not cx:*view-report-path*))
    (princ "\nCX_VIEW_REPORT_PATH_REQUIRED")
    (progn
      (setq file (open cx:*view-report-path* "w"))
      (if file
        (progn
          (write-line "KEY\tVALUE" file)
          (write-line (strcat "MODELSPACE_COUNT\t" (itoa (cx:count-modelspace))) file)
          (foreach name '("DWGNAME" "CTAB" "TILEMODE" "CVPORT" "WORLDUCS"
                          "UCSORG" "UCSXDIR" "UCSYDIR" "UCSFOLLOW"
                          "VIEWCTR" "VIEWSIZE" "VIEWDIR" "TARGET" "VIEWTWIST"
                          "PERSPECTIVE" "EXTMIN" "EXTMAX" "LIMCHECK" "REGENMODE"
                          "CMDACTIVE" "CMDNAMES" "DBMOD")
            (cx:view-write-row file name))
          (close file)
          (princ "\nCX_AUDIT_OWNED_VIEW_COMPLETE"))
        (princ "\nCX_VIEW_REPORT_OPEN_FAILED"))))
  (princ))

(princ)
