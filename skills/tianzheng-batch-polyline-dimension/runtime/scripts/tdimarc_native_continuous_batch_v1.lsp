(vl-load-com)

;; Validation-only continuous dispatcher for the frozen typed native kernel.
;; The frozen helper functions still own TDIMARC/TDimMP prompt semantics.  This
;; adapter changes only orchestration: one load, continue after an ordinary
;; segment failure, preserve accepted native objects, and return both subsets.

(defun cx:cb-show-handles (handles / handle entity object)
  (foreach handle handles
    (setq entity (handent handle))
    (if (and entity (entget entity))
      (progn
        (setq object (vl-catch-all-apply 'vlax-ename->vla-object (list entity)))
        (if (and object (not (vl-catch-all-error-p object)))
          (vl-catch-all-apply 'vla-put-Visible (list object :vlax-true)))))))

(defun cx:cb-failure-key (source-handle segment-type segment-index reason)
  (strcat source-handle ":" segment-type ":" (itoa segment-index) ":" reason))

(defun c:CXTDIMARCFULLBATCH
  (/ started doc drawing cleanup-result cleanup-deleted task source-handle
     segments offset group entity object arc-indices straight-indices
     segment-item segment-type segment-index expected-style one-result accepted
     all-added dimension-entity dimension-object failures details status detail
     task-count segment-count road-count shore-count elapsed target-count summary
     clean-slate-deleted batch-isolated batch-entities candidate-entity
     structural-failure isolation-ok)
  (setq started (getvar "MILLISECS")
        status "FAIL" detail "" all-added '() failures '()
        task-count 0 segment-count 0 road-count 0 shore-count 0
        cleanup-deleted '() clean-slate-deleted '()
        target-count (cx:fb-sum-targets cx:*full-batch-tasks*)
        batch-isolated nil batch-entities '() structural-failure nil
        details
          (list
            "GROUP\tSOURCE_HANDLE\tSEGMENT_TYPE\tSEGMENT_INDEX\tSTATUS\tADDED_HANDLE\tOBJECT_NAME\tLAYER\tDIM_STYLE\tPICK_X\tPICK_Y\tSIDE_X\tSIDE_Y\tCMDACTIVE\tCMDNAMES\tATTEMPTS"))
  (setq cx:*fb-old-error* *error* *error* cx:fb-runtime-error
        cx:*fb-phase* "START" cx:*fb-current-handle* ""
        cx:*fb-current-segment* nil cx:*fb-added* '()
        cx:*fb-visibility* '() cx:*fb-layer-snapshot* nil
        cx:*fb-object-isolated* nil)
  (setq drawing
    (cx:fb-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))))
  (cond
    ((= target-count 0) (setq detail "EMPTY_TASK_SET" structural-failure T))
    ((and (/= cx:*full-batch-expected-drawing* "")
          (/= drawing (cx:fb-normalize-path cx:*full-batch-expected-drawing*)))
      (setq detail "ACTIVE_DRAWING_MISMATCH" structural-failure T))
    ((/= (getvar "CMDNAMES") "")
      (setq detail "COMMAND_NOT_IDLE_AT_START" structural-failure T))
    (t
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
            cx:*fb-phase* "CLEANUP_HANDLES"
            cleanup-result
              (cx:fb-delete-validated-cleanup cx:*full-batch-cleanup-handles*))
      (if (not (car cleanup-result))
        (setq detail "CLEANUP_HANDLE_CONTRACT_FAILED" structural-failure T)
        (progn
          (setq cleanup-deleted (cadr cleanup-result))
          (if cx:*full-batch-clean-slate-object-names*
            (setq clean-slate-deleted
              (cx:fb-delete-object-names cx:*full-batch-clean-slate-object-names*)))
          (if (or cleanup-deleted clean-slate-deleted)
            (vl-catch-all-apply 'command-s (list "_.REGEN")))

          ;; Resolve and validate every source before the first native command.
          ;; A bad source is recorded per requested segment and does not erase
          ;; other valid sources from the same development batch.
          (foreach task cx:*full-batch-tasks*
            (setq source-handle (car task)
                  segments (cadr task)
                  entity (handent source-handle))
            (cond
              ((null entity)
                (foreach segment-item segments
                  (setq failures
                    (append failures
                      (list
                        (cx:cb-failure-key source-handle
                          (cx:fb-segment-item-type segment-item)
                          (cx:fb-segment-item-index segment-item)
                          "SOURCE_NOT_FOUND"))))))
              ((/= (vla-get-ObjectName
                     (setq object (vlax-ename->vla-object entity)))
                   "AcDbPolyline")
                (foreach segment-item segments
                  (setq failures
                    (append failures
                      (list
                        (cx:cb-failure-key source-handle
                          (cx:fb-segment-item-type segment-item)
                          (cx:fb-segment-item-index segment-item)
                          "NOT_POLYLINE"))))))
              (t (setq batch-entities (append batch-entities (list entity))))))

          (if batch-entities
            (if (cx:fb-isolate-entities batch-entities)
              (setq batch-isolated T cx:*fb-object-isolated* T)
              (setq detail "MULTI_SOURCE_OBJECT_ISOLATION_FAILED"
                    structural-failure T)))

          (if (not structural-failure)
            (foreach task cx:*full-batch-tasks*
              (setq source-handle (car task) segments (cadr task)
                    offset (caddr task) group (cadddr task)
                    entity (handent source-handle)
                    cx:*fb-current-handle* source-handle)
              (if entity
                (progn
                  (setq object (vlax-ename->vla-object entity)
                        arc-indices (cx:fb-arc-indices entity)
                        straight-indices
                          (cx:fb-straight-indices entity arc-indices))
                  (cx:fb-zoom-object object offset)
                  (setq task-count (1+ task-count))
                  (foreach segment-item segments
                    (setq segment-type (cx:fb-segment-item-type segment-item)
                          segment-index (cx:fb-segment-item-index segment-item)
                          expected-style
                            (if (= segment-type "ARC")
                              "_TCH_ARROW" "_TCH_ARCH_M_M")
                          cx:*fb-current-segment* segment-index)
                    (if (not
                          (cx:fb-segment-item-valid-p
                            segment-item arc-indices straight-indices))
                      (progn
                        (setq accepted (list nil "" "" "" "")
                              one-result (list nil '() nil nil "INVALID_TYPED_SEGMENT")
                              failures
                                (append failures
                                  (list
                                    (cx:cb-failure-key source-handle segment-type
                                      segment-index "INVALID_TYPED_SEGMENT")))))
                      (progn
                        (setq cx:*fb-phase* (strcat "RUN_" segment-type)
                              one-result
                                (if (= segment-type "ARC")
                                  (cx:fb-run-one entity segment-index offset expected-style)
                                  (cx:fb-run-line entity segment-index offset))
                              accepted (cx:fb-accept-one one-result expected-style))
                        (if (car accepted)
                          (progn
                            (setq all-added (append all-added (cadr one-result))
                                  segment-count (1+ segment-count)
                                  cx:*fb-added* all-added)
                            (setq dimension-entity (handent (cadr accepted)))
                            (if (and dimension-entity (entget dimension-entity))
                              (progn
                                (setq dimension-object
                                  (vl-catch-all-apply 'vlax-ename->vla-object
                                    (list dimension-entity)))
                                (if (and dimension-object
                                         (not (vl-catch-all-error-p dimension-object)))
                                  (vl-catch-all-apply 'vla-put-Visible
                                    (list dimension-object :vlax-false)))))
                            (if (= group "ROAD")
                              (setq road-count (1+ road-count))
                              (setq shore-count (1+ shore-count))))
                          (setq failures
                            (append failures
                              (list
                                (cx:cb-failure-key source-handle segment-type
                                  segment-index "NO_ACCEPTED_NATIVE_OBJECT")))))))
                    (setq details
                      (append details
                        (list
                          (strcat group "\t" source-handle "\t" segment-type "\t"
                            (itoa segment-index) "\t"
                            (if (car accepted) "PASS" "FAIL") "\t"
                            (cadr accepted) "\t" (caddr accepted) "\t"
                            (cadddr accepted) "\t" (nth 4 accepted) "\t"
                            (if (nth 2 one-result)
                              (rtos (car (nth 2 one-result)) 2 6) "") "\t"
                            (if (nth 2 one-result)
                              (rtos (cadr (nth 2 one-result)) 2 6) "") "\t"
                            (if (nth 3 one-result)
                              (rtos (car (nth 3 one-result)) 2 6) "") "\t"
                            (if (nth 3 one-result)
                              (rtos (cadr (nth 3 one-result)) 2 6) "") "\t"
                            (itoa (getvar "CMDACTIVE")) "\t"
                            (getvar "CMDNAMES") "\t"
                            (if (nth 4 one-result) (nth 4 one-result) ""))))))))))

          (if batch-isolated
            (progn
              (setq cx:*fb-phase* "UNISOLATE_MULTI_SOURCE")
              (if (not (cx:fb-unisolate-objects))
                (setq failures (append failures (list "BATCH:UNISOLATE_FAILED"))))
              (setq cx:*fb-object-isolated* nil)))
          (cx:cb-show-handles all-added)
          (if all-added (vl-catch-all-apply 'command-s (list "_.REGEN")))

          (cond
            (structural-failure nil)
            ((= segment-count target-count)
              (setq status "PASS" detail "ALL_NATIVE_TYPED_DIMENSIONS_ACCEPTED"))
            ((> segment-count 0)
              (setq status "PARTIAL"
                    detail "SUCCESSFUL_NATIVE_OBJECTS_PRESERVED_FAILED_SUBSETS_REPORTED"))
            (t (setq detail "NO_NATIVE_TYPED_DIMENSION_ACCEPTED")))
          (if (and (= status "PASS") cx:*full-batch-save-on-success*)
            (vla-Save doc))))))

  (setq cx:*fb-phase* "WRITE_REPORT"
        elapsed (- (getvar "MILLISECS") started)
        summary
          (list
            "STATUS\tDETAIL\tTASK_COUNT\tTARGET_SEGMENTS\tSUCCESS_COUNT\tROAD_COUNT\tSHORE_COUNT\tADDED_HANDLES\tFAILED\tCLEANUP_DELETED\tCLEAN_SLATE_DELETED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
            (strcat status "\t" detail "\t" (itoa task-count) "\t"
              (itoa target-count) "\t" (itoa segment-count) "\t"
              (itoa road-count) "\t" (itoa shore-count) "\t"
              (cx:fb-join all-added) "\t" (cx:fb-join failures) "\t"
              (cx:fb-join cleanup-deleted) "\t"
              (cx:fb-join clean-slate-deleted) "\t" (itoa elapsed) "\t"
              (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (cx:fb-write-lines cx:*full-batch-details-path* details)
  (cx:fb-write-lines cx:*full-batch-summary-path* summary)
  (setq *error* cx:*fb-old-error* cx:*fb-phase* "DONE")
  (princ))

(c:CXTDIMARCFULLBATCH)
