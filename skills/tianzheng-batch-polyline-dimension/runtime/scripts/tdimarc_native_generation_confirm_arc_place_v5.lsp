(vl-load-com)

;; Native TDIMARC prompt adapter V5.
;;
;; Verified command semantics:
;;   1. select the source polyline;
;;   2. confirm the requested arc segment with a point on that arc;
;;   3. place the dimension arc once.
;;
;; The E6 text grip is an acceptance measurement, not a second placement
;; input.  V24 incorrectly sent the dimension point where TDIMARC was still
;; asking which arc segment to use, then sent the text point as the actual
;; dimension placement.

(defun cx:tp5-dimension-point-wcs
  (geometry text-height / pm center radius unit target-radius)
  (if (or (not (listp geometry)) (/= (car geometry) "PASS"))
    nil
    (progn
      (setq pm (nth 3 geometry)
            center (nth 5 geometry)
            radius (nth 6 geometry)
            unit (cx:upx2-unit-from-center-xy center pm)
            target-radius (+ radius (* text-height cx:*ups-dimension-band-h*)))
      (if unit
        (list
          (+ (car center) (* (car unit) target-radius))
          (+ (cadr center) (* (cadr unit) target-radius))
          0.0)
        nil))))

(defun cx:tp5-confirm-point-ucs (geometry / midpoint)
  (if (and (listp geometry) (= (car geometry) "PASS"))
    (progn
      (setq midpoint (nth 3 geometry))
      (if midpoint (trans midpoint 0 1) nil))
    nil))

(defun cx:tp5-staged-tdimarc (pick confirm-point dimension-point)
  (setq cx:*sp2-last-trace* "")
  (cx:sp2-send-direct "START" "TDIMARC")
  (cx:sp2-send-direct "SELECT_OBJECT" pick)
  (cx:sp2-send-direct "CONFIRM_ARC" confirm-point)
  (cx:sp2-send-direct "FINAL_DIMENSION_POSITION" dimension-point)
  (if (/= (getvar "CMDNAMES") "")
    (cx:sp2-send-direct "FINISH" ""))
  T)

(defun cx:sp2-create-candidate
  (entity segment expected-style pick point audit-offset
    / geometry confirm-point before call-result after added valid placement)
  (setq geometry (cx:ups-arc-geometry entity segment)
        confirm-point (cx:tp5-confirm-point-ucs geometry)
        before (cx:fb-native-handles))
  (if (or (null confirm-point) (null point))
    (setq call-result nil)
    (setq call-result
      (cx:tp5-staged-tdimarc pick confirm-point point)))
  (setq after (cx:fb-native-handles)
        added (cx:fb-difference after before)
        valid
          (and (= (getvar "CMDNAMES") "")
               (cx:fb-created-object-valid-p added expected-style))
        placement
          (if valid
            (cx:pg-audit entity "ARC" segment (car added) audit-offset)
            (list 0 "INVALID_CONFIRM_ARC_SINGLE_POSITION_CANDIDATE"
              0.0 audit-offset 1e99 0)))
  (list call-result added placement valid))

(princ)
