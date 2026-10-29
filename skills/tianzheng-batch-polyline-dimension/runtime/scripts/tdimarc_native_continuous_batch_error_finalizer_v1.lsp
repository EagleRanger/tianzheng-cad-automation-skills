(vl-load-com)

;; Runtime-error finalizer for the continuous native batch.
;; A single unexpected segment error must not delete already accepted native
;; objects or suppress the authoritative summary/details files.  This handler
;; records the current segment as failed, preserves the committed handle set,
;; performs only idle-safe visibility cleanup, and writes a terminal PARTIAL or
;; FAIL report before returning control to the previous error handler.

(defun cx:cbe1-clean-text (value / text)
  (setq text (vl-princ-to-string value))
  (vl-string-translate "\t\r\n" "   " text))

(defun cx:cbe1-safe-string (symbol-name fallback)
  (if (boundp symbol-name) (eval symbol-name) fallback))

(defun cx:cbe1-safe-list (symbol-name fallback / value)
  (setq value (if (boundp symbol-name) (eval symbol-name) fallback))
  (if (listp value) value fallback))

(defun cx:cbe1-safe-integer (symbol-name / value)
  (setq value (if (boundp symbol-name) (eval symbol-name) 0))
  (if (numberp value) (fix value) 0))

(defun cx:cbe1-runtime-error
  (message / safe-message safe-source safe-type safe-index safe-group
    safe-added safe-failures safe-details failure-key error-detail
    final-status final-detail final-summary elapsed cleanup-note)
  ;; Disarm this handler first so a report I/O failure cannot recurse.
  (if (boundp 'cx:*fb-old-error*) (setq *error* cx:*fb-old-error*))
  (setq safe-message (cx:cbe1-clean-text message)
        safe-source (cx:cbe1-safe-string 'cx:*fb-current-handle* "")
        safe-type
          (strcase (cx:cbe1-safe-string 'segment-type "UNKNOWN"))
        safe-index (cx:cbe1-safe-integer 'cx:*fb-current-segment*)
        safe-group (cx:cbe1-safe-string 'group "UNKNOWN")
        safe-added
          (cx:cbe1-safe-list 'all-added
            (cx:cbe1-safe-list 'cx:*fb-added* '()))
        safe-failures (cx:cbe1-safe-list 'failures '())
        safe-details
          (cx:cbe1-safe-list 'details
            (list
              "GROUP\tSOURCE_HANDLE\tSEGMENT_TYPE\tSEGMENT_INDEX\tSTATUS\tADDED_HANDLE\tOBJECT_NAME\tLAYER\tDIM_STYLE\tPICK_X\tPICK_Y\tSIDE_X\tSIDE_Y\tCMDACTIVE\tCMDNAMES\tATTEMPTS"))
        failure-key
          (strcat safe-source ":" safe-type ":" (itoa safe-index)
            ":RUNTIME_ERROR")
        safe-failures (append safe-failures (list failure-key))
        error-detail
          (strcat safe-group "\t" safe-source "\t" safe-type "\t"
            (itoa safe-index) "\tFAIL\t\t\t\t\t\t\t\t\t"
            (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES")
            "\tRUNTIME_ERROR{" safe-message "}")
        safe-details (append safe-details (list error-detail))
        cleanup-note "PRESERVED_ACCEPTED_OBJECTS")

  ;; COM visibility restoration is safe while a native command is active.
  (if safe-added
    (vl-catch-all-apply 'cx:cb-show-handles (list safe-added)))
  ;; Command-based unisolation is allowed only after the exact command state is
  ;; idle; otherwise the next disposable lifecycle owns cleanup.
  (if (and (= (getvar "CMDNAMES") "")
           (boundp 'batch-isolated) batch-isolated)
    (progn
      (vl-catch-all-apply 'cx:fb-unisolate-objects '())
      (setq cleanup-note "PRESERVED_ACCEPTED_OBJECTS__UNISOLATED")))

  (setq final-status
          (if (> (cx:cbe1-safe-integer 'segment-count) 0)
            "PARTIAL" "FAIL")
        final-detail
          (strcat
            "RUNTIME_ERROR_FINALIZED__SUCCESSFUL_NATIVE_OBJECTS_PRESERVED__"
            cleanup-note)
        elapsed
          (if (boundp 'started) (- (getvar "MILLISECS") started) 0)
        final-summary
          (list
            "STATUS\tDETAIL\tTASK_COUNT\tTARGET_SEGMENTS\tSUCCESS_COUNT\tROAD_COUNT\tSHORE_COUNT\tADDED_HANDLES\tFAILED\tCLEANUP_DELETED\tCLEAN_SLATE_DELETED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
            (strcat final-status "\t" final-detail "\t"
              (itoa (cx:cbe1-safe-integer 'task-count)) "\t"
              (itoa (cx:cbe1-safe-integer 'target-count)) "\t"
              (itoa (cx:cbe1-safe-integer 'segment-count)) "\t"
              (itoa (cx:cbe1-safe-integer 'road-count)) "\t"
              (itoa (cx:cbe1-safe-integer 'shore-count)) "\t"
              (cx:fb-join safe-added) "\t"
              (cx:fb-join safe-failures) "\t"
              (cx:fb-join (cx:cbe1-safe-list 'cleanup-deleted '())) "\t"
              (cx:fb-join (cx:cbe1-safe-list 'clean-slate-deleted '())) "\t"
              (itoa elapsed) "\t" (itoa (getvar "CMDACTIVE")) "\t"
              (getvar "CMDNAMES"))))

  (if (boundp 'cx:*full-batch-details-path*)
    (vl-catch-all-apply 'cx:fb-write-lines
      (list cx:*full-batch-details-path* safe-details)))
  (if (boundp 'cx:*full-batch-summary-path*)
    (vl-catch-all-apply 'cx:fb-write-lines
      (list cx:*full-batch-summary-path* final-summary)))
  (vl-catch-all-apply 'cx:fb-write-lines
    (list "C:/tmp/cx_tdimarc_full_runtime_error.tsv"
      (list "STATUS\tPHASE\tSOURCE_HANDLE\tSEGMENT\tMESSAGE"
        (strcat "FAIL\t"
          (cx:cbe1-safe-string 'cx:*fb-phase* "UNKNOWN") "\t"
          safe-source "\t" (itoa safe-index) "\t" safe-message))))
  (setq cx:*fb-phase* "RUNTIME_ERROR_REPORTS_FINALIZED")
  (princ))

(defun cx:fb-runtime-error (message)
  (cx:cbe1-runtime-error message))

(princ)
