(vl-load-com)

;; CX弧度批标 - interactive command layer for the frozen native TDIMARC engine.
;;
;; Interaction contract:
;;   CXHDBZ -> select one or more LWPOLYLINE objects -> Enter -> native angles.
;;
;; This file deliberately does not reproduce TDIMARC.  It only derives a
;; selection, a scale-aware default offset and a preferred side, then invokes
;; the frozen TZ-TDIMARC-FULL-BATCH-V2 engine once.  The engine continues to
;; create one independent Tianzheng TDbDimension2 per source arc and owns all
;; rollback/object validation behaviour.

(setq cx:*interactive-command-version* "CX-TDIM-TYPED-SELECT-AUTO-LAYOUT-V1")
(setq cx:*interactive-paper-text-height-mm* 3.5)
(setq cx:*interactive-fallback-model-text-height* 2.1)

(defun cx:ui-safe-get (object property / value)
  (setq value (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (vl-catch-all-error-p value) nil value))

(defun cx:ui-round-key (value)
  (rtos value 2 3))

(defun cx:ui-increment-count (key rows / hit output row)
  (setq hit nil output '())
  (foreach row rows
    (if (= (car row) key)
      (progn
        (setq output (cons (list key (1+ (cadr row)) (caddr row)) output))
        (setq hit T))
      (setq output (cons row output))))
  (if (not hit) (setq output (cons (list key 1 (atof key)) output)))
  (reverse output))

(defun cx:ui-dominant-viewport-scale (/ doc layouts layout block count index item name scale rows best row)
  ;; Layout viewport CustomScale works for both metre-based and millimetre-
  ;; based drawings: model text height = paper text height / CustomScale.
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layouts (vla-get-Layouts doc) rows '())
  (vlax-for layout layouts
    (if (/= (strcase (vla-get-Name layout)) "MODEL")
      (progn
        (setq block (vla-get-Block layout) count (vla-get-Count block) index 0)
        (repeat count
          (setq item (vl-catch-all-apply 'vla-Item (list block index)))
          (if (and (not (vl-catch-all-error-p item)) item)
            (progn
              (setq name (cx:ui-safe-get item 'ObjectName))
              (if (= name "AcDbViewport")
                (progn
                  (setq scale (cx:ui-safe-get item 'CustomScale))
                  (if (and (numberp scale) (> scale 0.0000001) (< scale 10000.0))
                    (setq rows (cx:ui-increment-count (cx:ui-round-key scale) rows)))))))
          (setq index (1+ index))))))
  (setq best nil)
  (foreach row rows
    (if (or (null best) (> (cadr row) (cadr best))) (setq best row)))
  (if best (caddr best) nil))

(defun cx:ui-model-text-height (/ viewport-scale dimtxt height)
  (setq viewport-scale (cx:ui-dominant-viewport-scale)
        dimtxt (getvar "DIMTXT"))
  (if (and (numberp viewport-scale) (> viewport-scale 0.0000001)
           (numberp dimtxt) (> dimtxt 0.0))
    (setq height (/ dimtxt viewport-scale))
    (setq height cx:*interactive-fallback-model-text-height*))
  ;; Reject obviously unusable inferred values rather than generating a remote
  ;; dimension band.  This does not shrink text; it falls back to the measured
  ;; 1:600 project prior until a dedicated scale profile is configured.
  (if (or (not (numberp height)) (<= height 0.0))
    (setq height cx:*interactive-fallback-model-text-height*))
  height)

(defun cx:ui-string-contains (text needle)
  (and text needle (not (null (vl-string-search (strcase needle) (strcase text))))))

(defun cx:ui-offset-factor (layer-name)
  ;; Measured priors from USER_REFERENCE_ANNOTATION_CONTRACT_20260810.
  (cond
    ((and (cx:ui-string-contains layer-name "中线")
          (cx:ui-string-contains layer-name "2.5")) 2.53)
    ((cx:ui-string-contains layer-name "中线") 2.76)
    (T 1.22)))

(defun cx:ui-polyline-arc-indices (entity / data result vertex-index item end-param segment-count)
  (setq data (entget entity) result '() vertex-index -1)
  (setq end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list entity))
        segment-count (if (vl-catch-all-error-p end-param) 0 (fix end-param)))
  (foreach item data
    (cond
      ((= (car item) 10) (setq vertex-index (1+ vertex-index)))
      ((and (= (car item) 42) (>= vertex-index 0) (< vertex-index segment-count)
            (> (abs (cdr item)) 1e-10))
        (setq result (cons vertex-index result)))))
  (reverse result))

(defun cx:ui-polyline-segment-items (entity mode / end-param count index arcs p0 p1 result)
  (setq end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list entity))
        count (if (vl-catch-all-error-p end-param) 0 (fix end-param))
        arcs (cx:ui-polyline-arc-indices entity)
        index 0 result '())
  (repeat count
    (cond
      ((member index arcs)
        (setq result
          (append result
            (list (if (= mode "ARC_ONLY") index (list "ARC" index))))))
      ((= mode "TYPED")
        (setq p0 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity index))
              p1 (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (1+ index))))
        (if (and (not (vl-catch-all-error-p p0)) p0
                 (not (vl-catch-all-error-p p1)) p1
                 (> (distance p0 p1) 1e-8))
          (setq result (append result (list (list "LINE" index)))))))
    (setq index (1+ index)))
  result)

(defun cx:ui-polyline-area-sign (entity / coords values points result index p0 p1)
  ;; Chord shoelace sign is sufficient for choosing the exterior side of a
  ;; closed bulged polyline; the bulges do not reverse path orientation.
  (setq coords (cx:ui-safe-get (vlax-ename->vla-object entity) 'Coordinates)
        result 0.0 points '())
  (if coords
    (progn
      (setq values (vlax-safearray->list (vlax-variant-value coords)))
      (while values
        (setq points (append points (list (list (car values) (cadr values)))))
        (setq values (cddr values)))
      (setq index 0)
      (repeat (length points)
        (setq p0 (nth index points)
              p1 (nth (rem (1+ index) (length points)) points)
              result (+ result (- (* (car p0) (cadr p1)) (* (car p1) (cadr p0)))))
        (setq index (1+ index)))))
  result)

(defun cx:ui-selection-centroid (entities / sx sy count entity object pmin pmax min-list max-list)
  (setq sx 0.0 sy 0.0 count 0)
  (foreach entity entities
    (setq object (vlax-ename->vla-object entity))
    (if (not (vl-catch-all-error-p
               (vl-catch-all-apply 'vla-GetBoundingBox (list object 'pmin 'pmax))))
      (progn
        (setq min-list (vlax-safearray->list pmin)
              max-list (vlax-safearray->list pmax)
              sx (+ sx (/ (+ (car min-list) (car max-list)) 2.0))
              sy (+ sy (/ (+ (cadr min-list) (cadr max-list)) 2.0))
              count (1+ count)))))
  (if (> count 0) (list (/ sx count) (/ sy count) 0.0) '(0.0 0.0 0.0)))

(defun cx:ui-open-side-sign (entity selection-centroid / end-param param point deriv magnitude normal away dot)
  (setq end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list entity)))
  (if (or (vl-catch-all-error-p end-param) (<= end-param 0.0))
    1.0
    (progn
      (setq param (/ end-param 2.0)
            point (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity param))
            deriv (vl-catch-all-apply 'vlax-curve-getFirstDeriv (list entity param)))
      (if (or (vl-catch-all-error-p point) (vl-catch-all-error-p deriv)
              (null point) (null deriv)
              (<= (setq magnitude (distance '(0.0 0.0 0.0) deriv)) 1e-9))
        1.0
        (progn
          (setq normal (list (/ (- (cadr deriv)) magnitude) (/ (car deriv) magnitude) 0.0)
                away (mapcar '- point selection-centroid)
                dot (+ (* (car normal) (car away)) (* (cadr normal) (cadr away))))
          (if (>= dot 0.0) 1.0 -1.0))))))

(defun cx:ui-side-sign (entity selection-centroid / object closed area)
  (setq object (vlax-ename->vla-object entity)
        closed (cx:ui-safe-get object 'Closed))
  (if (= closed :vlax-true)
    (progn
      (setq area (cx:ui-polyline-area-sign entity))
      ;; CCW path: left normal points inward, so use negative; CW is opposite.
      (if (>= area 0.0) -1.0 1.0))
    (cx:ui-open-side-sign entity selection-centroid)))

(defun cx:ui-selected-entities (selection / index entity object result)
  (setq index 0 result '())
  (repeat (sslength selection)
    (setq entity (ssname selection index)
          object (vlax-ename->vla-object entity))
    (if (= (vla-get-ObjectName object) "AcDbPolyline")
      (setq result (append result (list entity))))
    (setq index (1+ index)))
  result)

(defun cx:ui-engine-path ()
  (or
    (if (and (boundp 'cx:*interactive-engine-path*)
             cx:*interactive-engine-path*
             (findfile cx:*interactive-engine-path*))
      cx:*interactive-engine-path*)
    (findfile "tdimarc_native_full_batch.lsp")
    (if (getenv "CAD_RUNTIME_ROOT")
      (findfile (strcat (getenv "CAD_RUNTIME_ROOT") "/scripts/tdimarc_native_full_batch.lsp")))))

(defun cx:ui-build-task (entity centroid text-height mode / object layer factor sign segments group)
  (setq object (vlax-ename->vla-object entity)
        layer (vla-get-Layer object)
        factor (cx:ui-offset-factor layer)
        sign (cx:ui-side-sign entity centroid)
        segments (cx:ui-polyline-segment-items entity mode)
        group (if (cx:ui-string-contains layer "中线") "ROAD" "SHORE"))
  (if segments
    (list (vla-get-Handle object) segments (* sign factor text-height) group)
    nil))

(defun cx:ui-run (mode / old-error selection entities centroid text-height tasks task engine drawing temp-root label report-stem)
  (setq label (if (= mode "TYPED") "CX多段线批标" "CX弧度批标")
        report-stem (if (= mode "TYPED") "cx_tdim_typed_interactive" "cx_tdimarc_interactive"))
  (setq old-error *error*)
  (setq *error*
    (lambda (message)
      (setq *error* old-error)
      (if (and message (/= message "Function cancelled"))
        (princ (strcat "\n" label "中止: " message)))
      (princ)))
  (cond
    ((/= (getvar "CMDNAMES") "")
      (princ (strcat "\n" label "未启动：当前仍有命令在运行。")))
    ((null (setq engine (cx:ui-engine-path)))
      (princ (strcat "\n" label "未启动：未找到已验证的原生标注引擎。")))
    ((null (setq selection
             (or
               ;; A governed caller may prepare an implied selection.  This
               ;; preserves the user command while avoiding mouse simulation.
               (ssget "_I" '((0 . "LWPOLYLINE") (410 . "Model")))
               (ssget '((0 . "LWPOLYLINE") (410 . "Model"))))))
      (princ "\n未选择多段线。"))
    (T
      (setq entities (cx:ui-selected-entities selection)
            centroid (cx:ui-selection-centroid entities)
            text-height (cx:ui-model-text-height)
            tasks '())
      (foreach entity entities
        (setq task (cx:ui-build-task entity centroid text-height mode))
        (if task (setq tasks (append tasks (list task)))))
      (if (null tasks)
        (princ "\n所选多段线没有可标注的圆弧段。")
        (progn
          (setq drawing (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))
                temp-root (vl-string-right-trim "\\/" (getvar "TEMPPREFIX"))
                cx:*full-batch-tasks* tasks
                cx:*full-batch-cleanup-handles* '()
                cx:*full-batch-clean-slate-object-names* '()
                cx:*full-batch-expected-drawing* drawing
                cx:*full-batch-summary-path*
                  (if (and (boundp 'cx:*interactive-summary-path*)
                           cx:*interactive-summary-path*)
                    cx:*interactive-summary-path*
                    (strcat temp-root "/" report-stem "_summary.tsv"))
                cx:*full-batch-details-path*
                  (if (and (boundp 'cx:*interactive-details-path*)
                           cx:*interactive-details-path*)
                    cx:*interactive-details-path*
                    (strcat temp-root "/" report-stem "_details.tsv"))
                cx:*full-batch-save-on-success* nil)
          (princ
            (strcat "\n" label "：已选 " (itoa (length tasks)) " 条多段线，"
                    "模型字高=" (rtos text-height 2 3) "，开始原生批标……"))
          ;; One load, one in-process invocation.  Never use delayed character
          ;; PostText/MDI delivery here: it previously caused a duplicate batch.
          (load engine)
          (princ
            (strcat "\n" label "执行结束。报告：" cx:*full-batch-summary-path*))))))
  (setq *error* old-error)
  (princ))

(defun c:CXPLBZ () (cx:ui-run "TYPED"))
(defun c:CXHDBZ () (cx:ui-run "ARC_ONLY"))
(defun c:CXTDIMARC () (cx:ui-run "ARC_ONLY"))

(princ "\nCX多段线标注已加载。CXPLBZ=弧度+直线；CXHDBZ=仅弧度。")
(princ)
