(vl-load-com)

;; User-positive target-plane correction V2.
;; The measured E6 native text anchor lies on WCS Z=0.  The source polyline
;; segment lies on Z=-0.6.  V1 normalized the full 3D center-to-midpoint vector,
;; which contaminated both the XY unit vector and the final cursor Z.  Keep the
;; verified radial magnitude, but derive direction in XY only and issue the
;; final-position cursor on the native annotation plane Z=0.

(defun cx:upx2-unit-from-center-xy (center point / dx dy magnitude)
  (setq dx (- (car point) (car center))
        dy (- (cadr point) (cadr center))
        magnitude (sqrt (+ (* dx dx) (* dy dy))))
  (if (> magnitude 1e-9)
    (list (/ dx magnitude) (/ dy magnitude) 0.0)
    nil))

(defun cx:ups-target-text-point-wcs
  (geometry text-height / pm center radius unit target-radius)
  (if (or (not (listp geometry)) (/= (car geometry) "PASS"))
    nil
    (progn
      (setq pm (nth 3 geometry)
            center (nth 5 geometry)
            radius (nth 6 geometry)
            unit (cx:upx2-unit-from-center-xy center pm)
            target-radius
              (+ radius
                 (* text-height
                   (+ cx:*ups-dimension-band-h*
                      cx:*ups-text-anchor-extra-h*))))
      (if unit
        (list
          (+ (car center) (* (car unit) target-radius))
          (+ (cadr center) (* (cadr unit) target-radius))
          0.0)
        nil))))

(princ)
