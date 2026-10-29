(vl-load-com)

;; Fast, fail-closed TDIMARC batch engine for an owned Tianzheng drawing.
;; Task shape: ("HANDLE" (("ARC" segment-index) ...) offset "GROUP")
;; This engine only proves native creation and prompt completion.  Displayed
;; semantics and source-segment association MUST be checked by the strict
;; post-run audit before a batch may be accepted or saved.

(if (not (boundp 'cx:*full-batch-tasks*)) (setq cx:*full-batch-tasks* '()))
(if (not (boundp 'cx:*full-batch-cleanup-handles*))
  (setq cx:*full-batch-cleanup-handles* '()))
(if (not (boundp 'cx:*full-batch-clean-slate-object-names*))
  (setq cx:*full-batch-clean-slate-object-names* '()))
(if (not (boundp 'cx:*full-batch-expected-drawing*))
  (setq cx:*full-batch-expected-drawing* ""))
(if (not (boundp 'cx:*full-batch-summary-path*))
  (setq cx:*full-batch-summary-path* "C:/tmp/cx_tdimarc_full_summary.tsv"))
(if (not (boundp 'cx:*full-batch-details-path*))
  (setq cx:*full-batch-details-path* "C:/tmp/cx_tdimarc_full_details.tsv"))
(if (not (boundp 'cx:*full-batch-save-on-success*))
  (setq cx:*full-batch-save-on-success* nil))

(defun cx:fb-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:fb-safe-property (object property / result)
  (setq result (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (vl-catch-all-error-p result) "" (vl-princ-to-string result)))

(defun cx:fb-join (items / output item)
  (setq output "")
  (foreach item items
    (setq output
      (strcat output (if (= output "") "" ",") (vl-princ-to-string item))))
  output)

(defun cx:fb-sum-targets (tasks / total task)
  (setq total 0)
  (foreach task tasks (setq total (+ total (length (cadr task)))))
  total)

(defun cx:fb-write-lines (path lines / temporary file line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq file (open temporary "w"))
  (foreach line lines (write-line line file))
  (close file)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:fb-runtime-error (message / line)
  (setq line
    (strcat "FAIL\t" (if (boundp 'cx:*fb-phase*) cx:*fb-phase* "UNKNOWN") "\t"
      (if (boundp 'cx:*fb-current-handle*) cx:*fb-current-handle* "") "\t"
      (if (and (boundp 'cx:*fb-current-segment*) cx:*fb-current-segment*)
        (itoa cx:*fb-current-segment*) "") "\t" message))
  (if (and (boundp 'cx:*fb-added*) cx:*fb-added*)
    (vl-catch-all-apply 'cx:fb-delete-handles (list cx:*fb-added*)))
  (if (and (boundp 'cx:*fb-visibility*) cx:*fb-visibility*)
    (vl-catch-all-apply 'cx:fb-restore-visibility (list cx:*fb-visibility*)))
  (if (and (boundp 'cx:*fb-object-isolated*) cx:*fb-object-isolated*)
    (vl-catch-all-apply 'command-s (list "_.UNISOLATEOBJECTS")))
  (if (and (boundp 'cx:*fb-layer-snapshot*) cx:*fb-layer-snapshot*)
    (vl-catch-all-apply 'cx:fb-restore-layers (list cx:*fb-layer-snapshot*)))
  (cx:fb-write-lines "C:/tmp/cx_tdimarc_full_runtime_error.tsv"
    (list "STATUS\tPHASE\tSOURCE_HANDLE\tSEGMENT\tMESSAGE" line))
  (if (boundp 'cx:*fb-old-error*) (setq *error* cx:*fb-old-error*))
  (princ))

(defun cx:fb-isolate-object (entity / result)
  ;; AutoCAD object isolation avoids Tianzheng layer-collection bugs and makes
  ;; point selection deterministic when road/shore geometry overlaps.
  (setq result (vl-catch-all-apply 'command-s (list "_.ISOLATEOBJECTS" entity "")))
  (and (not (vl-catch-all-error-p result))
       (= (getvar "CMDNAMES") "")
       (or (= (getvar "CMDACTIVE") 0) (= (getvar "CMDACTIVE") 4))))

(defun cx:fb-isolate-entities (entities / result)
  ;; Cross-source validation wrapper only.  Tianzheng keeps a pick cache across
  ;; UNISOLATEOBJECTS/ISOLATEOBJECTS transitions, so switching the isolation
  ;; set between source polylines can make the next valid arc return no object.
  ;; Isolate all explicitly authorised sources once and keep the verified
  ;; per-arc TDIMARC sequence unchanged.
  (setq result
    (vl-catch-all-apply 'command-s
      (append (list "_.ISOLATEOBJECTS") entities (list ""))))
  (and (not (vl-catch-all-error-p result))
       (= (getvar "CMDNAMES") "")
       (or (= (getvar "CMDACTIVE") 0) (= (getvar "CMDACTIVE") 4))))

(defun cx:fb-unisolate-objects (/ result)
  (setq result (vl-catch-all-apply 'command-s (list "_.UNISOLATEOBJECTS")))
  (and (not (vl-catch-all-error-p result)) (= (getvar "CMDNAMES") "")))

(defun cx:fb-native-handles (/ doc space count index item object-name result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        count (vla-get-Count space)
        index 0 result '())
  (repeat count
    (setq item (vl-catch-all-apply 'vla-Item (list space index)))
    (if (not (vl-catch-all-error-p item))
      (progn
        (setq object-name (vl-catch-all-apply 'vla-get-ObjectName (list item)))
        (if (and (not (vl-catch-all-error-p object-name))
                 (= object-name "TDbDimension2"))
          (setq result (cons (vla-get-Handle item) result)))))
    (setq index (1+ index)))
  result)

(defun cx:fb-difference (after before / result item)
  (setq result '())
  (foreach item after
    (if (not (member item before)) (setq result (cons item result))))
  (reverse result))

(defun cx:fb-delete-handles (handles / handle entity)
  (foreach handle handles
    (setq entity (handent handle))
    (if entity (entdel entity))))

(defun cx:fb-delete-object-names (object-names / doc space count index item name victims deleted)
  ;; Controlled-test only.  Collect first, then delete, so ModelSpace index
  ;; changes cannot skip an object.  The caller records every deleted handle.
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        count (vla-get-Count space)
        index 0 victims '() deleted '())
  (repeat count
    (setq item (vl-catch-all-apply 'vla-Item (list space index)))
    (if (not (vl-catch-all-error-p item))
      (progn
        (setq name (vl-catch-all-apply 'vla-get-ObjectName (list item)))
        (if (and (not (vl-catch-all-error-p name)) (member name object-names))
          (setq victims (cons item victims)))))
    (setq index (1+ index)))
  (foreach item victims
    (setq name (vl-catch-all-apply 'vla-get-Handle (list item)))
    (if (not (vl-catch-all-error-p name))
      (progn
        (vl-catch-all-apply 'vla-Delete (list item))
        (if (null (handent name)) (setq deleted (cons name deleted))))))
  (reverse deleted))

(defun cx:fb-delete-validated-cleanup (handles / handle entity object valid deleted)
  (setq valid T deleted '())
  (foreach handle handles
    (if valid
      (progn
        (setq entity (handent handle))
        (if (and entity (entget entity))
          (progn
            (setq object (vl-catch-all-apply 'vlax-ename->vla-object (list entity)))
            (if (and (not (vl-catch-all-error-p object)) object
                     (= (vla-get-ObjectName object) "TDbDimension2")
                     (= (vla-get-Layer object) "PUB_DIM")
                     (member
                       (cx:fb-safe-property object 'DimStyle)
                       '("_TCH_ARROW" "_TCH_ARCH_M_M")))
              (progn (entdel entity) (setq deleted (cons handle deleted)))
              (setq valid nil)))))))
  (list valid (reverse deleted)))

(defun cx:fb-layer-state (/ doc layers count index layer layer-name layer-on layer-freeze
                            active-layer result active-name)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layers (vla-get-Layers doc)
        count (vla-get-Count layers)
        index 0 result '())
  (setq active-layer (vl-catch-all-apply 'vla-get-ActiveLayer (list doc)))
  (if (or (vl-catch-all-error-p active-layer) (null active-layer))
    (setq active-name "0")
    (setq active-name (vla-get-Name active-layer)))
  (repeat count
    (setq layer (vl-catch-all-apply 'vla-Item (list layers index)))
    (if (and (not (vl-catch-all-error-p layer)) layer)
      (progn
        (setq layer-name (vl-catch-all-apply 'vla-get-Name (list layer))
              layer-on (vl-catch-all-apply 'vla-get-LayerOn (list layer))
              layer-freeze (vl-catch-all-apply 'vla-get-Freeze (list layer)))
        (if (and (not (vl-catch-all-error-p layer-name))
                 (not (vl-catch-all-error-p layer-on))
                 (not (vl-catch-all-error-p layer-freeze)))
          (setq result (cons (list layer-name layer-on layer-freeze) result)))))
    (setq index (1+ index)))
  (list active-name result))

(defun cx:fb-set-layer-visible (name visible / doc layer)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layer (vla-Item (vla-get-Layers doc) name))
  (if visible
    (progn
      (vl-catch-all-apply 'vla-put-Freeze (list layer :vlax-false))
      (vl-catch-all-apply 'vla-put-LayerOn (list layer :vlax-true)))
    (vl-catch-all-apply 'vla-put-LayerOn (list layer :vlax-false))))

(defun cx:fb-isolate-layer (source-layer / doc layers count index layer name)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layers (vla-get-Layers doc)
        count (vla-get-Count layers) index 0)
  (cx:fb-set-layer-visible source-layer T)
  (vl-catch-all-apply 'vla-put-ActiveLayer (list doc (vla-Item layers source-layer)))
  (repeat count
    (setq layer (vl-catch-all-apply 'vla-Item (list layers index)))
    (if (and (not (vl-catch-all-error-p layer)) layer)
      (progn
        (setq name (vl-catch-all-apply 'vla-get-Name (list layer)))
        (if (and (not (vl-catch-all-error-p name))
                 (not (member (strcase name) (list (strcase source-layer) "PUB_DIM" "0"))))
          (vl-catch-all-apply 'vla-put-LayerOn (list layer :vlax-false)))))
    (setq index (1+ index)))
  (if (tblsearch "LAYER" "PUB_DIM") (cx:fb-set-layer-visible "PUB_DIM" T)))

(defun cx:fb-restore-layers (snapshot / doc layers row layer active-name)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layers (vla-get-Layers doc) active-name (car snapshot))
  (foreach row (cadr snapshot)
    (if (tblsearch "LAYER" (car row))
      (progn
        (setq layer (vla-Item layers (car row)))
        (vl-catch-all-apply 'vla-put-Freeze (list layer (caddr row)))
        (vl-catch-all-apply 'vla-put-LayerOn (list layer (cadr row))))))
  (if (tblsearch "LAYER" active-name)
    (vl-catch-all-apply 'vla-put-ActiveLayer (list doc (vla-Item layers active-name)))))

(defun cx:fb-hide-sibling-polylines (entity layer-name / set index item object visible snapshot)
  (setq snapshot '()
        set (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 layer-name) '(410 . "Model"))))
  (if set
    (progn
      (setq index 0)
      (repeat (sslength set)
        (setq item (ssname set index))
        (if (not (eq item entity))
          (progn
            (setq object (vlax-ename->vla-object item) visible (vla-get-Visible object))
            (setq snapshot (cons (list object visible) snapshot))
            (vl-catch-all-apply 'vla-put-Visible (list object :vlax-false))))
        (setq index (1+ index)))))
  snapshot)

(defun cx:fb-restore-visibility (snapshot / row)
  (foreach row snapshot
    (vl-catch-all-apply 'vla-put-Visible (list (car row) (cadr row)))))

(defun cx:fb-arc-indices (entity / data result vertex-index item end-param segment-count)
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

(defun cx:fb-straight-indices (entity arc-indices / end-param segment-count index p0 p1 result)
  (setq end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list entity))
        segment-count (if (vl-catch-all-error-p end-param) 0 (fix end-param))
        index 0 result '())
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

(defun cx:fb-segment-item-type (item)
  (if (numberp item) "ARC" (strcase (car item))))

(defun cx:fb-segment-item-index (item)
  (if (numberp item) item (cadr item)))

(defun cx:fb-segment-item-valid-p (item arc-indices straight-indices / type index)
  (setq type (cx:fb-segment-item-type item) index (cx:fb-segment-item-index item))
  (and (numberp index)
       (or (and (= type "ARC") (member index arc-indices))
           (and (= type "LINE") (member index straight-indices)))))

(defun cx:fb-zoom-object (object offset / minimum maximum min-list max-list margin)
  (vla-GetBoundingBox object 'minimum 'maximum)
  (setq min-list (vlax-safearray->list minimum)
        max-list (vlax-safearray->list maximum)
        margin (+ 5.0 (* 2.0 (abs offset))))
  (vl-catch-all-apply 'command-s
    (list "_.ZOOM" "_W"
      (trans (list (- (car min-list) margin) (- (cadr min-list) margin) 0.0) 0 1)
      (trans (list (+ (car max-list) margin) (+ (cadr max-list) margin) 0.0) 0 1))))

(defun cx:fb-segment-points
  (entity segment fraction offset / parameter pick-result deriv-result before-result after-result
     pick-wcs deriv before-wcs after-wcs magnitude normal side-wcs)
  (setq parameter (+ segment fraction)
        pick-result (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity parameter))
        deriv-result (vl-catch-all-apply 'vlax-curve-getFirstDeriv (list entity parameter)))
  (if (not (vl-catch-all-error-p pick-result)) (setq pick-wcs pick-result))
  (if (not (vl-catch-all-error-p deriv-result)) (setq deriv deriv-result))
  ;; Some real Tianzheng polylines return nil for FirstDeriv on the final arc.
  ;; Use a local chord only as the tangent-direction fallback; the selected
  ;; geometry point remains on the original arc and TDIMARC computes the value.
  (if (and pick-wcs (null deriv))
    (progn
      (setq before-result
        (vl-catch-all-apply 'vlax-curve-getPointAtParam
          (list entity (+ segment (max 0.05 (- fraction 0.05)))))
            after-result
        (vl-catch-all-apply 'vlax-curve-getPointAtParam
          (list entity (+ segment (min 0.95 (+ fraction 0.05))))))
      (if (and (not (vl-catch-all-error-p before-result))
               (not (vl-catch-all-error-p after-result))
               before-result after-result)
        (setq before-wcs before-result after-wcs after-result
              deriv (mapcar '- after-wcs before-wcs)))))
  (setq magnitude (if deriv (distance '(0.0 0.0 0.0) deriv) 0.0))
  (if (and pick-wcs (> magnitude 1e-9))
    (progn
      (setq normal (list (/ (- (cadr deriv)) magnitude) (/ (car deriv) magnitude) 0.0)
            side-wcs (mapcar '+ pick-wcs (mapcar '(lambda (value) (* value offset)) normal)))
      (list (trans pick-wcs 0 1) (trans side-wcs 0 1)))
    nil))

(defun cx:fb-call-diagnostic (fraction call-result added / message)
  (setq message
    (if (vl-catch-all-error-p call-result)
      (vl-catch-all-error-message call-result)
      "NO_LISP_ERROR"))
  (strcat "fraction=" (rtos fraction 2 2)
    ",added=" (cx:fb-join added)
    ",errno=" (itoa (getvar "ERRNO"))
    ",cmdactive=" (itoa (getvar "CMDACTIVE"))
    ",cmdnames=" (getvar "CMDNAMES")
    ",result=" message))

(defun cx:fb-created-object-info (added / handle entity object object-name layer dim-style)
  (setq handle "" object-name "" layer "" dim-style "")
  (if (= (length added) 1)
    (progn
      (setq handle (car added) entity (handent handle))
      (if entity
        (progn
          (setq object (vl-catch-all-apply 'vlax-ename->vla-object (list entity)))
          (if (and (not (vl-catch-all-error-p object)) object)
            (setq object-name (vla-get-ObjectName object)
                  layer (vla-get-Layer object)
                  dim-style (cx:fb-safe-property object 'DimStyle)))))))
  (list handle object-name layer dim-style))

(defun cx:fb-created-object-valid-p (added expected-style / info)
  (setq info (cx:fb-created-object-info added))
  (and (= (length added) 1)
       (= (cadr info) "TDbDimension2")
       (= (caddr info) "PUB_DIM")
       (= (cadddr info) expected-style)))

(defun cx:fb-run-one
  (entity segment offset expected-style
    / fractions fraction points pick side before after added call-result result attempts info diagnostic)
  (setq fractions '(0.35 0.65 0.20 0.80 0.50)
        result (list nil '() nil nil "") attempts '())
  (while (and fractions (= (length (cadr result)) 0))
    (setq fraction (car fractions) fractions (cdr fractions)
          points (cx:fb-segment-points entity segment fraction offset))
    (if points
      (progn
        (setq pick (car points) side (cadr points) before (cx:fb-native-handles)
              ;; T20 V10 human prompt sequence: select arc, confirm in place,
              ;; then place the dimension at the computed offset point.
              call-result (vl-catch-all-apply 'command-s (list "TDIMARC" pick pick side ""))
              after (cx:fb-native-handles) added (cx:fb-difference after before)
              info (cx:fb-created-object-info added)
              diagnostic (cx:fb-call-diagnostic fraction call-result added))
        (if (and (not (vl-catch-all-error-p call-result))
                 (cx:fb-created-object-valid-p added expected-style))
          (progn
            (setq attempts (append attempts (list (strcat diagnostic ",semantic=ACCEPTED")))
                  result (list call-result added pick side (cx:fb-join attempts))))
          (progn
            ;; A geometrically valid arc can occasionally be interpreted by
            ;; T20 as a straight/length dimension at one pick fraction.  Keep
            ;; the verified human prompt sequence unchanged: remove only the
            ;; object created by this failed attempt, then retry another point
            ;; on the same authorised arc.
            (if added (cx:fb-delete-handles added))
            (setq attempts
              (append attempts
                (list
                  (strcat diagnostic
                    ",semantic=DISCARDED"
                    ",object=" (cadr info)
                    ",layer=" (caddr info)
                    ",style=" (cadddr info)))))
            (setq result (list call-result '() pick side (cx:fb-join attempts))))))))
  result)

(defun cx:fb-line-points (entity segment offset / p0-result p1-result p0 p1 vector magnitude normal midpoint side-wcs)
  (setq p0-result (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity segment))
        p1-result (vl-catch-all-apply 'vlax-curve-getPointAtParam (list entity (1+ segment))))
  (if (and (not (vl-catch-all-error-p p0-result)) p0-result
           (not (vl-catch-all-error-p p1-result)) p1-result)
    (progn
      (setq p0 p0-result p1 p1-result vector (mapcar '- p1 p0)
            magnitude (distance '(0.0 0.0 0.0) vector))
      (if (> magnitude 1e-8)
        (progn
          (setq normal (list (/ (- (cadr vector)) magnitude) (/ (car vector) magnitude) 0.0)
                midpoint (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p0 p1)
                side-wcs (mapcar '+ midpoint (mapcar '(lambda (value) (* value offset)) normal)))
          (list (trans p0 0 1) (trans p1 0 1) (trans side-wcs 0 1)))
        nil))
    nil))

(defun cx:fb-run-line (entity segment offset / points p0 p1 side before after added call-result)
  (setq points (cx:fb-line-points entity segment offset))
  (if points
    (progn
      (setq p0 (car points) p1 (cadr points) side (caddr points)
            before (cx:fb-native-handles)
            call-result (vl-catch-all-apply 'command-s (list "TDimMP" p0 p1 side ""))
            after (cx:fb-native-handles) added (cx:fb-difference after before))
      (list call-result added p0 side))
    (list nil '() nil nil)))

(defun cx:fb-accept-one (result expected-style / call-result added handle entity object object-name layer dim-style)
  (setq call-result (car result) added (cadr result)
        handle "" object-name "" layer "" dim-style "")
  (if (= (length added) 1)
    (progn
      (setq handle (car added) entity (handent handle))
      (if entity
        (progn
          (setq object (vlax-ename->vla-object entity)
                object-name (vla-get-ObjectName object)
                layer (vla-get-Layer object)
                dim-style (cx:fb-safe-property object 'DimStyle))))))
  (list
    (and (not (vl-catch-all-error-p call-result)) (= (length added) 1)
         (= object-name "TDbDimension2") (= layer "PUB_DIM")
         (= dim-style expected-style) (= (getvar "CMDNAMES") "")
         (or (= (getvar "CMDACTIVE") 0) (= (getvar "CMDACTIVE") 4)))
    handle object-name layer dim-style))

(defun c:CXTDIMARCFULLBATCH
  (/ started doc drawing cleanup-result cleanup-deleted task source-handle
     segments offset group entity object arc-indices straight-indices segment-item segment-type segment-index expected-style
     one-result accepted all-added task-added dimension-handle dimension-entity dimension-object failed details status detail task-count segment-count
     road-count shore-count elapsed target-count summary clean-slate-deleted
     batch-isolated batch-entities candidate-entity isolation-ok)
  (setq started (getvar "MILLISECS") status "FAIL" detail "" all-added '() failed '()
        task-count 0 segment-count 0 road-count 0 shore-count 0 cleanup-deleted '() clean-slate-deleted '()
        target-count (cx:fb-sum-targets cx:*full-batch-tasks*)
        batch-isolated nil batch-entities '()
        details (list "GROUP\tSOURCE_HANDLE\tSEGMENT_TYPE\tSEGMENT_INDEX\tSTATUS\tADDED_HANDLE\tOBJECT_NAME\tLAYER\tDIM_STYLE\tPICK_X\tPICK_Y\tSIDE_X\tSIDE_Y\tCMDACTIVE\tCMDNAMES\tATTEMPTS"))
  (setq cx:*fb-old-error* *error* *error* cx:fb-runtime-error
        cx:*fb-phase* "START" cx:*fb-current-handle* "" cx:*fb-current-segment* nil
        cx:*fb-added* '() cx:*fb-visibility* '() cx:*fb-layer-snapshot* nil
        cx:*fb-object-isolated* nil)
  (setq drawing (cx:fb-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))))
  (cond
    ((= target-count 0) (setq detail "EMPTY_TASK_SET"))
    ((and (/= cx:*full-batch-expected-drawing* "")
          (/= drawing (cx:fb-normalize-path cx:*full-batch-expected-drawing*)))
      (setq detail "ACTIVE_DRAWING_MISMATCH"))
    ((/= (getvar "CMDNAMES") "") (setq detail "COMMAND_NOT_IDLE_AT_START"))
    (t
      (setq cx:*fb-phase* "ACTIVE_DOCUMENT")
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
      (setq cx:*fb-phase* "CLEANUP_HANDLES")
      (setq cleanup-result (cx:fb-delete-validated-cleanup cx:*full-batch-cleanup-handles*))
      (setq cx:*fb-phase* "AFTER_CLEANUP")
      (if (not (car cleanup-result))
        (setq detail "CLEANUP_HANDLE_CONTRACT_FAILED")
        (progn
          (setq cleanup-deleted (cadr cleanup-result))
          (if cx:*full-batch-clean-slate-object-names*
            (setq clean-slate-deleted
              (cx:fb-delete-object-names cx:*full-batch-clean-slate-object-names*)))
          (if (or cleanup-deleted clean-slate-deleted)
            (vl-catch-all-apply 'command-s (list "_.REGEN")))
          ;; A multi-source run keeps every authorised source visible in one
          ;; isolation context.  This mirrors the verified human strategy of
          ;; showing all target polylines before repeated point selection and
          ;; avoids Tianzheng's stale pick cache at an isolation transition.
          (if (> (length cx:*full-batch-tasks*) 1)
            (progn
              (foreach task cx:*full-batch-tasks*
                (setq candidate-entity (handent (car task)))
                (if candidate-entity
                  (setq batch-entities (append batch-entities (list candidate-entity)))
                  (setq failed (list (strcat (car task) ":SOURCE_NOT_FOUND")))))
              (if (null failed)
                (if (cx:fb-isolate-entities batch-entities)
                  (setq batch-isolated T cx:*fb-object-isolated* T)
                  (setq failed (list "MULTI_SOURCE_OBJECT_ISOLATION_FAILED"))))))
          (foreach task cx:*full-batch-tasks*
            (if (null failed)
              (progn
                (setq source-handle (car task) segments (cadr task) offset (caddr task)
                      group (cadddr task) entity (handent source-handle) task-added '())
                (setq cx:*fb-phase* "TASK_VALIDATE" cx:*fb-current-handle* source-handle)
                (cond
                  ((null entity) (setq failed (list (strcat source-handle ":SOURCE_NOT_FOUND"))))
                  ((/= (vla-get-ObjectName (setq object (vlax-ename->vla-object entity))) "AcDbPolyline")
                    (setq failed (list (strcat source-handle ":NOT_POLYLINE"))))
                  (t
                    (setq arc-indices (cx:fb-arc-indices entity)
                          straight-indices (cx:fb-straight-indices entity arc-indices))
                    (if (not
                          (vl-every
                            '(lambda (item)
                              (cx:fb-segment-item-valid-p item arc-indices straight-indices))
                            segments))
                      (setq failed (list (strcat source-handle ":INVALID_TYPED_SEGMENT_IN_TASK")))
                      (progn
                        ;; Keep the command path identical to the verified native probe.
                        ;; Layer/entity isolation is deliberately excluded here because
                        ;; it caused Tianzheng "invalid layer" automation failures.
                        (setq cx:*fb-phase* "ISOLATE_OBJECT"
                              isolation-ok
                                (if batch-isolated T (cx:fb-isolate-object entity)))
                        (if (not isolation-ok)
                          (setq failed (list (strcat source-handle ":OBJECT_ISOLATION_FAILED")))
                          (progn
                            (if (not batch-isolated) (setq cx:*fb-object-isolated* T))
                            (setq cx:*fb-phase* "ZOOM_OBJECT")
                            (cx:fb-zoom-object object offset)
                            (setq task-count (1+ task-count))
                            ;; VERIFIED_TDIMARC_INDEPENDENT_ARC_V1: preserve the
                            ;; 2026-08-06 real-DWG path.  Each arc gets one fresh
                            ;; native TDIMARC invocation and one independent
                            ;; TDbDimension2; do not concatenate prompt tokens.
                            (foreach segment-item segments
                              (if (null failed)
                                (progn
                                  (setq segment-type (cx:fb-segment-item-type segment-item)
                                        segment-index (cx:fb-segment-item-index segment-item)
                                        expected-style
                                          (if (= segment-type "ARC") "_TCH_ARROW" "_TCH_ARCH_M_M")
                                        cx:*fb-phase* (strcat "RUN_" segment-type)
                                        cx:*fb-current-segment* segment-index)
                                  (setq one-result
                                          (if (= segment-type "ARC")
                                            (cx:fb-run-one entity segment-index offset expected-style)
                                            (cx:fb-run-line entity segment-index offset))
                                        accepted (cx:fb-accept-one one-result expected-style))
                                  (if (car accepted)
                                    (progn
                                      (setq all-added (append all-added (cadr one-result))
                                            task-added (append task-added (cadr one-result))
                                            segment-count (1+ segment-count)
                                            cx:*fb-added* all-added)
                                      (setq dimension-entity (handent (cadr accepted)))
                                      (if (and dimension-entity (entget dimension-entity))
                                        (progn
                                          (setq dimension-object
                                            (vl-catch-all-apply 'vlax-ename->vla-object
                                              (list dimension-entity)))
                                          (if (and dimension-object
                                                   (not (vl-catch-all-error-p dimension-object)))
                                            (vl-catch-all-apply 'vla-put-Visible
                                              (list dimension-object :vlax-false)))))
                                      (if (= group "ROAD")
                                        (setq road-count (1+ road-count))
                                        (setq shore-count (1+ shore-count))))
                                    (setq failed
                                      (list
                                        (strcat source-handle ":" segment-type ":"
                                          (itoa segment-index)))))
                                  (setq details
                                    (append details
                                      (list
                                        (strcat group "\t" source-handle "\t" segment-type "\t"
                                          (itoa segment-index) "\t"
                                          (if (car accepted) "PASS" "FAIL") "\t"
                                          (cadr accepted) "\t" (caddr accepted) "\t"
                                          (cadddr accepted) "\t" (nth 4 accepted) "\t"
                                          (if (nth 2 one-result)
                                            (rtos (car (nth 2 one-result)) 2 6) "") "\t"
                                          (if (nth 2 one-result)
                                            (rtos (cadr (nth 2 one-result)) 2 6) "") "\t"
                                          (if (nth 3 one-result)
                                            (rtos (car (nth 3 one-result)) 2 6) "") "\t"
                                          (if (nth 3 one-result)
                                            (rtos (cadr (nth 3 one-result)) 2 6) "") "\t"
                                          (itoa (getvar "CMDACTIVE")) "\t"
                                          (getvar "CMDNAMES") "\t"
                                          (if (nth 4 one-result) (nth 4 one-result) ""))))))))
                            (if (not batch-isolated)
                              (progn
                                (setq cx:*fb-phase* "UNISOLATE_OBJECT")
                                (if (not (cx:fb-unisolate-objects))
                                  (setq failed (list (strcat source-handle ":OBJECT_UNISOLATION_FAILED")))
                                  (progn
                                    ;; Preserve the proven single-source cleanup path.
                                    (setq cx:*fb-phase* "POST_UNISOLATE_REGEN")
                                    (vl-catch-all-apply 'command-s (list "_.REGEN"))))
                                (setq cx:*fb-object-isolated* nil))))))))))))
          (if batch-isolated
            (progn
              (setq cx:*fb-phase* "UNISOLATE_MULTI_SOURCE")
              (if (not (cx:fb-unisolate-objects))
                (setq failed (list "MULTI_SOURCE_OBJECT_UNISOLATION_FAILED"))
                (vl-catch-all-apply 'command-s (list "_.REGEN")))
              (setq cx:*fb-object-isolated* nil)))
           (if (and (null failed) (= segment-count target-count))
             (progn
               (foreach dimension-handle all-added
                 (setq dimension-entity (handent dimension-handle))
                 (if (and dimension-entity (entget dimension-entity))
                   (progn
                     (setq dimension-object
                       (vl-catch-all-apply 'vlax-ename->vla-object (list dimension-entity)))
                     (if (and dimension-object
                              (not (vl-catch-all-error-p dimension-object)))
                       (vl-catch-all-apply 'vla-put-Visible (list dimension-object :vlax-true))))))
               (setq status "PASS" detail "ALL_NATIVE_TYPED_DIMENSIONS_ACCEPTED")
              (if cx:*full-batch-save-on-success* (vla-Save doc)))
            (progn
              (cx:fb-delete-handles all-added)
              (setq detail "BATCH_FAILED_AND_NEW_OBJECTS_ROLLED_BACK"))))
      )))
  (setq cx:*fb-phase* "WRITE_REPORT")
  (setq elapsed (- (getvar "MILLISECS") started)
        summary (list
          "STATUS\tDETAIL\tTASK_COUNT\tTARGET_SEGMENTS\tSUCCESS_COUNT\tROAD_COUNT\tSHORE_COUNT\tADDED_HANDLES\tFAILED\tCLEANUP_DELETED\tCLEAN_SLATE_DELETED\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
          (strcat status "\t" detail "\t" (itoa task-count) "\t" (itoa target-count) "\t"
            (if (= status "PASS") (itoa segment-count) "0") "\t"
            (if (= status "PASS") (itoa road-count) "0") "\t"
            (if (= status "PASS") (itoa shore-count) "0") "\t"
            (if (= status "PASS") (cx:fb-join all-added) "") "\t"
            (cx:fb-join failed) "\t" (cx:fb-join cleanup-deleted) "\t"
            (cx:fb-join clean-slate-deleted) "\t"
            (itoa elapsed) "\t" (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (cx:fb-write-lines cx:*full-batch-details-path* details)
  (cx:fb-write-lines cx:*full-batch-summary-path* summary)
  (setq *error* cx:*fb-old-error* cx:*fb-phase* "DONE")
  (princ))

(c:CXTDIMARCFULLBATCH)
