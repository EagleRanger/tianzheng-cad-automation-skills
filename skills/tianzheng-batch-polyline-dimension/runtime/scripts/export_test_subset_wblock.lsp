(vl-load-com)

;; Generic test-baseboard exporter.  Per-run handles, paths and counts are
;; injected by the owned PowerShell adapter and never stored in this file.
(if (not (boundp 'cx:*test-subset-handles*)) (setq cx:*test-subset-handles* '()))
(if (not (boundp 'cx:*test-subset-output*)) (setq cx:*test-subset-output* ""))
(if (not (boundp 'cx:*test-subset-report*)) (setq cx:*test-subset-report* ""))
(if (not (boundp 'cx:*test-subset-expected-drawing*)) (setq cx:*test-subset-expected-drawing* ""))

(defun cx:tsb-write-row (stream values)
  (write-line
    (apply 'strcat
      (cons (vl-princ-to-string (car values))
            (mapcar '(lambda (value) (strcat "\t" (vl-princ-to-string value))) (cdr values))))
    stream))

(defun cx:tsb-fullname (document)
  (vl-string-translate "\\" "/" (vla-get-FullName document)))

(defun cx:tsb-export (/ started document model requested resolved missing objects handle entity
                         sets selection object-array result stream dbmod-before dbmod-after status error-text)
  (setq started (getvar "MILLISECS")
        document (vla-get-ActiveDocument (vlax-get-acad-object))
        model (vla-get-ModelSpace document)
        dbmod-before (getvar "DBMOD")
        requested (length cx:*test-subset-handles*)
        resolved 0
        missing '()
        objects '()
        status "FAIL"
        error-text "")
  (cond
    ((or (= requested 0) (= cx:*test-subset-output* "") (= cx:*test-subset-report* ""))
      (setq error-text "INVALID_INPUT"))
    ((and (/= cx:*test-subset-expected-drawing* "")
          (/= (strcase (cx:tsb-fullname document)) (strcase cx:*test-subset-expected-drawing*)))
      (setq error-text "ACTIVE_DRAWING_MISMATCH"))
    (T
      (foreach handle cx:*test-subset-handles*
        (setq entity (handent handle))
        (if (and entity (= (cdr (assoc 410 (entget entity))) "Model"))
          (progn
            (setq objects (cons (vlax-ename->vla-object entity) objects))
            (setq resolved (1+ resolved)))
          (setq missing (cons handle missing))))
      (if (/= requested resolved)
        (setq error-text "TARGET_HANDLE_MISSING_OR_NOT_MODELSPACE")
        (progn
          (setq objects (reverse objects)
                sets (vla-get-SelectionSets document))
          (vl-catch-all-apply
            '(lambda () (vla-Delete (vla-Item sets "CX_TEST_SUBSET_WBLOCK"))) '())
          (setq selection (vla-Add sets "CX_TEST_SUBSET_WBLOCK")
                object-array (vlax-make-safearray vlax-vbObject (cons 0 (1- resolved))))
          (vlax-safearray-fill object-array objects)
          (vla-AddItems selection (vlax-make-variant object-array))
          (if (findfile cx:*test-subset-output*) (vl-file-delete cx:*test-subset-output*))
          (setq result
            (vl-catch-all-apply 'vla-WBlock (list document cx:*test-subset-output* selection)))
          (vla-Delete selection)
          (cond
            ((vl-catch-all-error-p result)
              (setq error-text (vl-catch-all-error-message result)))
            ((not (findfile cx:*test-subset-output*))
              (setq error-text "WBLOCK_OUTPUT_NOT_FOUND"))
            (T (setq status "PASS")))))))
  (setq dbmod-after (getvar "DBMOD")
        stream (open cx:*test-subset-report* "w"))
  (if stream
    (progn
      (cx:tsb-write-row stream '("STATUS" "SOURCE_DWG" "REQUESTED" "RESOLVED" "MISSING_HANDLES" "OUTPUT_PATH" "OUTPUT_EXISTS" "DBMOD_BEFORE" "DBMOD_AFTER" "ELAPSED_MS" "ERROR_TEXT"))
      (cx:tsb-write-row stream
        (list status (cx:tsb-fullname document) requested resolved
              (if missing (apply 'strcat (mapcar '(lambda (item) (strcat item ",")) (reverse missing))) "")
              cx:*test-subset-output* (if (findfile cx:*test-subset-output*) "YES" "NO")
              dbmod-before dbmod-after (- (getvar "MILLISECS") started) error-text))
      (close stream)))
  (princ (strcat "\nCX_TEST_SUBSET_WBLOCK " status ": " cx:*test-subset-report*))
  (princ))

(cx:tsb-export)
