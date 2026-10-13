;;; ==========================================================================
;;; shapes.lsp — create basic geometry with entmake.
;;; --------------------------------------------------------------------------
;;; Run:  LOAD shapes.lsp, then SHAPES
;;; Draws one LINE, CIRCLE, ARC, POINT, TEXT, and a closed LWPOLYLINE
;;; rectangle on the current layer.
;;; ==========================================================================

(defun c:SHAPES (/ )
  ;; Diagonal line from (0,0) to (10,10).
  (entmake '((0 . "LINE") (10 0 0 0) (11 10 10 0)))
  ;; Circle, center (20,5), radius 3.
  (entmake '((0 . "CIRCLE") (10 20 5 0) (40 . 3.0)))
  ;; Half arc, center (30,5), radius 3, 0 -> 180 degrees.
  (entmake '((0 . "ARC") (10 30 5 0) (40 . 3.0) (50 . 0.0) (51 . 180.0)))
  ;; A single point marker.
  (entmake '((0 . "POINT") (10 40 0 0)))
  ;; Text label, 1.5 units high.
  (entmake '((0 . "TEXT") (10 0 15 0) (40 . 1.5) (1 . "Hello Zephyr")))
  ;; Closed 10x10 rectangle polyline (flag 1 = closed).
  (entmake '((0 . "LWPOLYLINE") (90 . 4) (70 . 1)
             (10 45 0) (10 55 0) (10 55 10) (10 45 10)))
  (princ "\nCreated 6 entities: LINE CIRCLE ARC POINT TEXT LWPOLYLINE.")
  (princ)
)
