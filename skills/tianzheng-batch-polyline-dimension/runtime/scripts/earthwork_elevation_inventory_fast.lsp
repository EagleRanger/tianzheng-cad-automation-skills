(vl-load-com)

(setq cx:ewf-root (getvar "DWGPREFIX"))

(defun cx:ewf-replace-all (new old value / pos)
  (if (null value) (setq value ""))
  (while (setq pos (vl-string-search old value))
    (setq value (strcat (substr value 1 pos) new (substr value (+ pos (strlen old) 1)))))
  value)

(defun cx:ewf-clean (value / result)
  (cond
    ((null value) (setq result ""))
    ((= (type value) 'STR) (setq result value))
    ((numberp value) (setq result (rtos value 2 12)))
    (T (setq result (vl-princ-to-string value))))
  (setq result (cx:ewf-replace-all " " (chr 9) result))
  (setq result (cx:ewf-replace-all " " (chr 10) result))
  (setq result (cx:ewf-replace-all " " (chr 13) result))
  result)

(defun cx:ewf-write-row (stream items / row item)
  (setq row "")
  (foreach item items
    (setq row (if (= row "") (cx:ewf-clean item) (strcat row (chr 9) (cx:ewf-clean item)))))
  (write-line row stream))

(defun cx:ewf-safe-prop (obj prop / value)
  (if (vlax-property-available-p obj prop)
    (progn
      (setq value (vl-catch-all-apply 'vlax-get-property (list obj prop)))
      (if (vl-catch-all-error-p value) nil value))
    nil))

(defun cx:ewf-array-list (value / raw)
  (cond
    ((null value) nil)
    ((= (type value) 'VARIANT) (cx:ewf-array-list (vlax-variant-value value)))
    ((= (type value) 'SAFEARRAY)
      (setq raw (vl-catch-all-apply 'vlax-safearray->list (list value)))
      (if (vl-catch-all-error-p raw) nil raw))
    ((listp value) value)
    (T nil)))

(defun cx:ewf-point-z (value / raw)
  (setq raw (cx:ewf-array-list value))
  (if (and raw (>= (length raw) 3)) (nth 2 raw) nil))

(defun cx:ewf-coordinate-z-range (obj / object raw index z zmin zmax)
  (setq object (cx:ewf-safe-prop obj 'ObjectName))
  (if (not (member object '("AcDb3dPolyline" "AcDb2dPolyline")))
    '("" "")
    (progn
      (setq raw (cx:ewf-array-list (cx:ewf-safe-prop obj 'Coordinates)))
      (setq index 2)
      (while (and raw (< index (length raw)))
        (setq z (nth index raw))
        (if (or (null zmin) (< z zmin)) (setq zmin z))
        (if (or (null zmax) (> z zmax)) (setq zmax z))
        (setq index (+ index 3)))
      (list (if zmin zmin "") (if zmax zmax "")))))

(defun cx:ewf-block-name (obj / value)
  (setq value (cx:ewf-safe-prop obj 'EffectiveName))
  (if (or (null value) (= value "")) (setq value (cx:ewf-safe-prop obj 'Name)))
  value)

(defun cx:ewf-write-attributes (stream owner / attrs att)
  (if (= (cx:ewf-safe-prop owner 'HasAttributes) :vlax-true)
    (progn
      (setq attrs (vl-catch-all-apply 'vlax-invoke (list owner 'GetAttributes)))
      (if (not (vl-catch-all-error-p attrs))
        (foreach att attrs
          (cx:ewf-write-row stream
            (list
              (cx:ewf-safe-prop owner 'Handle)
              (cx:ewf-block-name owner)
              (cx:ewf-safe-prop owner 'Layer)
              (cx:ewf-safe-prop att 'Handle)
              (cx:ewf-safe-prop att 'TagString)
              (cx:ewf-safe-prop att 'TextString)
              (cx:ewf-point-z (cx:ewf-safe-prop att 'InsertionPoint)))))))))

(defun c:CXEWFAST (/ acad doc model entity-stream attr-stream done obj zrange count dbmod-before)
  (setq acad (vlax-get-acad-object))
  (setq doc (vla-get-ActiveDocument acad))
  (setq model (vla-get-ModelSpace doc))
  (setq dbmod-before (getvar "DBMOD"))
  (setq entity-stream (open (strcat cx:ewf-root "earthwork_elevation_entities_fast.tsv") "w"))
  (setq attr-stream (open (strcat cx:ewf-root "earthwork_elevation_attributes_fast.tsv") "w"))
  (cx:ewf-write-row entity-stream
    '("HANDLE" "OBJECT" "LAYER" "BLOCK" "TEXT_STRING" "TCH_TEXT" "TEXT_OVERRIDE" "ELEVATION" "VALUE" "POSITION_Z" "INSERTION_Z" "START_Z" "END_Z" "CENTER_Z" "COORD_Z_MIN" "COORD_Z_MAX"))
  (cx:ewf-write-row attr-stream
    '("OWNER_HANDLE" "BLOCK" "LAYER" "ATTRIBUTE_HANDLE" "TAG" "TEXT" "INSERTION_Z"))
  (setq count 0)
  (vlax-for obj model
    (setq zrange (cx:ewf-coordinate-z-range obj))
    (cx:ewf-write-row entity-stream
      (list
        (cx:ewf-safe-prop obj 'Handle)
        (cx:ewf-safe-prop obj 'ObjectName)
        (cx:ewf-safe-prop obj 'Layer)
        (cx:ewf-block-name obj)
        (cx:ewf-safe-prop obj 'TextString)
        (cx:ewf-safe-prop obj 'Text)
        (cx:ewf-safe-prop obj 'TextOverride)
        (cx:ewf-safe-prop obj 'Elevation)
        (cx:ewf-safe-prop obj 'Value)
        (cx:ewf-point-z (cx:ewf-safe-prop obj 'Position))
        (cx:ewf-point-z (cx:ewf-safe-prop obj 'InsertionPoint))
        (cx:ewf-point-z (cx:ewf-safe-prop obj 'StartPoint))
        (cx:ewf-point-z (cx:ewf-safe-prop obj 'EndPoint))
        (cx:ewf-point-z (cx:ewf-safe-prop obj 'Center))
        (car zrange)
        (cadr zrange)))
    (cx:ewf-write-attributes attr-stream obj)
    (setq count (1+ count)))
  (close entity-stream)
  (close attr-stream)
  (setq done (open (strcat cx:ewf-root "earthwork_elevation_inventory_fast.done") "w"))
  (cx:ewf-write-row done (list "OK" (getvar "DWGNAME") count "DBMOD_BEFORE" dbmod-before "DBMOD_AFTER" (getvar "DBMOD")))
  (close done)
  (princ (strcat "\nCXEWFAST complete: " (itoa count) " entities."))
  (princ))

(princ "\nCXEWFAST loaded. Run CXEWFAST.")
(princ)
