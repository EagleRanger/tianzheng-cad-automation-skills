(vl-load-com)

;; Plan-view endpoint gate.  Native Tianzheng dimensions are planar objects
;; whose grips may be at WCS Z=0 even when the source polyline elevation is not
;; zero.  V5 associates grip2/grip3 by WCS XY and records Z only diagnostically.
(defun cx:pg-audit
  (entity segment-type segment dimension-handle offset
    / source-object source-handle result)
  (setq source-object (vlax-ename->vla-object entity)
        source-handle (vla-get-Handle source-object)
        result
          (vl-catch-all-apply
            'CXNATIVEPLACEMENTAUDITV5
            (list source-handle segment-type segment dimension-handle offset
                  cx:*pg-seed-band-h* cx:*pg-minimum-usable-band-h*
                  cx:*pg-normal-band-h* cx:*pg-maximum-usable-band-h*)))
  (if (vl-catch-all-error-p result)
    (list 0
      (strcat "PLACEMENT_AUDIT_V5_CALL_FAILED:"
              (vl-catch-all-error-message result))
      0.0 0.0 1e99 0)
    result))

(princ)
