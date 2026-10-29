(vl-load-com)

(defun cx:ods-normalize (value)
  (strcase (vl-string-translate "/" "\\" value)))

(defun cx:ods-main (/ expected actual report stream)
  (setq expected (cx:ods-normalize cx:*ods-expected-drawing*))
  (setq actual (cx:ods-normalize (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))))
  (setq report cx:*ods-report-path*)
  (setq stream (open report "w"))
  (if (null stream)
    (princ "\nCX_OWNED_STATE_REPORT_OPEN_FAILED")
    (progn
      (write-line "STATUS\tDETAIL\tDRAWING\tDBMOD\tCMDACTIVE\tCMDNAMES" stream)
      (write-line
        (strcat
          (if (= actual expected) "PASS" "FAIL") "\t"
          (if (= actual expected) "READ_ONLY_STATE_AUDIT" "DRAWING_MISMATCH") "\t"
          actual "\t"
          (itoa (getvar "DBMOD")) "\t"
          (itoa (getvar "CMDACTIVE")) "\t"
          (getvar "CMDNAMES"))
        stream)
      (close stream)))
  (princ))

(cx:ods-main)
