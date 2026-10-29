(vl-load-com)

(defun cx:observer-write (path stage / opened stream result)
  (setq opened (vl-catch-all-apply 'open (list path "a")))
  (if (or (vl-catch-all-error-p opened) (null opened))
    nil
    (progn
      (setq stream opened
            result (vl-catch-all-apply 'write-line
              (list
                (strcat stage "\t" (rtos (getvar "DATE") 2 12) "\t"
                  (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))
                stream)))
      (vl-catch-all-apply 'close (list stream))
      (not (vl-catch-all-error-p result)))))

(defun cx:observer-signal (path stage)
  (if (cx:observer-write path stage)
    (princ (strcat "\nCX_OBSERVER:" stage))
    (princ (strcat "\nCX_OBSERVER_WRITE_FAILED:" stage)))
  (princ))

(princ)
