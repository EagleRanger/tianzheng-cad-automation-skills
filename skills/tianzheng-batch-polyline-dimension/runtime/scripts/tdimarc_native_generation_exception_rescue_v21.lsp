(vl-load-com)
;; V21 preserves normal rank2 candidates. A missing/rank0/rank1 exceptional
;; candidate is discarded, then the versioned run219 dynamic full-polyline
;; translation rescue is tried once. Only a rank2 rescue survives.

(defun cx:er21-delete-result (result / handles handle entity)
  (setq handles (if (and (listp result) (> (length result) 1)) (cadr result) '()))
  (foreach handle handles
    (setq entity (handent handle))
    (if (and entity (entget entity))
      (vl-catch-all-apply 'vla-Delete (list (vlax-ename->vla-object entity)))))
  T)

(defun cx:er21-rank (result / placement)
  (setq placement (if (and (listp result) (> (length result) 2)) (nth 2 result) nil))
  (if (and (listp placement) (numberp (car placement))) (fix (car placement)) 0))

(defun cx:er21-with-detail (result detail / current)
  (setq current (if (and (listp result) (> (length result) 4)) (nth 4 result) ""))
  (list (car result) (cadr result) (nth 2 result) (nth 3 result)
    (strcat current (if (= current "") "" "|") detail)))

(defun cx:ha1-create-candidate
  (entity segment expected-style pick point audit-offset
    / ordinary ordinary-rank rescue rescue-rank detail)
  (setq ordinary
          (cx:er21-base-create-candidate
            entity segment expected-style pick point audit-offset)
        ordinary-rank (cx:er21-rank ordinary))
  (if (>= ordinary-rank 2)
    (cx:er21-with-detail ordinary
      "EXCEPTION_RESCUE_V21{route=NORMAL_RANK2_PRESERVED,rescue_count=0}")
    (progn
      (cx:er21-delete-result ordinary)
      (setq rescue
              (cx:er21-dynamic-full-polyline-rescue
                entity segment expected-style pick point audit-offset)
            rescue-rank (cx:er21-rank rescue)
            detail
              (strcat "EXCEPTION_RESCUE_V21{route=RUNTIME_ABNORMAL_ONLY"
                ",trigger=ORDINARY_RANK_BELOW_2"
                ",ordinary_rank=" (itoa ordinary-rank)
                ",rescue_rank=" (itoa rescue-rank)
                ",accepted=" (if (>= rescue-rank 2) "YES" "NO")
                ",normal_objects_frozen=YES"
                ",board_literals=0}"))
      (if (>= rescue-rank 2)
        (cx:er21-with-detail rescue detail)
        (progn
          (cx:er21-delete-result rescue)
          (list (car rescue) '() (nth 2 rescue) nil detail))))))

(princ)
