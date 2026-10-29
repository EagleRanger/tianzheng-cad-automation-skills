(vl-load-com)

;; T20 V10 prompt-profile probe and five-arc batch.
;; This adapter follows the locally observed prompt sequence:
;;   SELECT_ARC -> CHOOSE_TYPE_OR_SIDE -> PLACE_DIMENSION -> FINISH
;; It never uses the deprecated same-point type confirmation.

(if (not (boundp 'cx:*v10-source-handle*))
  (setq cx:*v10-source-handle* "18435D"))
(if (not (boundp 'cx:*v10-segments*))
  (setq cx:*v10-segments* '(0 2 3 4 6)))
(if (not (boundp 'cx:*v10-offset*))
  (setq cx:*v10-offset* 8.0))
(if (not (boundp 'cx:*v10-expected-drawing*))
  (setq cx:*v10-expected-drawing* ""))
(if (not (boundp 'cx:*v10-summary-path*))
  (setq cx:*v10-summary-path* "C:/tmp/cx_tdimarc_v10_summary.tsv"))
(if (not (boundp 'cx:*v10-details-path*))
  (setq cx:*v10-details-path* "C:/tmp/cx_tdimarc_v10_details.tsv"))
(if (not (boundp 'cx:*v10-save-on-success*))
  (setq cx:*v10-save-on-success* nil))

(defun cx:v10-normalize-path (value)
  (strcase (vl-string-translate "\\" "/" value)))

(defun cx:v10-safe-property (object property / result)
  (setq result (vl-catch-all-apply 'vlax-get-property (list object property)))
  (if (vl-catch-all-error-p result) "" (vl-princ-to-string result)))

(defun cx:v10-join (items / output item)
  (setq output "")
  (foreach item items
    (setq output
      (strcat output (if (= output "") "" ",") (vl-princ-to-string item))))
  output)

(defun cx:v10-write-lines (path lines / temporary file line)
  (setq temporary (strcat path ".tmp"))
  (if (findfile temporary) (vl-file-delete temporary))
  (setq file (open temporary "w"))
  (foreach line lines (write-line line file))
  (close file)
  (if (findfile path) (vl-file-delete path))
  (vl-file-rename temporary path))

(defun cx:v10-native-handles (/ doc space count index item result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-ModelSpace doc)
        count (vla-get-Count space)
        index 0
        result '())
  (repeat count
    (setq item (vla-Item space index))
    (if (= (vla-get-ObjectName item) "TDbDimension2")
      (setq result (cons (vla-get-Handle item) result)))
    (setq index (1+ index)))
  result)

(defun cx:v10-difference (after before / result item)
  (setq result '())
  (foreach item after
    (if (not (member item before)) (setq result (cons item result))))
  (reverse result))

(defun cx:v10-layer-state (/ doc layers count index layer result active-name)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layers (vla-get-Layers doc)
        active-name (vla-get-Name (vla-get-ActiveLayer doc))
        count (vla-get-Count layers)
        index 0
        result '())
  (repeat count
    (setq layer (vla-Item layers index))
    (setq result
      (cons
        (list (vla-get-Name layer)
              (vla-get-LayerOn layer)
              (vla-get-Freeze layer))
        result))
    (setq index (1+ index)))
  (list active-name result))

(defun cx:v10-set-layer-visible (name visible / doc layer)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layer (vla-Item (vla-get-Layers doc) name))
  (if visible
    (progn
      (vl-catch-all-apply 'vla-put-Freeze (list layer :vlax-false))
      (vl-catch-all-apply 'vla-put-LayerOn (list layer :vlax-true)))
    (vl-catch-all-apply 'vla-put-LayerOn (list layer :vlax-false))))

(defun cx:v10-isolate-source-layer (source-layer / doc layers count index layer name)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layers (vla-get-Layers doc)
        count (vla-get-Count layers)
        index 0)
  (cx:v10-set-layer-visible source-layer T)
  (vla-put-ActiveLayer doc (vla-Item layers source-layer))
  (repeat count
    (setq layer (vla-Item layers index)
          name (vla-get-Name layer))
    (if (not (member (strcase name) (list (strcase source-layer) "PUB_DIM" "0")))
      (vl-catch-all-apply 'vla-put-LayerOn (list layer :vlax-false)))
    (setq index (1+ index)))
  (if (tblsearch "LAYER" "PUB_DIM") (cx:v10-set-layer-visible "PUB_DIM" T)))

(defun cx:v10-restore-layers (snapshot / doc layers row layer active-name)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        layers (vla-get-Layers doc)
        active-name (car snapshot))
  (foreach row (cadr snapshot)
    (if (tblsearch "LAYER" (car row))
      (progn
        (setq layer (vla-Item layers (car row)))
        (vl-catch-all-apply 'vla-put-Freeze (list layer (caddr row)))
        (vl-catch-all-apply 'vla-put-LayerOn (list layer (cadr row))))))
  (if (tblsearch "LAYER" active-name)
    (vl-catch-all-apply
      'vla-put-ActiveLayer
      (list doc (vla-Item layers active-name)))))

(defun cx:v10-delete-handles (handles / handle entity)
  (foreach handle handles
    (setq entity (handent handle))
    (if entity (entdel entity))))

(defun cx:v10-segment-points (entity segment offset / pick-wcs deriv magnitude normal side-wcs)
  (setq pick-wcs (vlax-curve-getPointAtParam entity (+ segment 0.35))
        deriv (vlax-curve-getFirstDeriv entity (+ segment 0.35))
        magnitude (distance '(0.0 0.0 0.0) deriv)
        normal (list (/ (- (cadr deriv)) magnitude) (/ (car deriv) magnitude) 0.0)
        side-wcs (mapcar '+ pick-wcs
                   (mapcar '(lambda (value) (* value offset)) normal)))
  (list (trans pick-wcs 0 1) (trans side-wcs 0 1)))

(defun cx:v10-run-one (entity segment offset / points pick side before after added call-result)
  (setq points (cx:v10-segment-points entity segment offset)
        pick (car points)
        side (cadr points)
        before (cx:v10-native-handles)
        ;; Exact T20 V10 prompt sequence.  The side point is intentionally
        ;; supplied once for CHOOSE_TYPE_OR_SIDE and once for PLACE_DIMENSION.
        call-result
          (vl-catch-all-apply
            'command-s
            (list "TDIMARC" pick side side ""))
        after (cx:v10-native-handles)
        added (cx:v10-difference after before))
  (list call-result added pick side))

(defun cx:v10-accept-one (result / call-result added handle entity object object-name layer dim-style)
  (setq call-result (car result)
        added (cadr result)
        handle ""
        object-name ""
        layer ""
        dim-style "")
  (if (= (length added) 1)
    (progn
      (setq handle (car added)
            entity (handent handle))
      (if entity
        (progn
          (setq object (vlax-ename->vla-object entity)
                object-name (vla-get-ObjectName object)
                layer (vla-get-Layer object)
                dim-style (cx:v10-safe-property object 'DimStyle))))))
  (list
    (and (not (vl-catch-all-error-p call-result))
         (= (length added) 1)
         (= object-name "TDbDimension2")
         (= layer "PUB_DIM")
         (= dim-style "_TCH_ARROW")
         (= (getvar "CMDNAMES") "")
         (or (= (getvar "CMDACTIVE") 0) (= (getvar "CMDACTIVE") 4)))
    handle object-name layer dim-style))

(defun c:CXTDIMARCV10BATCH
  (/ started doc drawing entity object source-layer snapshot minimum maximum min-list max-list
     margin gate-segment gate-result gate-accepted batch-before segment one-result accepted
     all-added failed details status detail summary elapsed)
  (setq started (getvar "MILLISECS")
        status "FAIL"
        detail ""
        all-added '()
        failed '()
        details
          (list "PHASE\tSEGMENT_INDEX\tSTATUS\tADDED_HANDLE\tOBJECT_NAME\tLAYER\tDIM_STYLE\tPICK_X\tPICK_Y\tSIDE_X\tSIDE_Y\tCMDACTIVE\tCMDNAMES"))
  (setq drawing (cx:v10-normalize-path (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))))
  (cond
    ((and (/= cx:*v10-expected-drawing* "")
          (/= drawing (cx:v10-normalize-path cx:*v10-expected-drawing*)))
      (setq detail "ACTIVE_DRAWING_MISMATCH"))
    ((null (setq entity (handent cx:*v10-source-handle*)))
      (setq detail "SOURCE_HANDLE_NOT_FOUND"))
    ((/= (vla-get-ObjectName (setq object (vlax-ename->vla-object entity))) "AcDbPolyline")
      (setq detail "SOURCE_IS_NOT_ACDBPOLYLINE"))
    (t
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
            source-layer (vla-get-Layer object)
            snapshot (cx:v10-layer-state))
      (cx:v10-isolate-source-layer source-layer)
      (vla-GetBoundingBox object 'minimum 'maximum)
      (setq min-list (vlax-safearray->list minimum)
            max-list (vlax-safearray->list maximum)
            margin (+ 5.0 (* 2.0 (abs cx:*v10-offset*))))
      (vl-catch-all-apply
        'command-s
        (list "_.ZOOM" "_W"
          (trans (list (- (car min-list) margin) (- (cadr min-list) margin) 0.0) 0 1)
          (trans (list (+ (car max-list) margin) (+ (cadr max-list) margin) 0.0) 0 1)))
      (vl-catch-all-apply 'command-s (list "_.REGEN"))

      ;; Fresh one-arc gate in the exact active drawing.  The accepted gate
      ;; object is deleted before the five-segment batch starts.
      (setq gate-segment (car cx:*v10-segments*)
            gate-result (cx:v10-run-one entity gate-segment cx:*v10-offset*)
            gate-accepted (cx:v10-accept-one gate-result))
      (setq details
        (append details
          (list
            (strcat "GATE\t" (itoa gate-segment) "\t"
              (if (car gate-accepted) "PASS" "FAIL") "\t"
              (cadr gate-accepted) "\t" (caddr gate-accepted) "\t"
              (cadddr gate-accepted) "\t" (nth 4 gate-accepted) "\t"
              (rtos (car (nth 2 gate-result)) 2 6) "\t"
              (rtos (cadr (nth 2 gate-result)) 2 6) "\t"
              (rtos (car (nth 3 gate-result)) 2 6) "\t"
              (rtos (cadr (nth 3 gate-result)) 2 6) "\t"
              (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES")))))
      (if (car gate-accepted)
        (progn
          (cx:v10-delete-handles (cadr gate-result))
          (setq batch-before (cx:v10-native-handles))
          (foreach segment cx:*v10-segments*
            (if (null failed)
              (progn
                (setq one-result (cx:v10-run-one entity segment cx:*v10-offset*)
                      accepted (cx:v10-accept-one one-result))
                (if (car accepted)
                  (setq all-added (append all-added (cadr one-result)))
                  (setq failed (append failed (list segment))))
                (setq details
                  (append details
                    (list
                      (strcat "BATCH\t" (itoa segment) "\t"
                        (if (car accepted) "PASS" "FAIL") "\t"
                        (cadr accepted) "\t" (caddr accepted) "\t"
                        (cadddr accepted) "\t" (nth 4 accepted) "\t"
                        (rtos (car (nth 2 one-result)) 2 6) "\t"
                        (rtos (cadr (nth 2 one-result)) 2 6) "\t"
                        (rtos (car (nth 3 one-result)) 2 6) "\t"
                        (rtos (cadr (nth 3 one-result)) 2 6) "\t"
                        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))))))
          (if (and (null failed)
                   (= (length all-added) (length cx:*v10-segments*)))
            (progn
              (setq status "PASS" detail "FRESH_GATE_AND_FIVE_NATIVE_DIMENSIONS_ACCEPTED")
              (if cx:*v10-save-on-success* (vla-Save doc)))
            (progn
              (cx:v10-delete-handles all-added)
              (setq detail "BATCH_NATIVE_CONTRACT_FAILED_ROLLED_BACK"))))
        (progn
          (cx:v10-delete-handles (cadr gate-result))
          (setq detail "FRESH_PROMPT_PROFILE_GATE_FAILED")))
      (if (= (getvar "CMDNAMES") "")
        (vl-catch-all-apply 'command-s (list "_.ZOOM" "_P")))
      (cx:v10-restore-layers snapshot)))
  (setq elapsed (- (getvar "MILLISECS") started))
  (setq summary
    (list
      "STATUS\tDETAIL\tSOURCE_HANDLE\tSEGMENTS\tOFFSET\tSUCCESS_COUNT\tADDED_HANDLES\tFAILED_SEGMENTS\tELAPSED_MS\tCMDACTIVE\tCMDNAMES"
      (strcat status "\t" detail "\t" cx:*v10-source-handle* "\t"
        (cx:v10-join cx:*v10-segments*) "\t" (rtos cx:*v10-offset* 2 6) "\t"
        (if (= status "PASS") (itoa (length all-added)) "0") "\t"
        (if (= status "PASS") (cx:v10-join all-added) "") "\t"
        (cx:v10-join failed) "\t" (itoa elapsed) "\t"
        (itoa (getvar "CMDACTIVE")) "\t" (getvar "CMDNAMES"))))
  (cx:v10-write-lines cx:*v10-details-path* details)
  (cx:v10-write-lines cx:*v10-summary-path* summary)
  (princ))

(c:CXTDIMARCV10BATCH)
