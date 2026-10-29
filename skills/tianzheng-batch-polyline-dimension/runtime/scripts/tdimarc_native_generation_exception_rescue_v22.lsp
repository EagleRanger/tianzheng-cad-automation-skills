(vl-load-com)
;; V22 adds one generic, already field-proven route between the frozen normal
;; path and the translated full-polyline rescue.  Only a failed ordinary
;; candidate reaches it.  It retries the original source arc with the existing
;; adaptive fraction sequence and accepts only a post-audited rank2 object.

(defun cx:er22-direct-source-fraction-rescue
  (entity segment expected-style audit-offset
    / geometry text-height effective-offset raw added handle placement valid detail)
  (setq geometry (cx:ups-arc-geometry entity segment)
        text-height (cx:ups-text-height-from-effective audit-offset)
        effective-offset
          (if (and (listp geometry) (= (car geometry) "PASS") (> text-height 1e-9))
            (cx:ups-outer-offset (nth 1 geometry) text-height)
            audit-offset)
        raw (cx:ss-v2-run-one entity segment effective-offset expected-style)
        added (if (and (listp raw) (> (length raw) 1)) (cadr raw) '())
        handle (if (= (length added) 1) (car added) "")
        placement
          (if (/= handle "")
            (cx:pg-audit entity "ARC" segment handle audit-offset)
            (list 0 "DIRECT_SOURCE_FRACTION_NO_CANDIDATE" 0.0 audit-offset 1e99 0))
        valid (and (= (length added) 1) (cx:pg-audit-normal-p placement))
        detail
          (strcat "EXCEPTION_DIRECT_SOURCE_FRACTION_V22{"
            "route=ORIGINAL_SOURCE_ARC_ADAPTIVE_FRACTIONS"
            ",trigger=ORDINARY_RANK_BELOW_2"
            ",accepted=" (if valid "YES" "NO")
            ",rank=" (itoa (cx:er21-rank (list (car raw) added placement valid)))
            ",attempts=" (if (and (listp raw) (> (length raw) 4)) (nth 4 raw) "") "}"))
  (list (car raw) added placement valid detail))

(defun cx:er22-result-with-detail (result extra / detail)
  (setq detail (if (and (listp result) (> (length result) 4)) (nth 4 result) ""))
  (list (car result) (cadr result) (nth 2 result) (nth 3 result)
    (if (= detail "") extra (strcat detail "|" extra))))

(defun cx:ha1-create-candidate
  (entity segment expected-style pick point audit-offset
    / ordinary ordinary-rank direct direct-rank rescue rescue-rank)
  (setq ordinary
          (cx:er21-base-create-candidate
            entity segment expected-style pick point audit-offset)
        ordinary-rank (cx:er21-rank ordinary))
  (cond
    ((>= ordinary-rank 2)
      (cx:er22-result-with-detail ordinary
        "EXCEPTION_RESCUE_V22{route=NORMAL_RANK2_PRESERVED,rescue_count=0}"))
    (t
      (cx:er21-delete-result ordinary)
      (setq direct
              (cx:er22-direct-source-fraction-rescue
                entity segment expected-style audit-offset)
            direct-rank (cx:er21-rank direct))
      (if (>= direct-rank 2)
        (cx:er22-result-with-detail direct
          (strcat "EXCEPTION_RESCUE_V22{route=RUNTIME_ABNORMAL_ONLY"
            ",stage=DIRECT_SOURCE_FRACTION,ordinary_rank=" (itoa ordinary-rank)
            ",direct_rank=" (itoa direct-rank) ",accepted=YES}"))
        (progn
          (cx:er21-delete-result direct)
          (setq rescue
                  (cx:er21-dynamic-full-polyline-rescue
                    entity segment expected-style pick point audit-offset)
                rescue-rank (cx:er21-rank rescue))
          (if (>= rescue-rank 2)
            (cx:er22-result-with-detail rescue
              (strcat "EXCEPTION_RESCUE_V22{route=RUNTIME_ABNORMAL_ONLY"
                ",stage=TRANSLATED_FULL_POLYLINE,ordinary_rank=" (itoa ordinary-rank)
                ",direct_rank=" (itoa direct-rank)
                ",rescue_rank=" (itoa rescue-rank) ",accepted=YES}"))
            (progn
              (cx:er21-delete-result rescue)
              (list (car rescue) '() (nth 2 rescue) nil
                (strcat "EXCEPTION_RESCUE_V22{route=RUNTIME_ABNORMAL_ONLY"
                  ",stage=ALL_RESCUES_EXHAUSTED,ordinary_rank=" (itoa ordinary-rank)
                  ",direct_rank=" (itoa direct-rank)
                  ",rescue_rank=" (itoa rescue-rank) ",accepted=NO}")))))))))

(princ)
