(vl-load-com)
;; V24 keeps the recently user-accepted endpoint-helper route as the ordinary
;; path.  The born-angle true-WCS route is an exception-only fallback.
;; Position rank never substitutes for rendered included-angle semantics.

(defun cx:seo24-result-rank (result / placement)
  (setq placement
    (if (and (listp result) (> (length result) 2)) (nth 2 result) nil))
  (if (and (listp placement) (numberp (car placement)))
    (fix (car placement)) 0))

(defun cx:seo24-result-grips (result / placement)
  (setq placement
    (if (and (listp result) (> (length result) 2)) (nth 2 result) nil))
  (if (and (listp placement) (> (length placement) 5)
           (numberp (nth 5 placement)))
    (fix (nth 5 placement)) 0))

(defun cx:seo24-result-handle (result / added)
  (setq added
    (if (and (listp result) (> (length result) 1)) (cadr result) '()))
  (if (= (length added) 1) (car added) ""))

(defun cx:seo24-native-signature-p
  (result expected-style / handle entity object)
  (setq handle (cx:seo24-result-handle result)
        entity (if (/= handle "") (handent handle) nil)
        object
          (if (and entity (entget entity))
            (vlax-ename->vla-object entity) nil))
  (and object
       (= (vla-get-ObjectName object) "TDbDimension2")
       (= (vla-get-Layer object) "PUB_DIM")
       (= (cx:fb-safe-property object 'DimStyle) expected-style)
       (= (cx:seo24-result-grips result) 5)
       (= (getvar "CMDNAMES") "")))

(defun cx:seo24-delete-result (result / added)
  (setq added
    (if (and (listp result) (> (length result) 1)) (cadr result) '()))
  (if added (cx:cs-delete-live-handles added))
  T)

(defun cx:seo24-with-detail (result detail / prior)
  (setq prior
    (if (and (listp result) (> (length result) 4)) (nth 4 result) ""))
  (list (car result) (cadr result) (nth 2 result) (nth 3 result)
    (strcat prior (if (= prior "") "" "|") detail)))

(defun cx:ha1-create-candidate
  (entity segment expected-style pick point audit-offset
    / ordinary ordinary-rank fallback fallback-rank)
  ;; The endpoint helper is the user-confirmed ordinary route.  It creates the
  ;; native degree object directly and is accepted only as five-grip rank2.
  (setq ordinary
    (cx:cdv1-base-endpoint-candidate
      entity segment expected-style pick point audit-offset)
        ordinary-rank (cx:seo24-result-rank ordinary))
  (if (and (>= ordinary-rank 2)
           (cx:seo24-native-signature-p ordinary expected-style))
    (cx:seo24-with-detail ordinary
      "SEMANTIC_EXCEPTION_ONLY_V24{route=ORDINARY_ENDPOINT_HELPER_FIVE_GRIP_RANK2_PRESERVED,special_chain_count=0,style_write=0,rendered_angle_gate=REQUIRED_BY_CONTROLLER}")
    (progn
      (cx:seo24-delete-result ordinary)
      ;; The saved V31 route is the run292/run275 born-angle path.  It may
      ;; return semantic rank1 for second-pass positioning, but it must be a
      ;; native five-grip object born in the requested angle style.
      (setq fallback
        (cx:seo24-semantic-fallback
          entity segment expected-style pick point audit-offset)
            fallback-rank (cx:seo24-result-rank fallback))
      (if (and (>= fallback-rank 1)
               (cx:seo24-native-signature-p fallback expected-style))
        (cx:seo24-with-detail fallback
          "SEMANTIC_EXCEPTION_ONLY_V24{route=SPECIAL_BORN_ANGLE_TRUE_WCS,trigger=ORDINARY_ENDPOINT_HELPER_NOT_RANK2,special_chain_count=1,style_write=0,rendered_angle_gate=REQUIRED_BY_CONTROLLER}")
        (progn
          (cx:seo24-delete-result fallback)
          (list (car fallback) '() (nth 2 fallback) nil
            "SEMANTIC_EXCEPTION_ONLY_V24{route=SPECIAL_REJECTED,reason=NATIVE_FIVE_GRIP_BORN_ANGLE_SIGNATURE_MISSING,style_write=0,rendered_angle_gate=NOT_REACHED}"))))))

(princ)
