(vl-load-com)

;; Fast, read-only route-centerline inventory.  The layer predicate is applied
;; before any segment inspection.  LWPOLYLINE bulges are read from DXF data in
;; one pass; this intentionally avoids per-segment COM GetBulge calls.

(if (not (boundp 'cx:*route-fast-output*))
  (setq cx:*route-fast-output* "C:/tmp/route_centerlines_fast.tsv"))
(if (not (boundp 'cx:*route-fast-probe*))
  (setq cx:*route-fast-probe* "C:/tmp/route_centerlines_fast_probe.tsv"))

(defun cx:route-layer-p (layer / upper)
  (setq upper (strcase layer))
  (or
    (wcmatch upper "*中心线*")
    (wcmatch upper "*ROAD*CENTER*")
    (wcmatch upper "*ROAD*CL*")
    (wcmatch upper "*ROUTE*CENTER*")))

;; Override the legacy predicate with an ASCII-only rule.  A prior code-page
;; round trip corrupted its Chinese literal and could silently miss valid
;; layers.  These stable project prefixes cover the known 1.2 m stepping-stone,
;; 2.0 m/2.5 m route and 3.5 m main-route centerline families in the Yangqi
;; drawing.  Keep ASCII width tokens here because staged Chinese literals may
;; be corrupted by the host code page.
(defun cx:route-layer-p (layer / upper)
  (setq upper (strcase layer))
  (or
    (wcmatch upper "01-1.2M*")
    (wcmatch upper "01-2.5M*")
    (wcmatch upper "01-3.5M*")
    (wcmatch upper "01-2.0M*")
    (wcmatch upper "*ROAD*CENTER*")
    (wcmatch upper "*ROAD*CL*")
    (wcmatch upper "*ROUTE*CENTER*")))

(defun cx:dxf-real (code data / pair)
  (setq pair (assoc code data))
  (if pair (cdr pair) 0.0))

(defun cx:lwpoly-segment-count (data / vertices flags)
  (setq vertices (cdr (assoc 90 data))
        flags (if (assoc 70 data) (cdr (assoc 70 data)) 0))
  (if (= (logand flags 1) 1) vertices (max 0 (1- vertices))))

(defun cx:lwpoly-arc-indices (data segment-count / result vertex-index item)
  (setq result '() vertex-index -1)
  (foreach item data
    (cond
      ((= (car item) 10) (setq vertex-index (1+ vertex-index)))
      ((and (= (car item) 42)
            (>= vertex-index 0)
            (< vertex-index segment-count)
            (> (abs (cdr item)) 1e-10))
        (setq result (cons vertex-index result)))))
  (reverse result))

(defun cx:curve-segment-usable-p (entity index / p0 pm p1)
  (setq p0 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity index))
        pm (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (+ index 0.5)))
        p1 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (1+ index))))
  (and (not (vl-catch-all-error-p p0)) p0
       (not (vl-catch-all-error-p pm)) pm
       (not (vl-catch-all-error-p p1)) p1))

(defun cx:curve-straight-indices (entity segment-count arc-indices / index p0 p1 result)
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

(defun cx:oldpoly-data (entity / next data index arcs count done)
  (setq next (entnext entity) index 0 arcs '() count 0 done nil)
  (while (and next (not done))
    (setq data (entget next))
    (cond
      ((= (cdr (assoc 0 data)) "VERTEX")
        (if (> (abs (cx:dxf-real 42 data)) 1e-10)
          (setq arcs (cons index arcs)))
        (setq index (1+ index) count (1+ count)))
      ((= (cdr (assoc 0 data)) "SEQEND") (setq done T)))
    (if (not done) (setq next (entnext next))))
  (list count (reverse arcs)))

(defun cx:join-ints (values / output value)
  (setq output "")
  (foreach value values
    (setq output (strcat output (if (= output "") "" ",") (itoa value))))
  output)

(defun cx:bbox-text (object / minimum maximum attempt)
  (setq attempt
    (vl-catch-all-apply 'vla-GetBoundingBox (list object 'minimum 'maximum)))
  (if (vl-catch-all-error-p attempt)
    (list "" "")
    (list
      (strcat (rtos (vlax-safearray-get-element minimum 0) 2 3) ","
              (rtos (vlax-safearray-get-element minimum 1) 2 3))
      (strcat (rtos (vlax-safearray-get-element maximum 0) 2 3) ","
              (rtos (vlax-safearray-get-element maximum 1) 2 3)))))

(defun c:CXROUTEFASTINVENTORY
  (/ started dbmod selection file probe index entity data entity-type layer
     object segment-count raw-arc-indices arc-indices straight-indices old-data end-param length-value bbox
     scanned layer-matched accepted)
  (setq started (getvar "MILLISECS")
        dbmod (getvar "DBMOD")
        scanned 0 layer-matched 0 accepted 0)
  (setq file (open cx:*route-fast-output* "w"))
  (write-line
    "HANDLE\tENTITY_TYPE\tLAYER\tSEGMENT_COUNT\tARC_COUNT\tARC_SEGMENTS\tSTRAIGHT_COUNT\tSTRAIGHT_SEGMENTS\tLENGTH\tBBOX_MIN\tBBOX_MAX"
    file)
  (setq selection (ssget "_X" '((0 . "LWPOLYLINE,POLYLINE") (410 . "Model"))))
  (if selection
    (progn
      (setq index 0)
      (repeat (sslength selection)
        (setq entity (ssname selection index)
              data (entget entity)
              entity-type (cdr (assoc 0 data))
              layer (cdr (assoc 8 data))
              scanned (1+ scanned))
        (if (and layer (cx:route-layer-p layer))
          (progn
            (setq layer-matched (1+ layer-matched))
            (cond
              ((= entity-type "LWPOLYLINE")
                (setq segment-count (cx:lwpoly-segment-count data)
                      raw-arc-indices (cx:lwpoly-arc-indices data segment-count)
                      arc-indices raw-arc-indices
                      arc-indices
                        (vl-remove-if-not
                          '(lambda (arc-index) (cx:curve-segment-usable-p entity arc-index))
                          arc-indices)
                      straight-indices
                        (cx:curve-straight-indices entity segment-count raw-arc-indices)))
              ((= entity-type "POLYLINE")
                (setq old-data (cx:oldpoly-data entity)
                      segment-count (car old-data)
                      arc-indices (cadr old-data)
                      straight-indices '()))
              (t (setq segment-count 0 arc-indices '() straight-indices '())))
            (if (> (length arc-indices) 0)
              (progn
                (setq object (vlax-ename->vla-object entity)
                      end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list entity)))
                (if (vl-catch-all-error-p end-param)
                  (setq length-value nil)
                  (setq length-value
                    (vl-catch-all-apply 'vlax-curve-getDistAtParam (list entity end-param))))
                (if (vl-catch-all-error-p length-value) (setq length-value nil))
                (setq bbox (cx:bbox-text object))
                (write-line
                  (strcat
                    (cdr (assoc 5 data)) "\t" entity-type "\t" layer "\t"
                    (itoa segment-count) "\t" (itoa (length arc-indices)) "\t"
                    (cx:join-ints arc-indices) "\t"
                    (itoa (length straight-indices)) "\t"
                    (cx:join-ints straight-indices) "\t"
                    (if length-value (rtos length-value 2 6) "") "\t"
                    (car bbox) "\t" (cadr bbox))
                  file)
                (setq accepted (1+ accepted))))))
        (setq index (1+ index)))))
  (close file)
  (setq probe (open cx:*route-fast-probe* "w"))
  (write-line
    "STATUS\tDETAIL\tSCANNED\tLAYER_MATCHED\tARC_CANDIDATES\tELAPSED_MS\tDBMOD_BEFORE\tDBMOD_AFTER\tCTAB\tTILEMODE\tCVPORT\tCMDACTIVE\tCMDNAMES"
    probe)
  (write-line
    (strcat
      "PASS\tLAYER_PREFILTER_THEN_DXF_BULGE\t"
      (itoa scanned) "\t" (itoa layer-matched) "\t" (itoa accepted) "\t"
      (itoa (- (getvar "MILLISECS") started)) "\t"
      (itoa dbmod) "\t" (itoa (getvar "DBMOD"))
      "\t" (getvar "CTAB")
      "\t" (itoa (getvar "TILEMODE"))
      "\t" (itoa (getvar "CVPORT"))
      "\t" (itoa (getvar "CMDACTIVE"))
      "\t" (getvar "CMDNAMES"))
    probe)
  (close probe)
  (princ))

(princ)
