(vl-load-com)

;; Batch TMirDim probe for native Tianzheng angle dimensions.
;; The caller owns the drawing and provides an explicit handle file.  Only
;; TDbDimension2 objects are accepted; radius dimensions and all other objects
;; are rejected.  The drawing is deliberately not saved here.

(if (not (boundp 'cx:*namb-handles-path*))
  (setq cx:*namb-handles-path* "C:/tmp/cx_native_angle_mirror_handles.txt"))
(if (not (boundp 'cx:*namb-expected-drawing*))
  (setq cx:*namb-expected-drawing* ""))
(if (not (boundp 'cx:*namb-summary-path*))
  (setq cx:*namb-summary-path* "C:/tmp/cx_native_angle_mirror_batch_summary.tsv"))
(if (not (boundp 'cx:*namb-details-path*))
  (setq cx:*namb-details-path* "C:/tmp/cx_native_angle_mirror_batch_details.tsv"))

(defun cx:namb-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:namb-write-lines (path lines / temporary stream line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach line lines (write-line line stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:namb-read-lines (path / stream line result)
  (setq result '())
  (if (setq stream (open path "r"))
    (progn
      (while (setq line (read-line stream))
        (if (/= (vl-string-trim " \t\r\n" line) "")
          (setq result (append result (list (strcase (vl-string-trim " \t\r\n" line)))))))
      (close stream)))
  result)

(defun cx:namb-subclasses (entity / result pair)
  (setq result '())
  (foreach pair (entget entity '("*"))
    (if (= (car pair) 100)
      (setq result (append result (list (cdr pair))))))
  result)

(defun cx:namb-angle-p (entity)
  (member "TDbDimension2" (cx:namb-subclasses entity)))

(defun c:CXNATIVEANGLEMIRRORBATCH
  (/ started drawing handles rows requested processed passed failed handle entity
     before-data command-result after-entity after-data status detail elapsed toggled)
  (setq started (getvar "MILLISECS")
        drawing (cx:namb-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))
        handles (cx:namb-read-lines cx:*namb-handles-path*)
        rows (list "HANDLE\tSTATUS\tDETAIL\tCHANGED")
        requested (length handles)
        processed 0 passed 0 failed 0
        status "FAIL" detail "" toggled '())
  (cond
    ((and (/= cx:*namb-expected-drawing* "")
          (/= drawing (cx:namb-normalize-path cx:*namb-expected-drawing*)))
      (setq detail "ACTIVE_DRAWING_MISMATCH"))
    ((= requested 0)
      (setq detail "EMPTY_HANDLE_LIST"))
    (t
      ;; Validate the complete target set before changing any object.  This
      ;; prevents a missing/wrong-class handle from leaving a half-toggled run.
      (foreach handle handles
        (setq processed (1+ processed)
              entity (handent handle))
        (cond
          ((null entity)
            (setq failed (1+ failed)
                  rows (append rows (list (strcat handle "\tFAIL\tTARGET_NOT_FOUND\tNO")))))
          ((not (cx:namb-angle-p entity))
            (setq failed (1+ failed)
                  rows (append rows (list (strcat handle "\tFAIL\tNOT_TDBDIMENSION2\tNO")))))))
      (if (> failed 0)
        (setq detail "PREVALIDATION_FAILED")
        (progn
          (setq processed 0 rows (list "HANDLE\tSTATUS\tDETAIL\tCHANGED"))
          (foreach handle handles
            (setq processed (1+ processed)
                  entity (handent handle)
                  before-data (entget entity '("*"))
                  command-result (vl-catch-all-apply 'command-s (list "TMirDim" entity ""))
                  after-entity (handent handle))
            (cond
              ((vl-catch-all-error-p command-result)
                (setq failed (1+ failed)
                      rows (append rows
                        (list (strcat handle "\tFAIL\tCOMMAND_ERROR\tNO")))))
              ((or (/= (getvar "CMDACTIVE") 0) (/= (getvar "CMDNAMES") ""))
                (setq failed (1+ failed)
                      rows (append rows
                        (list (strcat handle "\tFAIL\tCOMMAND_NOT_IDLE\tNO")))))
              ((null after-entity)
                (setq failed (1+ failed)
                      rows (append rows
                        (list (strcat handle "\tFAIL\tTARGET_REPLACED_OR_DELETED\tNO")))))
              (t
                (setq after-data (entget after-entity '("*")))
                (if (equal before-data after-data)
                  (setq failed (1+ failed)
                        rows (append rows
                          (list (strcat handle "\tFAIL\tOBJECT_UNCHANGED\tNO"))))
                  (setq passed (1+ passed)
                        toggled (append toggled (list handle))
                        rows (append rows
                          (list (strcat handle "\tPASS\tSAME_NATIVE_HANDLE_MIRRORED\tYES"))))))))
          ;; A batch is accepted only as an atomic state change.  If any native
          ;; command fails, restore every object already toggled in this call.
          (if (> failed 0)
            (progn
              (foreach handle toggled
                (if (setq entity (handent handle))
                  (vl-catch-all-apply 'command-s (list "TMirDim" entity ""))))
              (setq passed 0 detail "COMMAND_FAILED_ROLLED_BACK"))
            (setq detail "BATCH_MIRROR_COMPLETE"))))
      (setq status (if (= failed 0) "PASS" "FAIL")
            detail (if (= failed 0) detail (if (= detail "") "ONE_OR_MORE_TARGETS_FAILED" detail)))))
  (setq elapsed (- (getvar "MILLISECS") started))
  (cx:namb-write-lines cx:*namb-details-path* rows)
  (cx:namb-write-lines cx:*namb-summary-path*
    (list
      "STATUS\tDETAIL\tREQUESTED\tPROCESSED\tPASSED\tFAILED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t" (itoa requested) "\t" (itoa processed) "\t"
        (itoa passed) "\t" (itoa failed) "\t" (itoa elapsed) "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (princ))

(c:CXNATIVEANGLEMIRRORBATCH)
