(vl-load-com)

(defun cx:vp-string (value)
  (cond
    ((vl-catch-all-error-p value) (strcat "ERROR:" (vl-catch-all-error-message value)))
    ((= (type value) 'VARIANT) (cx:vp-string (vlax-variant-value value)))
    ((= (type value) 'SAFEARRAY) (vl-princ-to-string (vlax-safearray->list value)))
    (T (vl-princ-to-string value))))

(defun cx:vp-call (fn args)
  (vl-catch-all-apply fn args))

(defun c:CXRESETOWNEDVIEWPORT (/ app doc vp file target direction center center-array
                                  put-target put-direction put-center put-height
                                  activate regen)
  (if (or (not (boundp 'cx:*vp-report-path*))
          (not (boundp 'cx:*vp-center-x*))
          (not (boundp 'cx:*vp-center-y*))
          (not (boundp 'cx:*vp-height*)))
    (princ "\nCX_RESET_VIEWPORT_ARGUMENTS_REQUIRED")
    (progn
      (setq app (vlax-get-acad-object)
            doc (vla-get-ActiveDocument app)
            vp (vla-get-ActiveViewport doc)
            ;; In a WCS plan view, Target is the camera target and Center is
            ;; the DCS/WCS view centre.  The previous implementation put the
            ;; drawing centre in Target and zero in Center; later Zoom/REGEN
            ;; calls then applied both transforms and could leave a valid
            ;; drawing behind a black model viewport.
            target (vlax-3d-point '(0.0 0.0 0.0))
            direction (vlax-3d-point '(0.0 0.0 1.0))
            center-array (vlax-make-safearray vlax-vbDouble '(0 . 1)))
      (vlax-safearray-fill center-array (list cx:*vp-center-x* cx:*vp-center-y*))
      (setq center (vlax-make-variant center-array))
      (setq put-target (cx:vp-call 'vla-put-Target (list vp target))
            put-direction (cx:vp-call 'vla-put-Direction (list vp direction))
            put-center (cx:vp-call 'vla-put-Center (list vp center))
            put-height (cx:vp-call 'vla-put-Height (list vp cx:*vp-height*))
            activate (cx:vp-call 'vla-put-ActiveViewport (list doc vp))
            regen (cx:vp-call 'vla-Regen (list doc 1)))
      (setq file (open cx:*vp-report-path* "w"))
      (if file
        (progn
          (write-line "KEY\tVALUE" file)
          (write-line (strcat "PUT_TARGET\t" (cx:vp-string put-target)) file)
          (write-line (strcat "PUT_DIRECTION\t" (cx:vp-string put-direction)) file)
          (write-line (strcat "PUT_CENTER\t" (cx:vp-string put-center)) file)
          (write-line (strcat "PUT_HEIGHT\t" (cx:vp-string put-height)) file)
          (write-line (strcat "ACTIVATE\t" (cx:vp-string activate)) file)
          (write-line (strcat "REGEN\t" (cx:vp-string regen)) file)
          (write-line (strcat "TARGET_AFTER\t" (cx:vp-string (cx:vp-call 'vla-get-Target (list (vla-get-ActiveViewport doc))))) file)
          (write-line (strcat "CENTER_AFTER\t" (cx:vp-string (cx:vp-call 'vla-get-Center (list (vla-get-ActiveViewport doc))))) file)
          (write-line (strcat "HEIGHT_AFTER\t" (cx:vp-string (cx:vp-call 'vla-get-Height (list (vla-get-ActiveViewport doc))))) file)
          (close file)
          (princ "\nCX_RESET_OWNED_VIEWPORT_COMPLETE"))
        (princ "\nCX_RESET_VIEWPORT_REPORT_OPEN_FAILED"))))
  (princ))

(princ)
