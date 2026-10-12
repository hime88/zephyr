(vl-load-com)

(defun c:SelectByColors ( / exSS i ent el sig colorList pt1 pt2 finalSS filteredSS j candidate candidateEl candidateSig)
  (princ "\nSelect example objects of the colors you want to target...")
  (setq exSS (ssget))

  (if (not exSS)
    (princ "\nNo example objects selected.")
    (progn
      ;; Build a unique list of color signatures from selection
      (setq colorList '() i 0)
      (while (< i (sslength exSS))
        (setq ent (ssname exSS i)
              el  (entget ent))

        ;; Determine color signature (TrueColor, Index Color, or Layer)
        (setq sig (cond
                    ((assoc 420 el) (strcat "T" (itoa (cdr (assoc 420 el))))) ; TrueColor
                    ((assoc 62  el) (strcat "A" (itoa (cdr (assoc 62  el))))) ; Index Color
                    (T              (strcat "L" (cdr (assoc 8 el))))          ; ByLayer Color
                  ))

        (if (not (member sig colorList))
          (setq colorList (cons sig colorList))
        )
        (setq i (1+ i))
      )

      (princ (strcat "\nCaptured " (itoa (length colorList)) " unique color signature(s)."))

      ;; Get the bounding area window from user
      (setq pt1 (getpoint "\nClick first corner of selection window: "))
      (if pt1 (setq pt2 (getcorner pt1 "\nClick opposite corner: ")))

      (if (and pt1 pt2)
        (progn
          ;; Grab everything inside the window
          (setq finalSS (ssget "_C" pt1 pt2)
                filteredSS (ssadd))

          (if finalSS
            (progn
              (setq j 0)
              (while (< j (sslength finalSS))
                (setq candidate   (ssname finalSS j)
                      candidateEl (entget candidate)
                      candidateSig (cond
                                      ((assoc 420 candidateEl) (strcat "T" (itoa (cdr (assoc 420 candidateEl)))))
                                      ((assoc 62  candidateEl) (strcat "A" (itoa (cdr (assoc 62  candidateEl)))))
                                      (T                       (strcat "L" (cdr (assoc 8 candidateEl))))
                                   ))

                ;; If the candidate's color matches any color in our learned list, add it
                (if (member candidateSig colorList)
                  (ssadd candidate filteredSS)
                )
                (setq j (1+ j))
              )

              ;; --- AUTO-SELECT FIX ---
              (if (> (sslength filteredSS) 0)
                (progn
                  ;; Run the SELECT command natively in the background to lock memory
                  (vl-cmdf "_.SELECT" filteredSS "")
                  ;; Force the blue grips to stay on screen
                  (sssetfirst nil filteredSS)
                  (princ (strcat "\nSuccess: Selected " (itoa (sslength filteredSS)) " objects matching target colors."))
                )
                (princ "\nNo matching colored objects found in the window.")
              )
            )
            (princ "\nNo objects found within the specified area.")
          )
        )
      )
    )
  )
  (princ)
)

(defun c:SS () (c:SelectByColors))
(princ "\nType SELECTBYCOLORS or SS to run the routine.")
(princ)
