(vl-load-com)

;; Minimal whitelist probe for TMirDim on one native Tianzheng annotation.
;; The probe never saves the drawing and accepts only TDbDimension2/TDbRadiusDim.

(if (not (boundp 'cx:*nam-target-handle*))
  (setq cx:*nam-target-handle* ""))
(if (not (boundp 'cx:*nam-expected-drawing*))
  (setq cx:*nam-expected-drawing* ""))
(if (not (boundp 'cx:*nam-summary-path*))
  (setq cx:*nam-summary-path* "C:/tmp/cx_native_annotation_mirror_summary.tsv"))
(if (not (boundp 'cx:*nam-details-path*))
  (setq cx:*nam-details-path* "C:/tmp/cx_native_annotation_mirror_details.tsv"))

(defun cx:nam-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:nam-write-lines (path lines / temporary stream line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach line lines (write-line line stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:nam-subclasses (entity / result pair)
  (setq result '())
  (foreach pair (entget entity '("*"))
    (if (= (car pair) 100)
      (setq result (append result (list (cdr pair))))))
  result)

(defun cx:nam-allowed-p (entity / classes)
  (setq classes (cx:nam-subclasses entity))
  (or (member "TDbDimension2" classes)
      (member "TDbRadiusDim" classes)))

(defun cx:nam-bbox-string (entity / object result minimum maximum min-list max-list)
  (setq object (vlax-ename->vla-object entity)
        result (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
  (if (vl-catch-all-error-p result)
    ""
    (progn
      (setq min-list (vlax-safearray->list minimum)
            max-list (vlax-safearray->list maximum))
      (strcat
        (rtos (car min-list) 2 9) "," (rtos (cadr min-list) 2 9) ","
        (rtos (caddr min-list) 2 9) "|"
        (rtos (car max-list) 2 9) "," (rtos (cadr max-list) 2 9) ","
        (rtos (caddr max-list) 2 9)))))

(defun c:CXNATIVEANNOMIRRORPROBE
  (/ started drawing entity before-data before-classes before-bbox command-result
     after-entity after-data after-classes after-bbox status detail changed elapsed)
  (setq started (getvar "MILLISECS")
        status "FAIL"
        detail "")
  (setq drawing
    (cx:nam-normalize-path
      (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))))
  (cond
    ((and (/= cx:*nam-expected-drawing* "")
          (/= drawing (cx:nam-normalize-path cx:*nam-expected-drawing*)))
      (setq detail "ACTIVE_DRAWING_MISMATCH"))
    ((null (setq entity (handent cx:*nam-target-handle*)))
      (setq detail "TARGET_HANDLE_NOT_FOUND"))
    ((not (cx:nam-allowed-p entity))
      (setq detail "TARGET_NATIVE_CLASS_NOT_WHITELISTED"))
    (t
      (setq before-data (entget entity '("*"))
            before-classes (cx:nam-subclasses entity)
            before-bbox (cx:nam-bbox-string entity)
            command-result
              (vl-catch-all-apply 'command-s (list "TMirDim" entity ""))
            after-entity (handent cx:*nam-target-handle*))
      (cond
        ((vl-catch-all-error-p command-result)
          (setq detail
            (strcat "COMMAND_ERROR:" (vl-catch-all-error-message command-result))))
        ((or (/= (getvar "CMDACTIVE") 0) (/= (getvar "CMDNAMES") ""))
          (setq detail "COMMAND_NOT_IDLE"))
        ((null after-entity)
          (setq detail "TARGET_HANDLE_REPLACED_OR_DELETED"))
        (t
          (setq after-data (entget after-entity '("*"))
                after-classes (cx:nam-subclasses after-entity)
                after-bbox (cx:nam-bbox-string after-entity)
                changed (not (equal before-data after-data)))
          (cond
            ((not (equal before-classes after-classes))
              (setq detail "NATIVE_CLASS_CHANGED"))
            ((not changed)
              (setq detail "COMMAND_ACCEPTED_BUT_OBJECT_UNCHANGED"))
            (t
              (setq status "PASS"
                    detail "SAME_NATIVE_HANDLE_MIRRORED")))))))
  (setq elapsed (- (getvar "MILLISECS") started))
  (if (null before-data) (setq before-data '()))
  (if (null after-data) (setq after-data '()))
  (if (null before-classes) (setq before-classes '()))
  (if (null after-classes) (setq after-classes '()))
  (if (null before-bbox) (setq before-bbox ""))
  (if (null after-bbox) (setq after-bbox ""))
  (cx:nam-write-lines cx:*nam-summary-path*
    (list
      "STATUS\tDETAIL\tTARGET_HANDLE\tBEFORE_CLASSES\tAFTER_CLASSES\tBEFORE_BBOX\tAFTER_BBOX\tCHANGED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t" (strcase cx:*nam-target-handle*) "\t"
        (vl-prin1-to-string before-classes) "\t"
        (vl-prin1-to-string after-classes) "\t"
        before-bbox "\t" after-bbox "\t"
        (if changed "YES" "NO") "\t" (itoa elapsed) "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (cx:nam-write-lines cx:*nam-details-path*
    (list
      "PHASE\tENTITY_STATE"
      (strcat "BEFORE\t" (vl-prin1-to-string before-data))
      (strcat "AFTER\t" (vl-prin1-to-string after-data))))
  (princ))

(c:CXNATIVEANNOMIRRORPROBE)
