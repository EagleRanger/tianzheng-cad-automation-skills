(vl-load-com)

;; One-object native Tianzheng dimension adjustment probe.
;; Whitelist modes: MIRROR and MOVE_VECTOR.  The probe never saves the drawing.

(if (not (boundp 'cx:*adjust-target-handle*))
  (setq cx:*adjust-target-handle* ""))
(if (not (boundp 'cx:*adjust-expected-drawing*))
  (setq cx:*adjust-expected-drawing* ""))
(if (not (boundp 'cx:*adjust-mode*))
  (setq cx:*adjust-mode* "MIRROR"))
(if (not (boundp 'cx:*adjust-move-x*))
  (setq cx:*adjust-move-x* 0.0))
(if (not (boundp 'cx:*adjust-move-y*))
  (setq cx:*adjust-move-y* 0.0))
(if (not (boundp 'cx:*adjust-summary-path*))
  (setq cx:*adjust-summary-path* "C:/tmp/cx_tdimarc_adjust_summary.tsv"))
(if (not (boundp 'cx:*adjust-details-path*))
  (setq cx:*adjust-details-path* "C:/tmp/cx_tdimarc_adjust_details.tsv"))

(defun cx:adjust-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:adjust-safe-property (object property / result)
  (setq result (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (vl-catch-all-error-p result) "" (vl-princ-to-string result)))

(defun cx:adjust-write-lines (path lines / temporary stream line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach line lines (write-line line stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:adjust-native-handles (/ doc space count index item result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        count (vla-get-Count space)
        index 0
        result '())
  (repeat count
    (setq item (vla-Item space index))
    (if (= (vla-get-ObjectName item) "TDbDimension2")
      (setq result (cons (vla-get-Handle item) result)))
    (setq index (1+ index)))
  (vl-sort result '<))

(defun cx:adjust-bbox-string (object / result minimum maximum min-list max-list)
  (setq result
    (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
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

(defun cx:adjust-object-state (entity / object)
  (if entity
    (progn
      (setq object (vlax-ename->vla-object entity))
      (list
        (vla-get-ObjectName object)
        (vla-get-Layer object)
        (cx:adjust-safe-property object 'DimStyle)
        (cx:adjust-bbox-string object)
        (vl-prin1-to-string (entget entity '("*")))))
    (list "" "" "" "" "")))

(defun cx:adjust-join (items / output item)
  (setq output "")
  (foreach item items
    (setq output (strcat output (if (= output "") "" ",") item)))
  output)

(defun c:CXTDIMARCADJUSTPROBE
  (/ started drawing entity before-state before-handles before-count command-result
     after-entity after-state after-handles after-count same-handle same-native-set
     changed expected-style status detail elapsed summary details)
  (setq started (getvar "MILLISECS")
        status "FAIL"
        detail ""
        command-result nil)
  (setq drawing
    (cx:adjust-normalize-path
      (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))))
  (cond
    ((and (/= cx:*adjust-expected-drawing* "")
          (/= drawing (cx:adjust-normalize-path cx:*adjust-expected-drawing*)))
      (setq detail "ACTIVE_DRAWING_MISMATCH"))
    ((not (member (strcase cx:*adjust-mode*) '("MIRROR" "MOVE_VECTOR")))
      (setq detail "MODE_NOT_WHITELISTED"))
    ((and (= (strcase cx:*adjust-mode*) "MOVE_VECTOR")
          (< (distance '(0.0 0.0 0.0)
               (list cx:*adjust-move-x* cx:*adjust-move-y* 0.0))
             0.000000001))
      (setq detail "MOVE_VECTOR_IS_ZERO"))
    ((null (setq entity (handent cx:*adjust-target-handle*)))
      (setq detail "TARGET_HANDLE_NOT_FOUND"))
    ((/= (vla-get-ObjectName (vlax-ename->vla-object entity)) "TDbDimension2")
      (setq detail "TARGET_IS_NOT_TDBDIMENSION2"))
    (t
      (setq before-state (cx:adjust-object-state entity)
            before-handles (cx:adjust-native-handles)
            before-count (length before-handles)
            command-result
              (if (= (strcase cx:*adjust-mode*) "MIRROR")
                (vl-catch-all-apply
                  'command-s
                  (list "TMirDim" entity ""))
                (vl-catch-all-apply
                  'command-s
                  (list "_.MOVE" entity "" '(0.0 0.0 0.0)
                    (list cx:*adjust-move-x* cx:*adjust-move-y* 0.0))))
            after-entity (handent cx:*adjust-target-handle*)
            after-state (cx:adjust-object-state after-entity)
            after-handles (cx:adjust-native-handles)
            after-count (length after-handles)
            same-handle (not (null after-entity))
            same-native-set (equal before-handles after-handles)
            changed (not (equal before-state after-state))
            expected-style (caddr before-state))
      (cond
        ((vl-catch-all-error-p command-result)
          (setq detail
            (strcat "COMMAND_ERROR:" (vl-catch-all-error-message command-result))))
        ((or (/= (getvar "CMDACTIVE") 0) (/= (getvar "CMDNAMES") ""))
          (setq detail "COMMAND_NOT_IDLE"))
        ((not same-handle)
          (setq detail "TARGET_HANDLE_REPLACED_OR_DELETED"))
        ((not same-native-set)
          (setq detail "NATIVE_DIMENSION_SET_CHANGED"))
        ((or (/= before-count after-count)
             (/= (car after-state) "TDbDimension2")
             (/= (cadr after-state) "PUB_DIM")
             (/= (caddr after-state) expected-style))
          (setq detail "NATIVE_OBJECT_CONTRACT_CHANGED"))
        ((not changed)
          (setq detail "COMMAND_ACCEPTED_BUT_OBJECT_UNCHANGED"))
        (t
          (setq status "PASS"
                detail
                  (if (= (strcase cx:*adjust-mode*) "MIRROR")
                    "SAME_NATIVE_HANDLE_MIRRORED"
                    "SAME_NATIVE_HANDLE_MOVED"))))))
  (setq elapsed (- (getvar "MILLISECS") started))
  (if (null before-state) (setq before-state (list "" "" "" "" "")))
  (if (null after-state) (setq after-state (list "" "" "" "" "")))
  (setq summary
    (list
      "STATUS\tDETAIL\tMODE\tTARGET_HANDLE\tMOVE_X\tMOVE_Y\tBEFORE_COUNT\tAFTER_COUNT\tBEFORE_BBOX\tAFTER_BBOX\tCHANGED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t" (strcase cx:*adjust-mode*) "\t"
        cx:*adjust-target-handle* "\t"
        (rtos cx:*adjust-move-x* 2 9) "\t" (rtos cx:*adjust-move-y* 2 9) "\t"
        (if before-count (itoa before-count) "0") "\t"
        (if after-count (itoa after-count) "0") "\t"
        (nth 3 before-state) "\t" (nth 3 after-state) "\t"
        (if changed "YES" "NO") "\t" (itoa elapsed) "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (setq details
    (list
      "PHASE\tOBJECT_NAME\tLAYER\tDIM_STYLE\tBBOX\tNATIVE_HANDLES\tENTITY_STATE"
      (strcat "BEFORE\t" (car before-state) "\t" (cadr before-state) "\t"
        (caddr before-state) "\t" (nth 3 before-state) "\t"
        (if before-handles (cx:adjust-join before-handles) "") "\t"
        (nth 4 before-state))
      (strcat "AFTER\t" (car after-state) "\t" (cadr after-state) "\t"
        (caddr after-state) "\t" (nth 3 after-state) "\t"
        (if after-handles (cx:adjust-join after-handles) "") "\t"
        (nth 4 after-state))))
  (cx:adjust-write-lines cx:*adjust-summary-path* summary)
  (cx:adjust-write-lines cx:*adjust-details-path* details)
  (princ))

(c:CXTDIMARCADJUSTPROBE)
