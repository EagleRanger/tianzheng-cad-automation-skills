(vl-load-com)

;; Validation-only TDIMARC prompt adapter V2.
;; V1 called COMMAND through VL-CATCH-ALL-APPLY, so Tianzheng never entered
;; the native final-position prompt.  V2 deliberately submits every token from
;; the normal CAD command context.  The verified V12 primary generator stays
;; unchanged; only a preserved rank-1 candidate reaches this adapter.

(setq cx:*sp2-last-trace* "UNSET")
(if (not (boundp 'cx:*sp2-stage-trace-path*))
  (setq cx:*sp2-stage-trace-path* nil))

(defun cx:sp2-clean-text (value / text)
  (setq text (vl-princ-to-string value))
  (vl-string-translate "\t\r\n" "   " text))

(defun cx:sp2-stage-line (stage phase)
  (strcat stage "\t" phase
    "\t" (itoa (getvar "CMDACTIVE"))
    "\t" (cx:sp2-clean-text (getvar "CMDNAMES"))
    "\t" (cx:sp2-clean-text (getvar "LASTPROMPT"))))

(defun cx:sp2-write-stage (stage phase / existed stream line)
  (setq line (cx:sp2-stage-line stage phase)
        cx:*sp2-last-trace*
          (strcat cx:*sp2-last-trace*
            (if (= cx:*sp2-last-trace* "") "" "|") line))
  (if (and cx:*sp2-stage-trace-path*
           (/= cx:*sp2-stage-trace-path* ""))
    (progn
      (setq existed (findfile cx:*sp2-stage-trace-path*)
            stream
              (open cx:*sp2-stage-trace-path*
                (if existed "a" "w")))
      (if stream
        (progn
          (if (not existed)
            (write-line "STAGE\tPHASE\tCMDACTIVE\tCMDNAMES\tLASTPROMPT"
              stream))
          (write-line line stream)
          (close stream)))))
  line)

(defun cx:sp2-send-direct (stage value)
  (cx:sp2-write-stage stage "BEFORE")
  ;; Intentionally direct.  Do not wrap COMMAND in VL-CATCH-ALL-APPLY and do
  ;; not call this function from a caught settlement frame.
  (command value)
  (cx:sp2-write-stage stage "AFTER")
  T)

(defun cx:sp2-staged-tdimarc (pick point)
  (setq cx:*sp2-last-trace* "")
  (cx:sp2-send-direct "START" "TDIMARC")
  (cx:sp2-send-direct "SELECT_ARC" pick)
  (cx:sp2-send-direct "CONFIRM_PREVIEW" pick)
  (cx:sp2-send-direct "FINAL_POSITION" point)
  (cx:sp2-send-direct "FINISH" "")
  T)

(defun cx:sp2-create-candidate
  (entity segment expected-style pick point audit-offset
    / before call-result after added valid placement)
  (setq before (cx:fb-native-handles)
        call-result (cx:sp2-staged-tdimarc pick point)
        after (cx:fb-native-handles)
        added (cx:fb-difference after before)
        valid
          (and (= (getvar "CMDNAMES") "")
               (cx:fb-created-object-valid-p added expected-style))
        placement
          (if valid
            (cx:pg-audit entity "ARC" segment (car added) audit-offset)
            (list 0 "INVALID_DIRECT_STAGED_CREATION_CANDIDATE"
              0.0 audit-offset 1e99 0)))
  (list call-result added placement valid))

;; V5 settlement resolves these symbols dynamically.  Only its correction
;; candidates use the direct prompt adapter.
(defun cx:cs-create-candidate
  (entity segment expected-style pick point audit-offset)
  (cx:sp2-create-candidate
    entity segment expected-style pick point audit-offset))

(defun cx:cs-correction-detail
  (index cursor-offset added placement accepted)
  (strcat
    "CREATION_DIRECT_STAGED_FINAL_POINT_" (itoa index)
    "{cursor=" (rtos (cx:cs-safe-number cursor-offset 0.0) 2 9)
    ",added=" (cx:fb-join added)
    ",accepted=" (if accepted "YES" "NO")
    "," (cx:cs-safe-audit-diagnostic placement)
    ",prompt_trace=" cx:*sp2-last-trace* "}"))

(defun cx:cs-opposite-detail (cursor-offset added placement accepted)
  (strcat
    "CREATION_DIRECT_STAGED_OPPOSITE_FINAL_POINT_1"
    "{cursor=" (rtos (cx:cs-safe-number cursor-offset 0.0) 2 9)
    ",added=" (cx:fb-join added)
    ",accepted=" (if accepted "YES" "NO")
    "," (cx:cs-safe-audit-diagnostic placement)
    ",prompt_trace=" cx:*sp2-last-trace* "}"))

;; The V5 wrapper itself used VL-CATCH-ALL-APPLY around the settlement core.
;; That enclosing catch is enough to make direct COMMAND illegal.  The V2
;; single-target validation path calls the same transactional core directly.
(defun cx:cs-settle-final-result
  (entity segment offset expected-style result)
  (cx:cs-settle-final-result-core
    entity segment offset expected-style result))

;; Preserve the ordinary V12 dispatcher byte-for-byte.  The builder renames it
;; before appending this adapter.
(defun cx:fb-run-one (entity segment offset expected-style)
  (cx:sp2-v12-run-one entity segment offset expected-style))

(princ)

