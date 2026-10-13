;;; ==========================================================================
;;; input.lsp — interactive input (getpoint / getstring / getint).
;;; --------------------------------------------------------------------------
;;; Run:  LOAD input.lsp, then INPUTDEMO
;;; Picks two points for a line, a text label for the second point, and a
;;; repeat count for concentric circles around the first point.
;;; ==========================================================================

(defun c:INPUTDEMO (/ p1 p2 name n i)
  (setq p1 (getpoint "\nFirst point: "))
  (setq p2 (getpoint p1 "\nSecond point: "))
  (entmake (list '(0 . "LINE") (cons 10 p1) (cons 11 p2)))
  (setq name (getstring T "\nLabel: "))
  (entmake (list '(0 . "TEXT") (cons 10 p2) '(40 . 1.0) (cons 1 name)))
  (setq n (getint "\nHow many circles: "))
  (setq i 0)
  (repeat n
    (entmake (list '(0 . "CIRCLE") (cons 10 p1) (cons 40 (+ 1.0 i))))
    (setq i (1+ i)))
  (princ (strcat "\nDrew a line, a label, and " (itoa n) " circle(s)."))
  (princ)
)
