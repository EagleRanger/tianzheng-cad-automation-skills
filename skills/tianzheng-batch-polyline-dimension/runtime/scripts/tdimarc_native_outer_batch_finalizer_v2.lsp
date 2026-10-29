(vl-load-com)

;; Versioned outer settlement for the continuous native batch.
;; The proven segment algorithms stay unchanged.  This layer owns only:
;;   1. a durable runtime cursor written before each segment route;
;;   2. a vector ledger written after the existing acceptance gate;
;;   3. idempotent visibility/report settlement after every outer return.

(defun cx:obf2-text (value fallback)
  (if (= (type value) 'STR) value fallback))

(defun cx:obf2-int (value)
  (if (numberp value) (fix value) 0))

(defun cx:obf2-file-p (path / stream)
  (setq stream
    (if (and (= (type path) 'STR) (/= path ""))
      (vl-catch-all-apply 'open (list path "r")) nil))
  (if (or (null stream) (vl-catch-all-error-p stream)) nil
    (progn (close stream) T)))

(defun cx:obf2-add-unique (value values)
  (if (or (= value "") (member value values)) values
    (append values (list value))))

(defun cx:obf2-alive-handles (handles / result handle)
  (setq result '())
  (foreach handle handles
    (if (and (= (type handle) 'STR) (/= handle "")
             (handent handle) (entget (handent handle)))
      (setq result (cx:obf2-add-unique handle result))))
  result)

(defun cx:obf2-write-cursor (stage / rows)
  (setq rows
    (list
      "SEQUENCE\tSTAGE\tGROUP\tSOURCE_HANDLE\tSEGMENT_TYPE\tSEGMENT_INDEX\tPHASE"
      (strcat
        (itoa (cx:obf2-int cx:*obf2-current-sequence*)) "\t"
        (cx:obf2-text stage "UNKNOWN") "\t"
        (cx:obf2-text cx:*obf2-current-group* "UNKNOWN") "\t"
        (cx:obf2-text cx:*obf2-current-source* "") "\t"
        (cx:obf2-text cx:*obf2-current-type* "UNKNOWN") "\t"
        (itoa (cx:obf2-int cx:*obf2-current-index*)) "\t"
        (cx:obf2-text cx:*fb-phase* "UNKNOWN"))))
  (if (and (boundp 'cx:*obf2-cursor-path*)
           (= (type cx:*obf2-cursor-path*) 'STR))
    (vl-catch-all-apply 'cx:fb-write-lines
      (list cx:*obf2-cursor-path* rows)))
  (princ))

(defun cx:obf2-segment-start (group source-handle segment-type segment-index)
  (setq cx:*obf2-current-sequence* (1+ cx:*obf2-current-sequence*)
        cx:*obf2-current-group* (cx:obf2-text group "UNKNOWN")
        cx:*obf2-current-source* (cx:obf2-text source-handle "")
        cx:*obf2-current-type* (cx:obf2-text segment-type "UNKNOWN")
        cx:*obf2-current-index* (cx:obf2-int segment-index)
        cx:*obf2-current-outcome-sequence* 0)
  (setq cx:*obf2-task-sources*
    (cx:obf2-add-unique cx:*obf2-current-source* cx:*obf2-task-sources*))
  (cx:obf2-write-cursor "SEGMENT_START_BEFORE_NATIVE_ROUTE")
  (princ))

(defun cx:obf2-base-accept-detail (accepted / handle object-name layer dim-style)
  (setq handle (if (and (listp accepted) (> (length accepted) 1))
                 (cx:obf2-text (nth 1 accepted) "") "")
        object-name (if (and (listp accepted) (> (length accepted) 2))
                      (cx:obf2-text (nth 2 accepted) "") "")
        layer (if (and (listp accepted) (> (length accepted) 3))
                (cx:obf2-text (nth 3 accepted) "") "")
        dim-style (if (and (listp accepted) (> (length accepted) 4))
                    (cx:obf2-text (nth 4 accepted) "") ""))
  (list handle object-name layer dim-style))

;; The builder renames the active proven acceptance function to
;; cx:obf2-base-accept-one.  This wrapper records its exact result without
;; changing acceptance, cleanup, geometry, style, or native command behavior.
(defun cx:fb-accept-one (result expected-style / accepted vector handle pass failure-key row trace)
  (setq accepted (cx:obf2-base-accept-one result expected-style)
        vector (cx:obf2-base-accept-detail accepted)
        handle (car vector)
        pass (and (listp accepted) (car accepted))
        trace (if (and (boundp 'cx:*sp2-last-trace*)
                       (= (type cx:*sp2-last-trace*) 'STR))
                cx:*sp2-last-trace* ""))
  (if pass
    (progn
      (setq cx:*obf2-accepted-handles*
        (cx:obf2-add-unique handle cx:*obf2-accepted-handles*))
      (if (= cx:*obf2-current-group* "ROAD")
        (setq cx:*obf2-road-count* (1+ cx:*obf2-road-count*))
        (setq cx:*obf2-shore-count* (1+ cx:*obf2-shore-count*))))
    (progn
      (setq failure-key
        (strcat cx:*obf2-current-source* ":" cx:*obf2-current-type* ":"
          (itoa cx:*obf2-current-index*) ":NO_ACCEPTED_NATIVE_OBJECT"))
      (setq cx:*obf2-failures*
        (cx:obf2-add-unique failure-key cx:*obf2-failures*))))
  (setq row
    (strcat cx:*obf2-current-group* "\t" cx:*obf2-current-source* "\t"
      cx:*obf2-current-type* "\t" (itoa cx:*obf2-current-index*) "\t"
      (if pass "PASS" "FAIL") "\t" handle "\t" (nth 1 vector) "\t"
      (nth 2 vector) "\t" (nth 3 vector) "\t\t\t\t\t"
      (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES") "\t"
      "OUTER_VECTOR_V2{" trace "}"))
  (setq cx:*obf2-details* (append cx:*obf2-details* (list row))
        cx:*obf2-current-outcome-sequence* cx:*obf2-current-sequence*)
  (cx:obf2-write-cursor (if pass "ACCEPTANCE_PASS_RECORDED" "ACCEPTANCE_FAIL_RECORDED"))
  accepted)

(defun cx:obf2-unsettled-cursor-p ()
  (and (> cx:*obf2-current-sequence* 0)
       (/= cx:*obf2-current-outcome-sequence* cx:*obf2-current-sequence*)))

(defun cx:obf2-finalize (reason / reports-exist accepted target-count status detail
  failure-key elapsed summary visibility-note report-note receipt)
  (if (not cx:*obf2-finalized*)
    (progn
      (setq cx:*obf2-finalized* T
            accepted (cx:obf2-alive-handles cx:*obf2-accepted-handles*)
            target-count (cx:fb-sum-targets cx:*full-batch-tasks*)
            reports-exist
              (and (cx:obf2-file-p cx:*full-batch-summary-path*)
                   (cx:obf2-file-p cx:*full-batch-details-path*))
            visibility-note "ACCEPTED_HANDLES_SHOWN")
      (if (cx:obf2-unsettled-cursor-p)
        (progn
          (setq failure-key
            (strcat cx:*obf2-current-source* ":" cx:*obf2-current-type* ":"
              (itoa cx:*obf2-current-index*) ":OUTER_FINALIZER_UNSETTLED_ROUTE"))
          (setq cx:*obf2-failures*
            (cx:obf2-add-unique failure-key cx:*obf2-failures*))
          (setq cx:*obf2-details*
            (append cx:*obf2-details*
              (list
                (strcat cx:*obf2-current-group* "\t" cx:*obf2-current-source* "\t"
                  cx:*obf2-current-type* "\t" (itoa cx:*obf2-current-index*)
                  "\tFAIL\t\t\t\t\t\t\t\t\t"
                  (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES")
                  "\tOUTER_FINALIZER_UNSETTLED_ROUTE"))))))
      (if accepted
        (vl-catch-all-apply 'cx:cb-show-handles (list accepted)))
      (if (and (= (getvar "CMDNAMES") "")
               (boundp 'cx:*fb-object-isolated*) cx:*fb-object-isolated*)
        (progn
          (vl-catch-all-apply 'cx:fb-unisolate-objects '())
          (setq cx:*fb-object-isolated* nil
                visibility-note "ACCEPTED_HANDLES_SHOWN__SOURCE_UNISOLATED")))
      (if reports-exist
        (setq report-note "EXISTING_AUTHORITATIVE_REPORTS_PRESERVED")
        (progn
          (setq status
            (cond
              ((and (= (length accepted) target-count)
                    (null cx:*obf2-failures*)) "PASS")
              ((> (length accepted) 0) "PARTIAL")
              (T "FAIL")))
          (setq detail
            (strcat "OUTER_BATCH_FINALIZER_V2__" (cx:obf2-text reason "UNKNOWN")
              "__" visibility-note))
          (setq elapsed (- (getvar "MILLISECS") cx:*obf2-started*))
          (setq summary
            (list
              "STATUS\tDETAIL\tTASK_COUNT\tTARGET_SEGMENTS\tSUCCESS_COUNT\tROAD_COUNT\tSHORE_COUNT\tADDED_HANDLES\tFAILED\tCLEANUP_DELETED\tCLEAN_SLATE_DELETED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
              (strcat status "\t" detail "\t"
                (itoa (length cx:*obf2-task-sources*)) "\t"
                (itoa target-count) "\t" (itoa (length accepted)) "\t"
                (itoa cx:*obf2-road-count*) "\t" (itoa cx:*obf2-shore-count*) "\t"
                (cx:fb-join accepted) "\t" (cx:fb-join cx:*obf2-failures*)
                "\t\t\t" (itoa elapsed) "\t"
                (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
          (vl-catch-all-apply 'cx:fb-write-lines
            (list cx:*full-batch-details-path* cx:*obf2-details*))
          (vl-catch-all-apply 'cx:fb-write-lines
            (list cx:*full-batch-summary-path* summary))
          (setq report-note "MISSING_REPORTS_RECONSTRUCTED_FROM_RUNTIME_VECTOR_LEDGER")))
      (setq receipt
        (list
          "STATUS\tREASON\tREPORT_SETTLEMENT\tVISIBILITY_SETTLEMENT\tCURSOR_SEQUENCE\tCURSOR_SOURCE\tCURSOR_TYPE\tCURSOR_INDEX\tALIVE_ACCEPTED"
          (strcat "PASS\t" (cx:obf2-text reason "UNKNOWN") "\t" report-note "\t"
            visibility-note "\t" (itoa cx:*obf2-current-sequence*) "\t"
            cx:*obf2-current-source* "\t" cx:*obf2-current-type* "\t"
            (itoa cx:*obf2-current-index*) "\t" (itoa (length accepted)))))
      (if (and (boundp 'cx:*obf2-finalizer-path*)
               (= (type cx:*obf2-finalizer-path*) 'STR))
        (vl-catch-all-apply 'cx:fb-write-lines
          (list cx:*obf2-finalizer-path* receipt)))
      (cx:obf2-write-cursor "OUTER_FINALIZER_SETTLED")))
  (princ))

(defun cx:obf2-runtime-error (message)
  (setq *error* cx:*obf2-outer-old-error*)
  (cx:obf2-finalize
    (strcat "ERROR_" (vl-string-translate (strcat (chr 9) (chr 10) (chr 13))
      "   " (cx:obf2-text message "UNKNOWN"))))
  (princ))

;; The active base batch assigns this symbol to *error*.  Keep the identity
;; bound to the robust outer finalizer after all older handlers are loaded.
(defun cx:fb-runtime-error (message)
  (cx:obf2-runtime-error message))

(defun c:CXTDIMARCFULLBATCH (/ result)
  (setq cx:*obf2-outer-old-error* *error*
        cx:*obf2-started* (getvar "MILLISECS")
        cx:*obf2-finalized* nil
        cx:*obf2-current-sequence* 0
        cx:*obf2-current-outcome-sequence* 0
        cx:*obf2-current-group* "UNKNOWN"
        cx:*obf2-current-source* ""
        cx:*obf2-current-type* "UNKNOWN"
        cx:*obf2-current-index* 0
        cx:*obf2-task-sources* '()
        cx:*obf2-accepted-handles* '()
        cx:*obf2-failures* '()
        cx:*obf2-road-count* 0
        cx:*obf2-shore-count* 0
        cx:*obf2-details*
          (list
            "GROUP\tSOURCE_HANDLE\tSEGMENT_TYPE\tSEGMENT_INDEX\tSTATUS\tADDED_HANDLE\tOBJECT_NAME\tLAYER\tDIM_STYLE\tPICK_X\tPICK_Y\tSIDE_X\tSIDE_Y\tCMDACTIVE\tCMDNAMES\tATTEMPTS")
        *error* cx:obf2-runtime-error)
  (setq result (vl-catch-all-apply 'cx:obf2-base-batch '()))
  (if (vl-catch-all-error-p result)
    (cx:obf2-runtime-error (vl-catch-all-error-message result))
    (cx:obf2-finalize "NORMAL_OR_SILENT_RETURN"))
  (setq *error* cx:*obf2-outer-old-error*)
  (princ))

(princ)
