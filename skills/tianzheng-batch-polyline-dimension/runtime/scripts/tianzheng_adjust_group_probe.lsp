(vl-load-com)

;; Reversible group probe for native Tianzheng dimension adjustment commands.
;; Copies the requested TDbDimension2 objects by a fixed vector, calls the
;; whitelisted command on the copies, records geometry changes, and deletes
;; every temporary object.  The source objects are never selected or changed.

(if (not (boundp 'cx:*group-command*)) (setq cx:*group-command* "TDimAdjust"))
(if (not (boundp 'cx:*group-target-handles*)) (setq cx:*group-target-handles* '()))
(if (not (boundp 'cx:*group-expected-drawing*)) (setq cx:*group-expected-drawing* ""))
(if (not (boundp 'cx:*group-summary-path*))
  (setq cx:*group-summary-path* "C:/tmp/cx_tz_adjust_group_summary.tsv"))

(defun cx:gp-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:gp-write-lines (path lines / temporary stream line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach line lines (write-line line stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:gp-bbox-string (object / result minimum maximum min-list max-list)
  (setq result (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
  (if (vl-catch-all-error-p result)
    ""
    (progn
      (setq min-list (vlax-safearray->list minimum)
            max-list (vlax-safearray->list maximum))
      (strcat
        (rtos (car min-list) 2 9) "," (rtos (cadr min-list) 2 9) "|"
        (rtos (car max-list) 2 9) "," (rtos (cadr max-list) 2 9)))))

(defun cx:gp-native-handles (/ doc space index count item result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        index 0 count (vla-get-Count space) result '())
  (repeat count
    (setq item (vla-Item space index))
    (if (= (vla-get-ObjectName item) "TDbDimension2")
      (setq result (cons (vla-get-Handle item) result)))
    (setq index (1+ index)))
  (vl-sort result '<))

(defun cx:gp-delete-clones (clones / clone)
  (foreach clone clones
    (if (and clone (not (vlax-erased-p clone)))
      (vl-catch-all-apply 'vla-Delete (list clone)))))

(defun cx:gp-join (items separator / result item)
  (setq result "")
  (foreach item items
    (setq result (if (= result "") item (strcat result separator item))))
  result)

(defun c:CXTZADJUSTGROUPPROBE
  (/ started drawing command source-handles before-handles after-handles
     source clone clones clone-enames clone-handles before-boxes after-boxes
     selection-set result error-text status detail elapsed index)
  (setq started (getvar "MILLISECS")
        drawing (cx:gp-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))
        command (strcase cx:*group-command*)
        source-handles cx:*group-target-handles*
        clones '() clone-enames '() clone-handles '() before-boxes '()
        after-boxes '() error-text "" status "FAIL" detail "")
  (cond
    ((and (/= cx:*group-expected-drawing* "")
          (/= drawing (cx:gp-normalize-path cx:*group-expected-drawing*)))
      (setq detail "ACTIVE_DRAWING_MISMATCH"))
    ((not (member command '("TDIMADJUST")))
      (setq detail "COMMAND_NOT_WHITELISTED"))
    ((< (length source-handles) 2)
      (setq detail "AT_LEAST_TWO_TARGETS_REQUIRED"))
    (t
      (setq before-handles (cx:gp-native-handles))
      (foreach handle source-handles
        (if (and (setq source (handent handle))
                 (= (vla-get-ObjectName (setq source (vlax-ename->vla-object source)))
                    "TDbDimension2"))
          (progn
            (setq clone (vl-catch-all-apply 'vla-Copy (list source)))
            (if (vl-catch-all-error-p clone)
              (setq detail (strcat "COPY_ERROR:" (vl-catch-all-error-message clone)))
              (progn
                (vla-Move clone
                  (vlax-3d-point '(0.0 0.0 0.0))
                  (vlax-3d-point '(30.0 30.0 0.0)))
                (setq clones (cons clone clones)
                      clone-enames (cons (vlax-vla-object->ename clone) clone-enames)
                      clone-handles (cons (vla-get-Handle clone) clone-handles)
                      before-boxes (cons (cx:gp-bbox-string clone) before-boxes)))))
          (setq detail (strcat "INVALID_TARGET:" handle))))
      (if (= (length clones) (length source-handles))
        (progn
          (setq selection-set (ssadd))
          (foreach clone-ename clone-enames (ssadd clone-ename selection-set))
          (setq result (vl-catch-all-apply 'command-s (list command selection-set "")))
          (if (vl-catch-all-error-p result)
            (setq error-text (vl-catch-all-error-message result)))
          (foreach clone (reverse clones)
            (setq after-boxes (cons (cx:gp-bbox-string clone) after-boxes)))
          (setq clone-handles (reverse clone-handles)
                before-boxes (reverse before-boxes)
                after-boxes (reverse after-boxes))
          (if (or (/= (getvar "CMDACTIVE") 0) (/= (getvar "CMDNAMES") ""))
            (progn
              (vl-catch-all-apply 'command (list nil))
              (setq detail "COMMAND_NOT_IDLE_AFTER_CANCEL"))
            (setq status "PASS"
                  detail (if (equal before-boxes after-boxes)
                           "GROUP_UNCHANGED" "GROUP_CHANGED")))))
      (cx:gp-delete-clones clones)
      (setq after-handles (cx:gp-native-handles))
      (if (not (equal before-handles after-handles))
        (setq status "FAIL" detail "TEMPORARY_NATIVE_SET_NOT_RESTORED"))))
  (setq elapsed (- (getvar "MILLISECS") started))
  (cx:gp-write-lines cx:*group-summary-path*
    (list
      "STATUS\tDETAIL\tCOMMAND\tTARGET_HANDLES\tCLONE_HANDLES\tBBOX_BEFORE\tBBOX_AFTER\tERROR_TEXT\tELAPSED_MS\tNATIVE_BEFORE\tNATIVE_AFTER\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t" command "\t"
        (cx:gp-join source-handles ",") "\t"
        (cx:gp-join clone-handles ",") "\t"
        (cx:gp-join before-boxes ";") "\t"
        (cx:gp-join after-boxes ";") "\t"
        error-text "\t" (itoa elapsed) "\t"
        (if before-handles (itoa (length before-handles)) "") "\t"
        (if after-handles (itoa (length after-handles)) "") "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (princ))

(c:CXTZADJUSTGROUPPROBE)
