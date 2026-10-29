(vl-load-com)

;; Generic post-command settlement for the five-stage native TDIMARC route.
;; Run217 proved that a completed candidate can occasionally leave TDIMARC in
;; its repeat loop.  Starting the next TDIMARC while that loop is active feeds
;; a command name into the old point prompt and aborts the whole batch.
;;
;; Keep the verified five business inputs unchanged.  After the existing
;; FINISH token, issue the already validated AutoLISP cancel primitive exactly
;; once only when CMDNAMES is still non-empty.  Never start a new native command
;; unless the previous command state is idle.

(defun cx:ps1-command-idle-p ()
  (= (getvar "CMDNAMES") ""))

(defun cx:ps1-cancel-stuck-after-finish (/)
  (if (not (cx:ps1-command-idle-p))
    (progn
      (cx:sp2-write-stage "CANCEL_STUCK_AFTER_FINISH" "BEFORE")
      (command)
      (cx:sp2-write-stage "CANCEL_STUCK_AFTER_FINISH" "AFTER")))
  (cx:ps1-command-idle-p))

(defun cx:gm1-staged-tdimarc
  (pick-wcs confirm-wcs dimension-point-ucs
    / pick-ucs confirm-ucs final-ucs)
  (setq cx:*sp2-last-trace* ""
        pick-ucs (cx:gm1-wcs-to-active-ucs-plane pick-wcs)
        confirm-ucs (cx:gm1-wcs-to-active-ucs-plane confirm-wcs)
        final-ucs (cx:gm1-active-ucs-plane dimension-point-ucs))
  (cond
    ((not (cx:ps1-command-idle-p))
      (error "TDIMARC_PRESTART_COMMAND_NOT_IDLE"))
    ((not (and pick-ucs confirm-ucs final-ucs)) nil)
    (T
      (cx:sp2-send-direct "START" "TDIMARC")
      (cx:sp2-send-direct "SELECT_OBJECT_UCS_PLANE_Z0" pick-ucs)
      (cx:sp2-send-direct "CONFIRM_ARC_UCS_PLANE_Z0" confirm-ucs)
      (cx:sp2-send-direct
        "FINAL_DIMENSION_POSITION_UCS_PLANE_Z0" final-ucs)
      (if (not (cx:ps1-command-idle-p))
        (cx:sp2-send-direct "FINISH" ""))
      (if (not (cx:ps1-cancel-stuck-after-finish))
        (error "TDIMARC_POSTFINISH_COMMAND_NOT_IDLE"))
      T)))

(princ)
