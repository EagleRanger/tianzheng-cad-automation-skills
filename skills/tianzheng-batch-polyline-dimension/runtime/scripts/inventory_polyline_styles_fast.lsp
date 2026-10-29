(vl-load-com)

;; Read-only model-space polyline style and segment inventory.

(if (not (boundp 'cx:*poly-style-output*))
  (setq cx:*poly-style-output* "C:/tmp/cx_polyline_styles.tsv"))
(if (not (boundp 'cx:*poly-style-summary*))
  (setq cx:*poly-style-summary* "C:/tmp/cx_polyline_styles_summary.tsv"))

(defun cx:poly-clean (value)
  (if (null value) (setq value ""))
  (vl-string-translate (strcat (chr 9) (chr 10) (chr 13)) "   " value))

(defun cx:poly-safe (object property / result)
  (setq result (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (vl-catch-all-error-p result) "" (vl-princ-to-string result)))

(defun cx:poly-rgb (object / color result red green blue)
  (setq result (vl-catch-all-apply 'vlax-get-property (list object 'TrueColor)))
  (if (vl-catch-all-error-p result)
    ""
    (progn
      (setq color result
            red (vl-catch-all-apply 'vlax-get-property (list color 'Red))
            green (vl-catch-all-apply 'vlax-get-property (list color 'Green))
            blue (vl-catch-all-apply 'vlax-get-property (list color 'Blue)))
      (if (or (vl-catch-all-error-p red)
              (vl-catch-all-error-p green)
              (vl-catch-all-error-p blue))
        ""
        (strcat (itoa red) "," (itoa green) "," (itoa blue))))))

(defun cx:poly-dxf-real (code data / pair)
  (setq pair (assoc code data))
  (if pair (cdr pair) 0.0))

(defun cx:poly-segment-count (data / vertices flags)
  (setq vertices (cdr (assoc 90 data))
        flags (if (assoc 70 data) (cdr (assoc 70 data)) 0))
  (if (= (logand flags 1) 1) vertices (max 0 (1- vertices))))

(defun cx:poly-arc-indices (data segment-count / result vertex-index item)
  (setq result '() vertex-index -1)
  (foreach item data
    (cond
      ((= (car item) 10) (setq vertex-index (1+ vertex-index)))
      ((and (= (car item) 42) (>= vertex-index 0) (< vertex-index segment-count)
            (> (abs (cdr item)) 1e-10))
        (setq result (cons vertex-index result)))))
  (reverse result))

(defun cx:poly-segment-usable-p (entity index / p0 pm p1)
  (setq p0 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity index))
        pm (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (+ index 0.5)))
        p1 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (1+ index))))
  (and (not (vl-catch-all-error-p p0)) p0
       (not (vl-catch-all-error-p pm)) pm
       (not (vl-catch-all-error-p p1)) p1))

(defun cx:poly-straight-indices (entity segment-count arc-indices / index p0 p1 result)
  (setq index 0 result '())
  (repeat segment-count
    (if (not (member index arc-indices))
      (progn
        (setq p0 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity index))
              p1 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (1+ index))))
        (if (and (not (vl-catch-all-error-p p0)) p0
                 (not (vl-catch-all-error-p p1)) p1
                 (> (distance p0 p1) 1e-8))
          (setq result (cons index result)))))
    (setq index (1+ index)))
  (reverse result))

(defun cx:poly-join-ints (values / output value)
  (setq output "")
  (foreach value values
    (setq output (strcat output (if (= output "") "" ",") (itoa value))))
  output)

(defun cx:poly-bbox (object / result minimum maximum)
  (setq result (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
  (if (vl-catch-all-error-p result)
    (list "" "")
    (list
      (strcat (rtos (vlax-safearray-get-element minimum 0) 2 3) ","
              (rtos (vlax-safearray-get-element minimum 1) 2 3))
      (strcat (rtos (vlax-safearray-get-element maximum 0) 2 3) ","
              (rtos (vlax-safearray-get-element maximum 1) 2 3)))))

(defun c:CXPOLYSTYLEINVENTORY
  (/ started dbmod doc layers selection output summary index entity data object layer-name
     layer-object entity-color layer-color entity-rgb layer-rgb segment-count raw-arc-indices arc-indices straight-indices
     bbox length-value end-param scanned arc-polylines total-arcs)
  (setq started (getvar "MILLISECS")
        dbmod (getvar "DBMOD")
        doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layers (vla-get-Layers doc)
        scanned 0 arc-polylines 0 total-arcs 0)
  (setq output (open cx:*poly-style-output* "w"))
  (write-line
    "HANDLE\tLAYER\tENTITY_COLOR\tLAYER_COLOR\tENTITY_RGB\tLAYER_RGB\tLINETYPE\tLINEWEIGHT\tCONSTANT_WIDTH\tSEGMENT_COUNT\tARC_COUNT\tARC_SEGMENTS\tSTRAIGHT_COUNT\tSTRAIGHT_SEGMENTS\tLENGTH\tBBOX_MIN\tBBOX_MAX"
    output)
  (setq selection (ssget "_X" '((0 . "LWPOLYLINE") (410 . "Model"))))
  (if selection
    (progn
      (setq index 0)
      (repeat (sslength selection)
        (setq entity (ssname selection index)
              data (entget entity)
              object (vlax-ename->vla-object entity)
              layer-name (cdr (assoc 8 data))
              layer-object (vla-Item layers layer-name)
              entity-color (vla-get-Color object)
              layer-color (vla-get-Color layer-object)
              entity-rgb (cx:poly-rgb object)
              layer-rgb (cx:poly-rgb layer-object)
              segment-count (cx:poly-segment-count data)
              raw-arc-indices (cx:poly-arc-indices data segment-count)
              arc-indices raw-arc-indices
              arc-indices
                (vl-remove-if-not
                  '(lambda (arc-index) (cx:poly-segment-usable-p entity arc-index))
                  arc-indices)
              straight-indices (cx:poly-straight-indices entity segment-count raw-arc-indices)
              bbox (cx:poly-bbox object)
              end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list entity)))
        (if (vl-catch-all-error-p end-param)
          (setq length-value nil)
          (setq length-value
            (vl-catch-all-apply 'vlax-curve-getDistAtParam (list entity end-param))))
        (if (vl-catch-all-error-p length-value) (setq length-value nil))
        (if (> (length arc-indices) 0)
          (setq arc-polylines (1+ arc-polylines)
                total-arcs (+ total-arcs (length arc-indices))))
        (write-line
          (strcat
            (cdr (assoc 5 data)) "\t" (cx:poly-clean layer-name) "\t"
            (itoa entity-color) "\t" (itoa layer-color) "\t"
            entity-rgb "\t" layer-rgb "\t"
            (cx:poly-clean (vla-get-Linetype object)) "\t"
            (cx:poly-safe object 'Lineweight) "\t"
            (rtos (cx:poly-dxf-real 43 data) 2 6) "\t"
            (itoa segment-count) "\t" (itoa (length arc-indices)) "\t"
            (cx:poly-join-ints arc-indices) "\t"
            (itoa (length straight-indices)) "\t"
            (cx:poly-join-ints straight-indices) "\t"
            (if length-value (rtos length-value 2 6) "") "\t"
            (car bbox) "\t" (cadr bbox))
          output)
        (setq scanned (1+ scanned) index (1+ index)))))
  (close output)
  (setq summary (open cx:*poly-style-summary* "w"))
  (write-line "STATUS\tDETAIL\tSCANNED\tARC_POLYLINES\tTOTAL_ARCS\tELAPSED_MS\tDBMOD_BEFORE\tDBMOD_AFTER\tCMDACTIVE\tCMDNAMES" summary)
  (write-line
    (strcat "PASS\tREAD_ONLY_STYLE_AND_BULGE_INVENTORY\t"
      (itoa scanned) "\t" (itoa arc-polylines) "\t" (itoa total-arcs) "\t"
      (itoa (- (getvar "MILLISECS") started)) "\t"
      (itoa dbmod) "\t" (itoa (getvar "DBMOD")) "\t"
      (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))
    summary)
  (close summary)
  (princ))

(c:CXPOLYSTYLEINVENTORY)
