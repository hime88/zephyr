;;; ==========================================================================
;;; selection.lsp — selection-set queries (ssget / sslength / ssname).
;;; --------------------------------------------------------------------------
;;; Run:  LOAD selection.lsp, then SELCOUNT
;;; Seeds 3 lines + 2 circles (one of each red), then counts:
;;;   all entities, circles by type, and red entities by color.
;;; Returns an assoc list, e.g. (("all" . 5) ("circles" . 2) ("red" . 2)).
;;; ==========================================================================

(defun c:SELCOUNT (/ seed all circles red)
  ;; Seed the drawing (BYLAYER except where noted).
  (entmake '((0 . "LINE") (10 0 0 0) (11 10 0 0)))
  (entmake '((0 . "LINE") (10 0 5 0) (11 10 5 0) (62 . 1)))
  (entmake '((0 . "LINE") (10 0 10 0) (11 10 10 0)))
  (entmake '((0 . "CIRCLE") (10 20 5 0) (40 . 3.0)))
  (entmake '((0 . "CIRCLE") (10 30 5 0) (40 . 2.0) (62 . 1)))
  ;; Query the whole database with DXF filters.
  (setq all (ssget "_X"))
  (setq circles (ssget "_X" '((0 . "CIRCLE"))))
  (setq red (ssget "_X" '((62 . 1))))
  (princ (strcat "\nall=" (itoa (sslength all))
                 " circles=" (itoa (sslength circles))
                 " red=" (itoa (sslength red))))
  (list (cons "all" (sslength all))
        (cons "circles" (sslength circles))
        (cons "red" (sslength red)))
)
