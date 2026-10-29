(vl-load-com)
;; V19 is the full-scope semantic promotion adapter.
;; Ordinary candidates that already passed the native rank2 gate are returned
;; unchanged.  Only a surviving five-grip native angle candidate below rank2
;; is promoted to the explicit semantic rank1 handoff for the unified layout.

(defun cx:sp19-delete-handles (handles / handle entity)
  (foreach handle handles
    (setq entity (handent handle))
    (if (and entity (entget entity))
      (vl-catch-all-apply
        'vla-Delete (list (vlax-ename->vla-object entity)))))
  T)

(defun cx:ha1-create-candidate
  (entity segment expected-style pick point audit-offset
    / result added original-placement original-valid original-rank handle
      candidate object-name layer dim-style grips signature detail promoted-placement)
  (setq result
          (cx:sp19-base-create-candidate
            entity segment expected-style pick point audit-offset)
        added
          (if (and (listp result) (> (length result) 1))
            (cadr result) '())
        original-placement
          (if (and (listp result) (> (length result) 2))
            (nth 2 result) nil)
        original-valid
          (if (and (listp result) (> (length result) 3))
            (nth 3 result) nil)
        original-rank
          (if (and (listp original-placement)
                   (> (length original-placement) 0)
                   (numberp (car original-placement)))
            (fix (car original-placement)) 0)
        handle (if (= (length added) 1) (car added) "")
        candidate
          (if (and (/= handle "") (handent handle) (entget (handent handle)))
            (vlax-ename->vla-object (handent handle)) nil)
        object-name (if candidate (vla-get-ObjectName candidate) "")
        layer (if candidate (vla-get-Layer candidate) "")
        dim-style
          (if candidate (cx:fb-safe-property candidate 'DimStyle) "")
        grips
          (if (and (listp original-placement)
                   (> (length original-placement) 5)
                   (numberp (nth 5 original-placement)))
            (fix (nth 5 original-placement)) 0)
        signature
          (and candidate
               (= object-name "TDbDimension2")
               (= layer "PUB_DIM")
               (= dim-style expected-style)
               (= grips 5)
               (= (getvar "CMDNAMES") ""))
        detail
          (strcat
            "TRUE_WCS_SEMANTIC_PROMOTION_V19{handle=" handle
            ",native=" object-name
            ",layer=" layer
            ",style=" dim-style
            ",grips=" (itoa grips)
            ",original_rank=" (itoa original-rank)
            ",ordinary_rank2_preserved="
              (if (and original-valid (>= original-rank 2)) "YES" "NO")
            ",semantic_first_pass_rank=1"
            ",endpoint_rank2_claimed=NO"
            ",second_pass_unified_layout_required=YES"
            ",accepted=" (if signature "YES" "NO") "}")
        promoted-placement (list 1 detail 0.0 audit-offset 1e99 grips)
        cx:*sp2-last-trace* (strcat cx:*sp2-last-trace* "|" detail))
  (cond
    ((and original-valid (>= original-rank 2)) result)
    (signature (list (car result) added promoted-placement T))
    (T
      (cx:sp19-delete-handles added)
      (list (car result) '()
        (list 0 detail 0.0 audit-offset 1e99 grips) nil))))

(princ)
