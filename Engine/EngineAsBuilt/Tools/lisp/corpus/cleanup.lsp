;;; ==========================================================================
;;; CleanSpeckles.lsp   (AutoCAD LT 2024+ / full AutoCAD)
;;; --------------------------------------------------------------------------
;;; SELECT-BY-EXAMPLE speckle cleaner.
;;;
;;; Workflow:
;;;   1. Pre-select a few example speckles (grips showing). Include the BIGGEST
;;;      one (sets the size ceiling) and one of each colour variant.
;;;   2. Run  CLEANSPECKLES .
;;;   3. Window the area to clean.
;;;
;;; Learned from the examples: COLOUR(s) + SIZE ceiling. Nothing to type.
;;;
;;; DEFAULT behaviour = pure pattern match: every object whose colour, size and
;;; type match the examples is selected, regardless of what it touches. This is
;;; the most aggressive mode and grabs speckles right up against pipes/walls.
;;;
;;; Optional safeguards (off by default - flip near the top of the function):
;;;   doCluster T : spare same-colour tiles that chain into one LARGE connected
;;;                 shape (use when a real curve/fixture is triangulated in the
;;;                 same colour as the speckles, so you don't grab it).
;;;   doTouch  T  : (needs doCluster) spare a cluster that physically touches
;;;                 non-speckle geometry (e.g. caps welded to a channel).
;;;
;;; Only HIGHLIGHTS the result. Review, Shift-deselect keepers, then ERASE.
;;; ==========================================================================

(vl-load-com)

(defun spk-lw-hasbulge (el / has)
  (setq has nil)
  (foreach pr el (if (and (= (car pr) 42) (/= (cdr pr) 0.0)) (setq has T)))
  has
)

(defun spk-pl-hasbulge (ent / v has el)
  (setq has nil v (entnext ent))
  (while (and v (not has)
              (setq el (entget v))
              (= (cdr (assoc 0 el)) "VERTEX"))
    (if (/= (cdr (assoc 42 el)) 0.0) (setq has T))
    (setq v (entnext v))
  )
  has
)

(defun spk-colorsig (el)
  (cond
    ((assoc 420 el) (strcat "T" (itoa (cdr (assoc 420 el)))))
    ((assoc 62  el) (strcat "A" (itoa (cdr (assoc 62  el)))))
    (T              (strcat "L" (cdr (assoc 8 el))))
  )
)

(defun spk-diag (ent / obj minPt maxPt mn mx sx sy)
  (setq obj (vlax-ename->vla-object ent) minPt nil maxPt nil)
  (vl-catch-all-apply 'vla-getboundingbox (list obj 'minPt 'maxPt))
  (if (and minPt maxPt)
    (progn
      (setq mn (vlax-safearray->list minPt) mx (vlax-safearray->list maxPt)
            sx (abs (- (car mx) (car mn))) sy (abs (- (cadr mx) (cadr mn))))
      (sqrt (+ (* sx sx) (* sy sy))))
    0.0
  )
)

(defun spk-near (ax1 ay1 ax2 ay2 bx1 by1 bx2 by2 g / gx gy)
  (setq gx (max (- bx1 ax2) (- ax1 bx2) 0.0)
        gy (max (- by1 ay2) (- ay1 by2) 0.0))
  (and (<= gx g) (<= gy g))
)

(defun spk-anchored (x1 y1 x2 y2 gap tag / aw j ae ah res)
  (setq res nil)
  (setq aw (ssget "_C" (list (- x1 gap) (- y1 gap)) (list (+ x2 gap) (+ y2 gap))))
  (if aw
    (progn
      (setq j 0)
      (while (and (< j (sslength aw)) (not res))
        (setq ae (ssname aw j) ah (cdr (assoc 5 (entget ae))))
        (if (not (boundp (read (strcat tag "H_" ah)))) (setq res T))
        (setq j (1+ j))
      )
    )
  )
  res
)

(defun c:CleanSpeckles ( / doCluster doTouch
                          exSS sampleSigs maxDiag connectGap touchGap clusterMax
                          cell tag pt1 pt2
                          ss i ent el etype sig dg keep obj minPt maxPt mn mx
                          sx sy hnd n cands idx c m ix iy key bsym usedKeys
                          stack k kd kx1 ky1 kx2 ky2 kcx kcy gx gy
                          members cminx cminy cmaxx cmaxy cdx cdy cdiag
                          md mx1 my1 mx2 my2 finalSS)

  ;; ============ OPTIONAL SAFEGUARDS (off = pure pattern match) ============
  (setq doCluster nil    ; T to protect same-colour tiles that form a big shape
        doTouch   nil)    ; T (needs doCluster) to protect tiles welded to geometry

  ;; ============ LEARN from example objects ============
  (setq exSS (ssget "_I"))
  (if (not exSS)
    (setq exSS (ssget "\nSelect a few example speckles, then Enter: ")))
  (sssetfirst nil nil)

  (if (not exSS)
    (princ "\nNo examples selected - nothing to learn from.")
    (progn
      (setq sampleSigs '() maxDiag 0.0 i 0)
      (while (< i (sslength exSS))
        (setq ent (ssname exSS i) el (entget ent) sig (spk-colorsig el))
        (if (not (member sig sampleSigs)) (setq sampleSigs (cons sig sampleSigs)))
        (setq dg (spk-diag ent))
        (if (> dg maxDiag) (setq maxDiag dg))
        (setq i (1+ i))
      )
      (setq maxDiag (* maxDiag 1.3))
      (if (<= maxDiag 1e-9)
        (progn (setq maxDiag 0.05)
               (prompt "\nCould not learn a size (only dots?) - using 0.05.")))
      (prompt (strcat "\nLearned: " (itoa (length sampleSigs))
                      " colour(s), max speckle diagonal ~" (rtos maxDiag 2 4) "."))

      (setq connectGap (* maxDiag 0.5)
            touchGap   (* maxDiag 0.05)
            clusterMax (* maxDiag 3.0)
            cell       maxDiag
            tag        (strcat "spk_" (itoa (getvar "MILLISECS")) "_"))

      ;; ============ pick the area to clean ============
      (setq pt1 (getpoint "\nClick first corner of the area to clean: "))
      (if pt1 (setq pt2 (getcorner pt1 "\nClick opposite corner: ")))

      (if (and pt1 pt2)
        (progn
          (setq ss (ssget "C" pt1 pt2))
          (if ss
            (progn
              ;; ============ PASS 1: collect matching candidates ============
              (setq cands '() i 0)
              (while (< i (sslength ss))
                (setq ent (ssname ss i) el (entget ent) etype (cdr (assoc 0 el)))
                (if (and (member etype '("POINT" "LINE" "LWPOLYLINE" "TRACE" "SOLID" "POLYLINE"))
                         (member (spk-colorsig el) sampleSigs))
                  (progn
                    (setq keep T)
                    (cond
                      ((= etype "LWPOLYLINE") (if (spk-lw-hasbulge el)  (setq keep nil)))
                      ((= etype "POLYLINE")   (if (spk-pl-hasbulge ent) (setq keep nil)))
                    )
                    (if keep
                      (progn
                        (setq obj (vlax-ename->vla-object ent) minPt nil maxPt nil)
                        (vl-catch-all-apply 'vla-getboundingbox (list obj 'minPt 'maxPt))
                        (if (and minPt maxPt)
                          (progn
                            (setq mn (vlax-safearray->list minPt)
                                  mx (vlax-safearray->list maxPt)
                                  sx (abs (- (car mx)  (car mn)))
                                  sy (abs (- (cadr mx) (cadr mn)))
                                  dg (sqrt (+ (* sx sx) (* sy sy))))
                            (if (< dg maxDiag)
                              (progn
                                (setq hnd (cdr (assoc 5 el)))
                                (if doTouch (set (read (strcat tag "H_" hnd)) T))
                                (setq cands
                                      (cons (list ent
                                                  (car mn) (cadr mn) (car mx) (cadr mx)
                                                  (/ (+ (car mn)  (car mx))  2.0)
                                                  (/ (+ (cadr mn) (cadr mx)) 2.0)
                                                  hnd)
                                            cands))
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
                (setq i (1+ i))
              )

              (setq n (length cands))
              (if (= n 0)
                (princ "\nNo objects in the window matched the examples.")
                (progn
                  (setq finalSS (ssadd))

                  (if (not doCluster)
                    ;; ---------- pure pattern match: take them all ----------
                    (foreach c cands (ssadd (car c) finalSS))

                    ;; ---------- cluster gate (optional) ----------
                    (progn
                      (setq idx 0 usedKeys '())
                      (foreach c cands
                        (set (read (strcat tag "D_" (itoa idx))) c)
                        (set (read (strcat tag "V_" (itoa idx))) nil)
                        (setq ix  (fix (/ (nth 5 c) cell))
                              iy  (fix (/ (nth 6 c) cell))
                              key (strcat tag "B_" (itoa ix) "_" (itoa iy))
                              bsym (read key))
                        (if (not (member key usedKeys))
                          (progn (set bsym nil) (setq usedKeys (cons key usedKeys))))
                        (set bsym (cons idx (eval bsym)))
                        (setq idx (1+ idx))
                      )
                      (setq i 0)
                      (while (< i n)
                        (if (not (eval (read (strcat tag "V_" (itoa i)))))
                          (progn
                            (set (read (strcat tag "V_" (itoa i))) T)
                            (setq kd (eval (read (strcat tag "D_" (itoa i))))
                                  cminx (nth 1 kd) cminy (nth 2 kd)
                                  cmaxx (nth 3 kd) cmaxy (nth 4 kd)
                                  members (list i) stack (list i))
                            (while stack
                              (setq k (car stack) stack (cdr stack)
                                    kd (eval (read (strcat tag "D_" (itoa k))))
                                    kx1 (nth 1 kd) ky1 (nth 2 kd) kx2 (nth 3 kd) ky2 (nth 4 kd)
                                    kcx (nth 5 kd) kcy (nth 6 kd)
                                    ix (fix (/ kcx cell)) iy (fix (/ kcy cell)))
                              (setq gx (1- ix))
                              (while (<= gx (1+ ix))
                                (setq gy (1- iy))
                                (while (<= gy (1+ iy))
                                  (setq bsym (read (strcat tag "B_" (itoa gx) "_" (itoa gy))))
                                  (if (boundp bsym)
                                    (foreach m (eval bsym)
                                      (if (not (eval (read (strcat tag "V_" (itoa m)))))
                                        (progn
                                          (setq md (eval (read (strcat tag "D_" (itoa m))))
                                                mx1 (nth 1 md) my1 (nth 2 md) mx2 (nth 3 md) my2 (nth 4 md))
                                          (if (spk-near kx1 ky1 kx2 ky2 mx1 my1 mx2 my2 connectGap)
                                            (progn
                                              (set (read (strcat tag "V_" (itoa m))) T)
                                              (setq stack (cons m stack) members (cons m members))
                                              (if (< mx1 cminx) (setq cminx mx1))
                                              (if (< my1 cminy) (setq cminy my1))
                                              (if (> mx2 cmaxx) (setq cmaxx mx2))
                                              (if (> my2 cmaxy) (setq cmaxy my2))
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                  (setq gy (1+ gy))
                                )
                                (setq gx (1+ gx))
                              )
                            )
                            (setq cdx (- cmaxx cminx) cdy (- cmaxy cminy)
                                  cdiag (sqrt (+ (* cdx cdx) (* cdy cdy))))
                            (if (<= cdiag clusterMax)
                              (if (or (not doTouch)
                                      (not (spk-anchored cminx cminy cmaxx cmaxy touchGap tag)))
                                (foreach m members
                                  (ssadd (car (eval (read (strcat tag "D_" (itoa m))))) finalSS))
                              )
                            )
                          )
                        )
                        (setq i (1+ i))
                      )
                      ;; cleanup hash symbols
                      (setq i 0)
                      (while (< i n)
                        (set (read (strcat tag "D_" (itoa i))) nil)
                        (set (read (strcat tag "V_" (itoa i))) nil)
                        (setq i (1+ i))
                      )
                      (foreach key usedKeys (set (read key) nil))
                    )
                  )

                  (if doTouch
                    (foreach c cands (set (read (strcat tag "H_" (nth 7 c))) nil)))

                  ;; ============ highlight ============
                  (if (> (sslength finalSS) 0)
                    (progn
                      (sssetfirst nil finalSS)
                      (princ (strcat "\nSelected " (itoa (sslength finalSS))
                                     " speckles matching your examples. Review, then ERASE."))
                    )
                    (princ "\nNothing matched after the gates.")
                  )
                )
              )
            )
            (princ "\nNothing found in the window.")
          )
        )
      )
    )
  )
  (princ)
)

(princ "\nCleanSpeckles loaded. Select example speckles, then type CLEANSPECKLES.")
(princ)
