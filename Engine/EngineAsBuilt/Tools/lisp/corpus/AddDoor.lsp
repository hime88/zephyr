;;; ==========================================================================
;;; COMMAND: IDR (Interior Door - No Number)
;;; ==========================================================================
(defun c:IDR ( / *error* hingePt latchPt swingPt dWidth wAngle sAngle diff dAngle dEndPt doorThick p3 p4 oldOs oldCmd)
  (vl-load-com)

  ;; 1. Store current environmental variables
  (setq oldOs (getvar "OSMODE")
        oldCmd (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  ;; 2. Define Custom Error Handler (Catches "Esc" and failures)
  (defun *error* (msg)
    (if oldOs (setvar "OSMODE" oldOs))
    (if oldCmd (setvar "CMDECHO" oldCmd))
    (princ "\nCommand cancelled. Snap settings restored.")
    (princ)
  )

  ;; 3. Execute Command Logic
  (setvar "OSMODE" 1) ; Snap to Nearest
  (if (setq hingePt (getpoint "\nClick first line for Hinge Point: "))
    (progn
      (setvar "OSMODE" 128) ; Snap to Perpendicular
      (if (setq latchPt (getpoint hingePt "\nClick second line for Latch Point: "))
        (progn
          (setvar "OSMODE" 0) ; Disable snaps
          ;; Get Swing Direction
          (if (setq swingPt (getpoint hingePt "\nClick anywhere on the side the door should swing towards: "))
            (progn
              ;; Vector Math
              (setq dWidth (distance hingePt latchPt)
                    wAngle (angle hingePt latchPt)
                    sAngle (angle hingePt swingPt))

              (setq diff (- sAngle wAngle))
              (while (> diff pi) (setq diff (- diff (* pi 2.0))))
              (while (< diff (- pi)) (setq diff (+ diff (* pi 2.0))))

              (if (> diff 0.0)
                (setq dAngle (+ wAngle (/ pi 2.0))) ; CCW
                (setq dAngle (- wAngle (/ pi 2.0))) ; CW
              )

              (setq dEndPt (polar hingePt dAngle dWidth)
                    doorThick (/ dWidth 24.0)
                    p3 (polar dEndPt wAngle doorThick)
                    p4 (polar hingePt wAngle doorThick))

              ;; Draw Door and Arc
              (command "_.PLINE" "_non" hingePt "_non" dEndPt "_non" p3 "_non" p4 "_C")
              (if (> diff 0.0)
                (command "_.ARC" "_C" "_non" hingePt "_non" latchPt "_non" dEndPt)
                (command "_.ARC" "_C" "_non" hingePt "_non" dEndPt "_non" latchPt)
              )
              (princ "\nQuick Door generated.")
e            )
            (princ "\nError: No swing direction provided.")
          )
        )
        (princ "\nError: Invalid latch point.")
      )
    )
    (princ "\nError: Invalid hinge point.")
  )

  ;; 4. Standard Restore (If command finishes successfully)
  (setvar "OSMODE" oldOs)
  (setvar "CMDECHO" oldCmd)
  (princ)
)

;;; ==========================================================================
;;; COMMAND: IDN (Interior Door with Number)
;;; ==========================================================================
(defun c:IDN ( / *error* entTxt hingePt latchPt swingPt dWidth wAngle sAngle diff dAngle dEndPt doorThick p3 p4 textPt txtAngle oldOs oldCmd)
  (vl-load-com)

  ;; 1. Store current environmental variables
  (setq oldOs (getvar "OSMODE")
        oldCmd (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  ;; 2. Define Custom Error Handler (Catches "Esc" and failures)
  (defun *error* (msg)
    (if oldOs (setvar "OSMODE" oldOs))
    (if oldCmd (setvar "CMDECHO" oldCmd))
    (princ "\nCommand cancelled. Snap settings restored.")
    (princ)
  )

  ;; 3. Execute Command Logic
  (if (setq entTxt (car (entsel "\nSelect door number (Text/MText): ")))
    (progn
      (setvar "OSMODE" 512) ; Snap to Nearest
      (if (setq hingePt (getpoint "\nClick first line for Hinge Point: "))
        (progn
          (setvar "OSMODE" 128) ; Snap to Perpendicular
          (if (setq latchPt (getpoint hingePt "\nClick second line for Latch Point: "))
            (progn
              (setvar "OSMODE" 0) ; Disable snaps
              ;; Get Swing Direction
              (if (setq swingPt (getpoint hingePt "\nClick anywhere on the side the door should swing towards: "))
                (progn
                  ;; Vector Math
                  (setq dWidth (distance hingePt latchPt)
                        wAngle (angle hingePt latchPt)
                        sAngle (angle hingePt swingPt))

                  (setq diff (- sAngle wAngle))
                  (while (> diff pi) (setq diff (- diff (* pi 2.0))))
                  (while (< diff (- pi)) (setq diff (+ diff (* pi 2.0))))

                  (if (> diff 0.0)
                    (progn
                      (setq dAngle (+ wAngle (/ pi 2.0)))
                      (setq diff (/ pi 2.0))
                    )
                    (progn
                      (setq dAngle (- wAngle (/ pi 2.0)))
                      (setq diff (- (/ pi 2.0)))
                    )
                  )

                  (setq dEndPt (polar hingePt dAngle dWidth)
                        doorThick (/ dWidth 18.0)
                        p3 (polar dEndPt wAngle doorThick)
                        p4 (polar hingePt wAngle doorThick))

                  ;; Draw Door and Arc
                  (command "_.PLINE" "_non" hingePt "_non" dEndPt "_non" p3 "_non" p4 "_C")
                  (if (> diff 0.0)
                    (command "_.ARC" "_C" "_non" hingePt "_non" latchPt "_non" dEndPt)
                    (command "_.ARC" "_C" "_non" hingePt "_non" dEndPt "_non" latchPt)
                  )

                  ;; Text Placement Math
                  (setq textPt (polar hingePt (+ wAngle (/ diff 2.0)) (* dWidth 0.6)))
                  (setq txtAngle dAngle)

                  (while (>= txtAngle (* pi 2.0)) (setq txtAngle (- txtAngle (* pi 2.0))))
                  (while (< txtAngle 0.0) (setq txtAngle (+ txtAngle (* pi 2.0))))

                  (if (and (> txtAngle (/ pi 2.0)) (<= txtAngle (* 1.5 pi)))
                    (setq txtAngle (- txtAngle pi))
                  )

                  ;; Execute Text Move/Rotate
                  (command "_.COPY" entTxt "" "_non" (cdr (assoc 10 (entget entTxt))) "_non" textPt)
                  (command "_.ROTATE" "_L" "" "_non" textPt (* 180.0 (/ txtAngle pi)))

                  (princ "\nQuick Door with Number generated.")
                )
                (princ "\nError: No swing direction provided.")
              )
            )
            (princ "\nError: Invalid latch point.")
          )
        )
        (princ "\nError: Invalid hinge point.")
      )
    )
    (princ "\nError: No text selected.")
  )

  ;; 4. Standard Restore (If command finishes successfully)
  (setvar "OSMODE" oldOs)
  (setvar "CMDECHO" oldCmd)
  (princ)
)

;;; ==========================================================================
;;; COMMAND: EDR (Exterior Door - No Number - 180 Degree)
;;; ==========================================================================
(defun c:EDR ( / *error* hingePt latchPt swingPt dWidth wAngle sAngle diff dAngle dEndPt oAngle doorThick p3 p4 oldOs oldCmd)
  (vl-load-com)

  ;; 1. Store current environmental variables
  (setq oldOs (getvar "OSMODE")
        oldCmd (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  ;; 2. Define Custom Error Handler
  (defun *error* (msg)
    (if oldOs (setvar "OSMODE" oldOs))
    (if oldCmd (setvar "CMDECHO" oldCmd))
    (princ "\nCommand cancelled. Snap settings restored.")
    (princ)
  )

  ;; 3. Execute Command Logic
  (setvar "OSMODE" 1) ; Snap to Nearest
  (if (setq hingePt (getpoint "\nClick first line for Hinge Point: "))
    (progn
      (setvar "OSMODE" 128) ; Snap to Perpendicular
      (if (setq latchPt (getpoint hingePt "\nClick second line for Latch Point: "))
        (progn
          (setvar "OSMODE" 0) ; Disable snaps
          ;; Get Swing Direction
          (if (setq swingPt (getpoint hingePt "\nClick anywhere on the side the door should swing towards: "))
            (progn
              ;; Vector Math
              (setq dWidth (distance hingePt latchPt)
                    wAngle (angle hingePt latchPt)
                    sAngle (angle hingePt swingPt))

              (setq diff (- sAngle wAngle))
              (while (> diff pi) (setq diff (- diff (* pi 2.0))))
              (while (< diff (- pi)) (setq diff (+ diff (* pi 2.0))))

              ;; For 180 deg door, it folds completely flat against the wall (opposite the latch)
              (setq dAngle (+ wAngle pi))
              (setq dEndPt (polar hingePt dAngle dWidth))

              ;; Determine offset angle for door thickness (pushing it flush against the wall)
              (if (> diff 0.0)
                (setq oAngle (+ wAngle (/ pi 2.0))) ; Swing Left/CCW
                (setq oAngle (- wAngle (/ pi 2.0))) ; Swing Right/CW
              )

              (setq doorThick (/ dWidth 28.0)
                    p3 (polar dEndPt oAngle doorThick)
                    p4 (polar hingePt oAngle doorThick))

              ;; Draw Door Panel
              (command "_.PLINE" "_non" hingePt "_non" dEndPt "_non" p3 "_non" p4 "_C")

              ;; Draw 180 Degree Arc (Center is always Hinge, Ends are Latch and Open End)
              (if (> diff 0.0)
                (command "_.ARC" "_C" "_non" hingePt "_non" latchPt "_non" dEndPt)
                (command "_.ARC" "_C" "_non" hingePt "_non" dEndPt "_non" latchPt)
              )
              (princ "\nExterior Door generated.")
            )
            (princ "\nError: No swing direction provided.")
          )
        )
        (princ "\nError: Invalid latch point.")
      )
    )
    (princ "\nError: Invalid hinge point.")
  )

  ;; 4. Standard Restore
  (setvar "OSMODE" oldOs)
  (setvar "CMDECHO" oldCmd)
  (princ)
)

;;; ==========================================================================
;;; COMMAND: EDN (Exterior Door with Number - 180 Degree)
;;; ==========================================================================
(defun c:EDN ( / *error* entTxt hingePt latchPt swingPt dWidth wAngle sAngle diff dAngle dEndPt oAngle doorThick p3 p4 textPt txtAngle oldOs oldCmd)
  (vl-load-com)

  ;; 1. Store current environmental variables
  (setq oldOs (getvar "OSMODE")
        oldCmd (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  ;; 2. Define Custom Error Handler
  (defun *error* (msg)
    (if oldOs (setvar "OSMODE" oldOs))
    (if oldCmd (setvar "CMDECHO" oldCmd))
    (princ "\nCommand cancelled. Snap settings restored.")
    (princ)
  )

  ;; 3. Execute Command Logic
  (if (setq entTxt (car (entsel "\nSelect door number (Text/MText): ")))
    (progn
      (setvar "OSMODE" 512) ; Snap to Nearest
      (if (setq hingePt (getpoint "\nClick first line for Hinge Point: "))
        (progn
          (setvar "OSMODE" 128) ; Snap to Perpendicular
          (if (setq latchPt (getpoint hingePt "\nClick second line for Latch Point: "))
            (progn
              (setvar "OSMODE" 0) ; Disable snaps
              ;; Get Swing Direction
              (if (setq swingPt (getpoint hingePt "\nClick anywhere on the side the door should swing towards: "))
                (progn
                  ;; Vector Math
                  (setq dWidth (distance hingePt latchPt)
                        wAngle (angle hingePt latchPt)
                        sAngle (angle hingePt swingPt))

                  (setq diff (- sAngle wAngle))
                  (while (> diff pi) (setq diff (- diff (* pi 2.0))))
                  (while (< diff (- pi)) (setq diff (+ diff (* pi 2.0))))

                  ;; For 180 deg door, it folds completely flat against the wall
                  (setq dAngle (+ wAngle pi))
                  (setq dEndPt (polar hingePt dAngle dWidth))

                  ;; Determine offset angle for door thickness
                  (if (> diff 0.0)
                    (setq oAngle (+ wAngle (/ pi 2.0)))
                    (setq oAngle (- wAngle (/ pi 2.0)))
                  )

                  (setq doorThick (/ dWidth 18.0)
                        p3 (polar dEndPt oAngle doorThick)
                        p4 (polar hingePt oAngle doorThick))

                  ;; Draw Door Panel
                  (command "_.PLINE" "_non" hingePt "_non" dEndPt "_non" p3 "_non" p4 "_C")

                  ;; Draw 180 Degree Arc
                  (if (> diff 0.0)
                    (command "_.ARC" "_C" "_non" hingePt "_non" latchPt "_non" dEndPt)
                    (command "_.ARC" "_C" "_non" hingePt "_non" dEndPt "_non" latchPt)
                  )

                  ;; Text Placement Math (Push straight out into the center of the semi-circle)
                  (setq textPt (polar hingePt oAngle (* dWidth 0.6)))

                  ;; Set text parallel to wall
                  (setq txtAngle wAngle)

                  ;; Normalize angle
                  (while (>= txtAngle (* pi 2.0)) (setq txtAngle (- txtAngle (* pi 2.0))))
                  (while (< txtAngle 0.0) (setq txtAngle (+ txtAngle (* pi 2.0))))

                  ;; Flip to ensure it reads cleanly bottom-to-top or left-to-right
                  (if (and (> txtAngle (/ pi 2.0)) (<= txtAngle (* 1.5 pi)))
                    (setq txtAngle (- txtAngle pi))
                  )

                  ;; Execute Text Move/Rotate
                  (command "_.COPY" entTxt "" "_non" (cdr (assoc 10 (entget entTxt))) "_non" textPt)
                  (command "_.ROTATE" "_L" "" "_non" textPt (* 180.0 (/ txtAngle pi)))

                  (princ "\nExterior Door with Number generated.")
                )
                (princ "\nError: No swing direction provided.")
              )
            )
            (princ "\nError: Invalid latch point.")
          )
        )
        (princ "\nError: Invalid hinge point.")
      )
    )
    (princ "\nError: No text selected.")
  )

  ;; 4. Standard Restore
  (setvar "OSMODE" oldOs)
  (setvar "CMDECHO" oldCmd)
  (princ)
)
