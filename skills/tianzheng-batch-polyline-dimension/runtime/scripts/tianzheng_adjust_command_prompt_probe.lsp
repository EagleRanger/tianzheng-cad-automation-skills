(vl-load-com)

;; Prompt/state probe for a short whitelist of Tianzheng adjustment commands.
;; The target is copied to a temporary location, probed, and deleted.  The
;; original entity is never passed to the command and the drawing is not saved.

(if (not (boundp 'cx:*prompt-command*)) (setq cx:*prompt-command* "TArrangeDim"))
(if (not (boundp 'cx:*prompt-stage*)) (setq cx:*prompt-stage* "FIRST_PROMPT"))
(if (not (boundp 'cx:*prompt-target-handle*)) (setq cx:*prompt-target-handle* ""))
(if (not (boundp 'cx:*prompt-expected-drawing*)) (setq cx:*prompt-expected-drawing* ""))
(if (not (boundp 'cx:*prompt-summary-path*))
  (setq cx:*prompt-summary-path* "C:/tmp/cx_tz_adjust_prompt_summary.tsv"))

(defun cx:pp-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:pp-safe-property (object property / result)
  (setq result (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (vl-catch-all-error-p result) "" (vl-princ-to-string result)))

(defun cx:pp-write-lines (path lines / temporary stream line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq stream (open temporary "w"))
  (foreach line lines (write-line line stream))
  (close stream)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:pp-bbox-string (object / result minimum maximum min-list max-list)
  (setq result (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
  (if (vl-catch-all-error-p result)
    ""
    (progn
      (setq min-list (vlax-safearray->list minimum)
            max-list (vlax-safearray->list maximum))
      (strcat
        (rtos (car min-list) 2 9) "," (rtos (cadr min-list) 2 9) "|"
        (rtos (car max-list) 2 9) "," (rtos (cadr max-list) 2 9)))))

(defun cx:pp-bbox-list (object / result minimum maximum)
  (setq result (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
  (if (vl-catch-all-error-p result)
    nil
    (append (vlax-safearray->list minimum) (vlax-safearray->list maximum))))

(defun cx:pp-near (a b) (< (abs (- a b)) 0.000001))

(defun cx:pp-clean-shifted-clones (source-object / doc space index count item source-box item-box)
  ;; Recover only stale clones created by this probe: every min/max coordinate
  ;; must be the source bbox translated by exactly (+30,+30,0).
  (setq source-box (cx:pp-bbox-list source-object)
        doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        index 0 count (vla-get-Count space))
  (if source-box
    (repeat count
      (setq item (vl-catch-all-apply 'vla-Item (list space index)))
      (if (and (not (vl-catch-all-error-p item)) item
               (/= (vla-get-Handle item) (vla-get-Handle source-object))
               (= (vla-get-ObjectName item) "TDbDimension2")
               (= (vla-get-Layer item) "PUB_DIM")
               (= (cx:pp-safe-property item 'DimStyle) (cx:pp-safe-property source-object 'DimStyle))
               (setq item-box (cx:pp-bbox-list item))
               (cx:pp-near (nth 0 item-box) (+ 30.0 (nth 0 source-box)))
               (cx:pp-near (nth 1 item-box) (+ 30.0 (nth 1 source-box)))
               (cx:pp-near (nth 2 item-box) (nth 2 source-box))
               (cx:pp-near (nth 3 item-box) (+ 30.0 (nth 3 source-box)))
               (cx:pp-near (nth 4 item-box) (+ 30.0 (nth 4 source-box)))
               (cx:pp-near (nth 5 item-box) (nth 5 source-box)))
        (vl-catch-all-apply 'vla-Delete (list item)))
      (setq index (1+ index)))))

(defun cx:pp-native-handles (/ doc space index count item result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        index 0 count (vla-get-Count space) result '())
  (repeat count
    (setq item (vla-Item space index))
    (if (= (vla-get-ObjectName item) "TDbDimension2")
      (setq result (cons (vla-get-Handle item) result)))
    (setq index (1+ index)))
  (vl-sort result '<))

(defun c:CXTZADJUSTPROMPTPROBE
  (/ started drawing command stage source source-object copied clone clone-handle
     clone-before clone-after result error-text last-prompt before-handles after-handles
     during-active during-names status detail cleanup-result elapsed)
  (setq started (getvar "MILLISECS")
        drawing (cx:pp-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")))
        command (strcase cx:*prompt-command*)
        stage (strcase cx:*prompt-stage*)
        status "FAIL" detail "" error-text "" last-prompt "")
  (cond
    ((and (/= cx:*prompt-expected-drawing* "")
          (/= drawing (cx:pp-normalize-path cx:*prompt-expected-drawing*)))
      (setq detail "ACTIVE_DRAWING_MISMATCH"))
    ((not (member command '("TARRANGEDIM" "TDIMADJUST" "TMOVE" "TDRAGMOVE")))
      (setq detail "COMMAND_NOT_WHITELISTED"))
    ((not (member stage '("FIRST_PROMPT" "SELECT_CLONE_CANCEL" "APPLY_CLONE")))
      (setq detail "STAGE_NOT_WHITELISTED"))
    ((null (setq source (handent cx:*prompt-target-handle*)))
      (setq detail "TARGET_HANDLE_NOT_FOUND"))
    ((/= (vla-get-ObjectName (setq source-object (vlax-ename->vla-object source)))
         "TDbDimension2")
      (setq detail "TARGET_IS_NOT_TDBDIMENSION2"))
    (t
      (cx:pp-clean-shifted-clones source-object)
      (setq before-handles (cx:pp-native-handles)
            copied (vl-catch-all-apply 'vla-Copy (list source-object)))
      (if (vl-catch-all-error-p copied)
        (setq detail (strcat "COPY_ERROR:" (vl-catch-all-error-message copied)))
        (progn
          (vla-Move copied
            (vlax-3d-point '(0.0 0.0 0.0))
            (vlax-3d-point '(30.0 30.0 0.0)))
          (setq clone (vlax-vla-object->ename copied)
                clone-handle (vla-get-Handle copied)
                clone-before (cx:pp-bbox-string copied)
                result
                  (cond
                    ((= stage "APPLY_CLONE")
                      (vl-catch-all-apply 'command-s (list command clone "")))
                    ((= stage "FIRST_PROMPT")
                      (vl-catch-all-apply 'command-s (list command nil)))
                    (t
                      (vl-catch-all-apply 'command-s (list command clone "" nil))))
                last-prompt ""
                during-active (getvar "CMDACTIVE")
                during-names (getvar "CMDNAMES")
                clone-after (if (and clone (entget clone))
                              (cx:pp-bbox-string (vlax-ename->vla-object clone)) ""))
          (if (vl-catch-all-error-p result)
            (setq error-text (vl-catch-all-error-message result)))
          (if (or (/= (getvar "CMDACTIVE") 0) (/= (getvar "CMDNAMES") ""))
            (vl-catch-all-apply 'command (list nil)))
          (if (or (/= (getvar "CMDACTIVE") 0) (/= (getvar "CMDNAMES") ""))
            (setq detail "COMMAND_NOT_IDLE_AFTER_CANCEL")
            (setq status "PASS"
                  detail (if (= clone-before clone-after)
                           "CLONE_UNCHANGED" "CLONE_CHANGED")))
          (if (and clone (entget clone)) (entdel clone))
          (setq after-handles (cx:pp-native-handles))
          (if (not (equal before-handles after-handles))
            (setq status "FAIL" detail "TEMPORARY_NATIVE_SET_NOT_RESTORED"))))))
  (setq elapsed (- (getvar "MILLISECS") started))
  (cx:pp-write-lines cx:*prompt-summary-path*
    (list
      "STATUS\tDETAIL\tCOMMAND\tSTAGE\tTARGET_HANDLE\tCLONE_HANDLE\tCLONE_BBOX_BEFORE\tCLONE_BBOX_AFTER\tLASTPROMPT\tERROR_TEXT\tDURING_CMDACTIVE\tDURING_CMDNAMES\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t" command "\t" stage "\t"
        cx:*prompt-target-handle* "\t" (if clone-handle clone-handle "") "\t"
        (if clone-before clone-before "") "\t" (if clone-after clone-after "") "\t"
        last-prompt "\t" error-text "\t"
        (if during-active (itoa during-active) "") "\t"
        (if during-names during-names "") "\t" (itoa elapsed) "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (princ))

(c:CXTZADJUSTPROMPTPROBE)
