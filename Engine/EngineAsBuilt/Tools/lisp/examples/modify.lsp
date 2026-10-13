;;; ==========================================================================
;;; modify.lsp — read and rewrite entities (entget / entmod / subst).
;;; --------------------------------------------------------------------------
;;; Run:  LOAD modify.lsp, then REDCIRCLES
;;; Colors every CIRCLE in the drawing red (color index 1), adding group 62
;;; where missing. Reports how many circles were changed.
;;; ==========================================================================

(defun c:REDCIRCLES (/ ss i n e changed)
  (setq ss (ssget "_X" '((0 . "CIRCLE"))))
  (if (null ss)
    (progn (princ "\nNo circles found.") (princ))
    (progn
      (setq i 0
            n (sslength ss)
            changed 0)
      (repeat n
        (setq e (entget (ssname ss i)))
        (entmod (if (assoc 62 e)
                  (subst '(62 . 1) (assoc 62 e) e)
                  (append e (list '(62 . 1)))))
        (setq changed (1+ changed)
              i (1+ i)))
      (princ (strcat "\nColored " (itoa changed) " circle(s) red."))
      (princ)))
)
