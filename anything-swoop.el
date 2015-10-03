;;; anything-swoop.el --- Efficiently hopping squeezed lines powered by anything interface -*- coding: utf-8; lexical-binding: t -*-

;; Copyright (C) 2013 by Shingo Fukuyama

;; Version: 1.6.0
;; Author: Shingo Fukuyama - http://fukuyama.co
;; URL: https://github.com/ShingoFukuyama/anything-swoop
;; Created: Oct 24 2013
;; Keywords: anything swoop inner buffer search
;; Package-Requires: ((anything "1.0") (emacs "24"))

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.

;;; Commentary:

;; List the all lines to another buffer, which is able to squeeze
;; by any words you input. At the same time, the original buffer's
;; cursor is jumping line to line according to moving up and down
;; the list.

;; Example config
;; ----------------------------------------------------------------
;; ;; anything from https://github.com/emacs-anything/anything
;; (require 'anything)

;; ;; Locate the anything-swoop folder to your path
;; ;; This line is unnecessary if you get this program from MELPA
;; (add-to-list 'load-path "~/.emacs.d/elisp/anything-swoop")

;; (require 'anything-swoop)

;; ;; Change keybinds to whatever you like :)
;; (global-set-key (kbd "M-i") 'anything-swoop)
;; (global-set-key (kbd "M-I") 'anything-swoop-back-to-last-point)
;; (global-set-key (kbd "C-c M-i") 'anything-multi-swoop)
;; (global-set-key (kbd "C-x M-i") 'anything-multi-swoop-all)

;; ;; When doing isearch, hand the word over to anything-swoop
;; (define-key isearch-mode-map (kbd "M-i") 'anything-swoop-from-isearch)
;; (define-key anything-swoop-map (kbd "M-i") 'anything-multi-swoop-all-from-anything-swoop)

;; ;; Save buffer when anything-multi-swoop-edit complete
;; (setq anything-multi-swoop-edit-save t)

;; ;; If this value is t, split window inside the current window
;; (setq anything-swoop-split-with-multiple-windows nil)

;; ;; Split direction. 'split-window-vertically or 'split-window-horizontally
;; (setq anything-swoop-split-direction 'split-window-vertically)

;; ;; If nil, you can slightly boost invoke speed in exchange for text color
;; (setq anything-swoop-speed-or-color nil)

;; ;; Go to the opposite side of line from the end or beginning of line
;; (setq anything-swoop-move-to-line-cycle t)

;; ;; Optional face for line numbers
;; ;; Face name is `anything-swoop-line-number-face`
;; (setq anything-swoop-use-line-number-face t)

;; ----------------------------------------------------------------

;; * `M-x anything-swoop` when region active
;; * `M-x anything-swoop` when the cursor is at any symbol
;; * `M-x anything-swoop` when the cursor is not at any symbol
;; * `M-3 M-x anything-swoop` or `C-u 5 M-x anything-swoop` multi separated line culling
;; * `M-x anything-multi-swoop` multi-occur like feature
;; * `M-x anything-multi-swoop-all` apply all buffers
;; * `C-u M-x anything-multi-swoop` apply last selected buffers from the second time
;; * `M-x anything-swoop-same-face-at-point` list lines have the same face at the cursor is on
;; * During isearch `M-i` to hand the word over to anything-swoop
;; * During anything-swoop `M-i` to hand the word over to anything-multi-swoop-all
;; * While doing `anything-swoop` press `C-c C-e` to edit mode, apply changes to original buffer by `C-x C-s`

;; Anything Swoop Edit
;; While doing anything-swoop, press keybind [C-c C-e] to move to edit buffer.
;; Edit the list and apply by [C-x C-s]. If you'd like to cancel, [C-c C-g]

;;; Code:

(require 'cl-lib)
(require 'anything)
(require 'anything-match-plugin)

(declare-function migemo-search-pattern-get "migemo")

;;; @ anything-swoop ----------------------------------------------

(defgroup anything-swoop nil
  "Open anything-swoop."
  :prefix "anything-swoop-" :group 'anything)

(defface anything-swoop-target-line-face
  '((t (:background "#e3e300" :foreground "#222222")))
  "Face for anything-swoop target line"
  :group 'anything-swoop)
(defface anything-swoop-target-line-block-face
  '((t (:background "#cccc00" :foreground "#222222")))
  "Face for target line"
  :group 'anything-swoop)
(defface anything-swoop-target-word-face
  '((t (:background "#7700ff" :foreground "#ffffff")))
  "Face for target word"
  :group 'anything-swoop)
(defface anything-swoop-line-number-face
  '((t (:foreground "#999999")))
  "Face for line numbers"
  :group 'anything-swoop)

(defcustom anything-swoop-speed-or-color nil
 "If nil, you can slightly boost invoke speed in exchange for text color"
 :group 'anything-swoop :type 'boolean)
(defcustom anything-swoop-use-line-number-face nil
  "Use face to line numbers on anything-swoop buffer"
  :group 'anything-swoop :type 'boolean)
(defcustom anything-swoop-split-with-multiple-windows nil
 "Split window when having multiple windows open"
 :group 'anything-swoop :type 'boolean)
(defcustom anything-swoop-move-to-line-cycle t
 "Return to the opposite side of line"
 :group 'anything-swoop :type 'boolean)
(defcustom anything-swoop-split-direction 'split-window-vertically
 "Split direction"
 :type '(choice (const :tag "vertically"   split-window-vertically)
                (const :tag "horizontally" split-window-horizontally))
 :group 'anything-swoop)

(defvar anything-swoop-split-window-function
  (lambda ($buf)
   (if anything-swoop-split-with-multiple-windows
       (funcall anything-swoop-split-direction)
       (when (one-window-p)
        (funcall anything-swoop-split-direction)))
    (other-window 1)
    (switch-to-buffer $buf))
  "Change the way to split window only when `anything-swoop' is calling")

(defvar anything-swoop-candidate-number-limit 19999)
(defvar anything-swoop-buffer "*Anything Swoop*")
(defvar anything-swoop-prompt "Swoop: ")
(defvar anything-swoop-last-point nil)
(defvar anything-swoop-invisible-targets nil)
(defvar anything-swoop-last-line-info nil)

;; Buffer local variables
(defvar anything-swoop-cache)
(defvar anything-swoop-list-cache)
(defvar anything-swoop-pattern)            ; Keep anything-pattern value
(defvar anything-swoop-last-query)         ; Last search query for resume
(defvar anything-swoop-last-prefix-number) ; For multiline highlight

;; Global variables
(defvar anything-swoop-synchronizing-window nil
  "Window object where `anything-swoop' called from")
(defvar anything-swoop-target-buffer nil
  "Buffer object where `anything-swoop' called from")
(defvar anything-swoop-line-overlay nil
  "Overlay object to indicate other window's line")

(defvar anything-swoop-map
  (let (($map (make-sparse-keymap)))
    (set-keymap-parent $map anything-map)
    (define-key $map (kbd "C-c C-e") 'anything-swoop-edit)
    (define-key $map (kbd "M-i") 'anything-multi-swoop-all-from-anything-swoop)
    (define-key $map (kbd "C-w") 'anything-swoop-yank-thing-at-point)
    (delq nil $map))
  "Keymap for anything-swoop")

(defvar anything-multi-swoop-map
  (let (($map (make-sparse-keymap)))
    (set-keymap-parent $map anything-map)
    (define-key $map (kbd "C-c C-e") 'anything-multi-swoop-edit)
    (delq nil $map)))

(defcustom anything-swoop-pre-input-function
  (lambda () (thing-at-point 'symbol))
  "This function can pre-input keywords when anything-swoop invoked"
  :group 'anything-swoop :type 'function)

(defun anything-swoop-pre-input-optimize ($query)
  (when $query
    (let (($regexp (list '("\+" . "\\\\+")
                         '("\*" . "\\\\*")
                         '("\#" . "\\\\#"))))
      (mapc (lambda ($r)
              (setq $query (replace-regexp-in-string (car $r) (cdr $r) $query)))
            $regexp)
      $query)))

(defsubst anything-swoop--goto-line ($line)
  (goto-char (point-min))
  (forward-line (1- $line)))

(defsubst anything-swoop--recenter ()
  (recenter (/ (window-height) 2)))

(defsubst anything-swoop--delete-overlay ($identity &optional $beg $end)
  (or $beg (setq $beg (point-min)))
  (or $end (setq $end (point-max)))
  (overlay-recenter $end)
  (mapc (lambda ($o)
          (if (overlay-get $o $identity)
              (delete-overlay $o)))
        (overlays-in $beg $end)))

(defsubst anything-swoop--get-string-at-line ()
  (buffer-substring-no-properties (point-at-bol) (point-at-eol)))

(defsubst anything-swoop--buffer-substring ($point-min $point-max)
  (if anything-swoop-speed-or-color
      (let (($content (buffer-substring $point-min $point-max)))
        (with-temp-buffer
          (let ((inhibit-read-only t))
            (insert $content)
            (remove-text-properties (point-min) (point-max) '(read-only t))
            (setq $content (buffer-substring (point-min) (point-max)))))
        $content)
    (buffer-substring-no-properties $point-min $point-max)))

;;;###autoload
(defun anything-swoop-back-to-last-point (&optional $cancel)
  "Go back to last position where `anything-swoop' was called"
  (interactive)
  (if anything-swoop-last-point
      (let (($po (point)))
        (switch-to-buffer (cdr anything-swoop-last-point))
        (goto-char (car anything-swoop-last-point))
        (unless $cancel
          (setq anything-swoop-last-point
                (cons $po (buffer-name (current-buffer))))))))

(defun anything-swoop--split-lines-by ($string $regexp $step)
  "split-string by $step for multiline"
  (or $step (setq $step 1))
  (let (($from1 0) ;; last match point
        ($from2 0) ;; last substring point
        $list
        ($i 1)) ;; from line 1
    (while (string-match $regexp $string $from1)
      (setq $i (1+ $i))
      (if (eq 0 (% $i $step))
          (progn
            (setq $list (cons (substring $string $from2 (match-beginning 0))
                              $list))
            (setq $from2 (match-end 0))
            (setq $from1 (match-end 0)))
        (setq $from1 (match-end 0))))
    (setq $list (cons (substring $string $from2) $list))
    (nreverse $list)))

(defun anything-swoop--target-line-overlay-move ()
  "Add color to the target line"
  (move-overlay
   anything-swoop-line-overlay
   (progn
     (search-backward
      "\n" nil t (% (line-number-at-pos) anything-swoop-last-prefix-number))
     (goto-char (point-at-bol)))
   ;; For multiline highlight
   (save-excursion
     (goto-char (point-at-bol))
     (or (re-search-forward "\n" nil t anything-swoop-last-prefix-number)
         ;; For the end of buffer error
         (point-max))))
  (anything-swoop--unveil-invisible-overlay))

(defun anything-swoop--validate-regexp (regexp)
  (condition-case nil
      (progn
        (string-match-p regexp "")
        t)
    (invalid-regexp nil)))

(defun anything-swoop--target-word-overlay ($identity &optional $threshold)
  (interactive)
  (or $threshold (setq $threshold 2))
  (save-excursion
    (let (($pat (split-string anything-pattern " "))
          $o)
      (mapc (lambda ($wd)
              (when (and (anything-swoop--validate-regexp $wd) (< $threshold (length $wd)))
                (goto-char (point-min))
                ;; Optional require migemo.el & anything-migemo.el
                (if (and (featurep 'migemo) (featurep 'anything-migemo))
                    (setq $wd (migemo-search-pattern-get $wd)))
                ;; For caret begging match
                (if (string-match "^\\^\\[0\\-9\\]\\+\\.\\(.+\\)" $wd)
                    (setq $wd (concat "^" (match-string 1 $wd))))
                (overlay-recenter (point-max))
                (let (finish)
                  (while (and (not finish) (re-search-forward $wd nil t))
                    (if (= (match-beginning 0) (match-end 0))
                        (forward-char 1)
                      (setq $o (make-overlay (match-beginning 0) (match-end 0)))
                      (overlay-put $o 'face 'anything-swoop-target-word-face)
                      (overlay-put $o $identity t))
                    (when (eobp)
                      (setq finish t))))))
            $pat))))

(defun anything-swoop--restore-unveiled-overlay ()
  (when anything-swoop-invisible-targets
    (mapc (lambda ($ov) (overlay-put (car $ov) 'invisible (cdr $ov)))
          anything-swoop-invisible-targets)
    (setq anything-swoop-invisible-targets nil)))

(defun anything-swoop--unveil-invisible-overlay ()
  "Show hidden text temporarily to view it during anything-swoop.
This function needs to call after latest anything-swoop-line-overlay set."
  (anything-swoop--restore-unveiled-overlay)
  (mapc (lambda ($ov)
          (let (($type (overlay-get $ov 'invisible)))
            (when $type
              (overlay-put $ov 'invisible nil)
              (setq anything-swoop-invisible-targets
                    (cons (cons $ov $type) anything-swoop-invisible-targets)))))
        (overlays-in (overlay-start anything-swoop-line-overlay)
                     (overlay-end anything-swoop-line-overlay))))

;; anything action ------------------------------------------------

(defadvice anything-next-line (around anything-swoop-next-line disable)
  (let ((anything-move-to-line-cycle-in-source t))
    ad-do-it
    (when (called-interactively-p 'any)
      (anything-swoop--move-line-action))))

(defadvice anything-previous-line (around anything-swoop-previous-line disable)
  (let ((anything-move-to-line-cycle-in-source t))
    ad-do-it
    (when (called-interactively-p 'any)
      (anything-swoop--move-line-action))))

(defadvice anything-toggle-visible-mark (around anything-swoop-toggle-visible-mark disable)
  (let ((anything-move-to-line-cycle-in-source t))
    ad-do-it
    (when (called-interactively-p 'any)
      (anything-swoop--move-line-action))))

(defun anything-swoop--move-line-action ()
  (with-anything-window
    (let* (($key (anything-swoop--get-string-at-line))
           ($num (when (string-match "^[0-9]+" $key)
                   (string-to-number (match-string 0 $key)))))
      ;; Synchronizing line position
      (when (and $key $num)
        (with-selected-window anything-swoop-synchronizing-window
          (progn
            (anything-swoop--goto-line $num)
            (with-current-buffer anything-swoop-target-buffer
              (delete-overlay anything-swoop-line-overlay)
              (anything-swoop--target-line-overlay-move))
            (anything-swoop--recenter)))
        (setq anything-swoop-last-line-info
              (cons anything-swoop-target-buffer $num))))))

(defun anything-swoop--nearest-line ($target $list)
  "Return the nearest number of $target out of $list."
  (when (and $target $list)
    (let ($result)
      (cl-labels ((filter ($fn $elem $list)
                          (let ($r)
                            (mapc (lambda ($e)
                                    (if (funcall $fn $elem $e)
                                        (setq $r (cons $e $r))))
                                  $list) $r)))
        (if (eq 1 (length $list))
            (setq $result (car $list))
          (let* (($lts (filter '> $target $list))
                 ($gts (filter '< $target $list))
                 ($lt (if $lts (apply 'max $lts)))
                 ($gt (if $gts (apply 'min $gts)))
                 ($ltg (if $lt (- $target $lt)))
                 ($gtg (if $gt (- $gt $target))))
            (setq $result
                  (cond ((memq $target $list) $target)
                        ((and (not $lt) (not $gt)) nil)
                        ((not $gtg) $lt)
                        ((not $ltg) $gt)
                        ((eq $ltg $gtg) $gt)
                        ((< $ltg $gtg) $lt)
                        ((> $ltg $gtg) $gt)
                        (t 1))))))
      $result)))

(defun anything-swoop--keep-nearest-position ()
  (with-anything-window
    (let (($p (point-min)) $list $bound
          $nearest-line $target-point
          ($buf (rx-to-string (buffer-name (car anything-swoop-last-line-info)) t)))
      (save-excursion
        (goto-char $p)
        (while (if $p (setq $p (re-search-forward (concat "^" $buf "$") nil t)))
          (when (get-text-property (point-at-bol) 'anything-header)
            (forward-char 1)
            (setq $bound (next-single-property-change (point) 'anything-header))
            (while (re-search-forward "^[0-9]+" $bound t)
              (setq $list (cons
                           (string-to-number (match-string 0))
                           $list)))
            (setq $nearest-line (anything-swoop--nearest-line
                            (cdr anything-swoop-last-line-info)
                            $list))
            (goto-char $p)
            (re-search-forward (concat "^"
                                       (number-to-string $nearest-line)
                                       "\\s-") $bound t)
            (setq $target-point (point))
            (setq $p nil))))
      (when $target-point
        (goto-char $target-point)
        (anything-mark-current-line)
        (if (equal anything-swoop-buffer (buffer-name (current-buffer)))
            (anything-swoop--move-line-action)
          (anything-multi-swoop--move-line-action))))))

(defun anything-swoop--pattern-match ()
  "Overlay target words"
  (with-anything-window
    (setq anything-swoop-pattern anything-pattern)
    (when (< 2 (length anything-pattern))
      (anything-swoop--delete-overlay 'target-buffer)
      (anything-swoop--target-word-overlay 'target-buffer)
      (with-selected-window anything-swoop-synchronizing-window
        (anything-swoop--delete-overlay 'target-buffer)
        (anything-swoop--target-word-overlay 'target-buffer)))))

;; core ------------------------------------------------

(defun anything-swoop--get-content (&optional $linum)
  "Get the whole content in buffer and add line number at the head.
If $linum is number, lines are separated by $linum"
  (let (($bufstr (anything-swoop--buffer-substring (point-min) (point-max)))
        $return)
    (with-temp-buffer
      (insert $bufstr)
      (goto-char (point-min))
      (let (($i 1))
        (insert (format "%s " $i))
        (while (re-search-forward "\n" nil t)
          (cl-incf $i)
          (if anything-swoop-use-line-number-face
              (insert (propertize (format "%s" $i) 'font-lock-face 'anything-swoop-line-number-face) " ")
            (insert (format "%s " $i))))
        ;; Delete empty lines
        (unless $linum
          (goto-char (point-min))
          (while (re-search-forward "^[0-9]+\\s-*$" nil t)
            (replace-match ""))))
      (setq $return (anything-swoop--buffer-substring (point-min) (point-max))))
    $return))

(defun anything-c-source-swoop ()
  `((name . ,(buffer-name (current-buffer)))
    (init . (lambda ()
              (unless anything-swoop-cache
                (with-current-buffer (anything-candidate-buffer 'local)
                  (insert ,(anything-swoop--get-content)))
                (setq anything-swoop-cache t))))
    (candidates-in-buffer)
    (get-line . ,(if anything-swoop-speed-or-color
                     'anything-swoop--buffer-substring
                   'buffer-substring-no-properties))
    (keymap . ,anything-swoop-map)
    (header-line . "[C-c C-e] Edit mode, [M-i] apply all buffers")
    (action . (("Go to Line"
                . (lambda ($line)
                    (anything-swoop--goto-line
                     (when (string-match "^[0-9]+" $line)
                       (string-to-number (match-string 0 $line))))
                    (let (($regex (mapconcat 'identity
                                             (split-string anything-pattern " ")
                                             "\\|")))
                      (when (or (and (and (featurep 'migemo) (featurep 'anything-migemo))
                                     (migemo-forward $regex nil t))
                                (re-search-forward $regex nil t))
                        (goto-char (match-beginning 0))))
                    (anything-swoop--recenter)))))
    (migemo) ;;? in exchange for those matches ^ $ [0-9] .*
    ))

(defun anything-c-source-multi-swoop ($buf $func $action)
  `((name . ,$buf)
    (candidates . ,(funcall $func))
    (action . ,$action)
    (header-line . ,(concat $buf "    [C-c C-e] Edit mode"))
    (keymap . ,anything-multi-swoop-map)
    (requires-pattern . 2)
    (migemo)))

(defun anything-c-source-swoop-multiline ($linum)
  `((name . ,(buffer-name (current-buffer)))

    (candidates . ,(if anything-swoop-list-cache
                       (progn
                         (anything-swoop--split-lines-by
                          anything-swoop-list-cache "\n" $linum))
                     (anything-swoop--split-lines-by
                      (setq anything-swoop-list-cache
                            (anything-swoop--get-content t))
                      "\n" $linum)))
    (keymap . ,anything-swoop-map)
    (action . (("Go to Line"
                . (lambda ($line)
                    (anything-swoop--goto-line
                     (when (string-match "^[0-9]+" $line)
                       (string-to-number (match-string 0 $line))))
                    (when (re-search-forward
                           (mapconcat 'identity
                                      (split-string anything-pattern " ") "\\|")
                           nil t)
                      (goto-char (match-beginning 0)))
                    (anything-swoop--recenter)))))
    (multiline)
    (migemo)))

(defun anything-swoop--set-prefix (&optional $multiline)
  ;; Enable scrolling margin
  (if (boundp 'anything-swoop-last-prefix-number)
      (setq anything-swoop-last-prefix-number
            (or $multiline 1)) ;; $multiline is for resume
    (set (make-local-variable 'anything-swoop-last-prefix-number)
         (or $multiline 1))))
(anything-swoop--set-prefix) ;; Silence error "Warning: reference to free variable"

;; Delete cache when modified file is saved
(defun anything-swoop--clear-cache ()
  (if (boundp 'anything-swoop-cache) (setq anything-swoop-cache nil))
  (if (boundp 'anything-swoop-list-cache) (setq anything-swoop-list-cache nil)))
(add-hook 'after-save-hook 'anything-swoop--clear-cache)

(defadvice narrow-to-region (around anything-swoop-advice-narrow-to-region activate)
  (anything-swoop--clear-cache)
  ad-do-it)

(defadvice widen (around anything-swoop-advice-widen activate)
  (anything-swoop--clear-cache)
  ad-do-it)

(defun anything-swoop--restore ()
  (when (= 1 anything-exit-status)
    (anything-swoop-back-to-last-point t)
    (anything-swoop--restore-unveiled-overlay))
  (setq anything-swoop-invisible-targets nil)
  (ad-disable-advice 'anything-next-line 'around 'anything-swoop-next-line)
  (ad-activate 'anything-next-line)
  (ad-disable-advice 'anything-previous-line 'around 'anything-swoop-previous-line)
  (ad-activate 'anything-previous-line)
  (ad-disable-advice 'anything-toggle-visible-mark 'around 'anything-swoop-toggle-visible-mark)
  (ad-activate 'anything-toggle-visible-mark)
  (ad-disable-advice 'anything-move--next-line-fn 'around
                     'anything-multi-swoop-next-line-cycle)
  (ad-activate 'anything-move--next-line-fn)
  (ad-disable-advice 'anything-move--previous-line-fn 'around
                     'anything-multi-swoop-previous-line-cycle)
  (ad-activate 'anything-move--previous-line-fn)
  (remove-hook 'anything-update-hook 'anything-swoop--pattern-match)
  (remove-hook 'anything-after-update-hook 'anything-swoop--keep-nearest-position)
  (setq anything-swoop-last-query anything-swoop-pattern)
  (mapc (lambda ($ov)
          (when (or (eq 'anything-swoop-target-line-face (overlay-get $ov 'face))
                    (eq 'anything-swoop-target-line-block-face
                        (overlay-get $ov 'face)))
            (delete-overlay $ov)))
        (overlays-in (point-min) (point-max)))
  (anything-swoop--delete-overlay 'target-buffer)
  (deactivate-mark t))

;;;###autoload
(cl-defun anything-swoop (&key $query $source ($multiline current-prefix-arg))
  "List the all lines to another buffer, which is able to squeeze by
 any words you input. At the same time, the original buffer's cursor
 is jumping line to line according to moving up and down the list."
  (interactive)
  (setq anything-swoop-synchronizing-window (selected-window))
  (setq anything-swoop-last-point (cons (point) (buffer-name (current-buffer))))
  (setq anything-swoop-last-line-info
        (cons (current-buffer) (line-number-at-pos)))
  (unless (boundp 'anything-swoop-last-query)
    (set (make-local-variable 'anything-swoop-last-query) ""))
  (setq anything-swoop-target-buffer (current-buffer))
  (anything-swoop--set-prefix (prefix-numeric-value $multiline))
  ;; Overlay
  (setq anything-swoop-line-overlay (make-overlay (point) (point)))
  (overlay-put anything-swoop-line-overlay
               'face (if (< 1 anything-swoop-last-prefix-number)
                         'anything-swoop-target-line-block-face
                       'anything-swoop-target-line-face))
  ;; Cache
  (cond ((not (boundp 'anything-swoop-cache))
         ;; first time of a buffer
         (set (make-local-variable 'anything-swoop-cache) nil))
        ((buffer-modified-p)
         (setq anything-swoop-cache nil)))
  ;; Cache for multiline
  (cond ((not (boundp 'anything-swoop-list-cache))
         (set (make-local-variable 'anything-swoop-list-cache) nil))
        ((buffer-modified-p)
         (setq anything-swoop-list-cache nil)))
  (unwind-protect
      (progn
        ;; For synchronizing line position
        (ad-enable-advice 'anything-next-line 'around 'anything-swoop-next-line)
        (ad-activate 'anything-next-line)
        (ad-enable-advice 'anything-previous-line 'around 'anything-swoop-previous-line)
        (ad-activate 'anything-previous-line)
        (ad-enable-advice 'anything-toggle-visible-mark 'around 'anything-swoop-toggle-visible-mark)
        (ad-activate 'anything-toggle-visible-mark)
        (ad-enable-advice 'anything-move--next-line-fn 'around
                          'anything-multi-swoop-next-line-cycle)
        (ad-activate 'anything-move--next-line-fn)
        (ad-enable-advice 'anything-move--previous-line-fn 'around
                          'anything-multi-swoop-previous-line-cycle)
        (ad-activate 'anything-move--previous-line-fn)
        (add-hook 'anything-update-hook 'anything-swoop--pattern-match)
        (add-hook 'anything-after-update-hook 'anything-swoop--keep-nearest-position t)
        (cond ($query
               (if (string-match
                    "\\(\\^\\[0\\-9\\]\\+\\.\\)\\(.*\\)" $query)
                   $query ;; NEED FIX #1 to appear as a "^"
                 $query))
              (mark-active
               (let (($st (buffer-substring-no-properties
                           (region-beginning) (region-end))))
                 (if (string-match "\n" $st)
                     (message "Multi line region is not allowed")
                   (setq $query (anything-swoop-pre-input-optimize $st)))))
              ((setq $query (anything-swoop-pre-input-optimize
                             (funcall anything-swoop-pre-input-function))))
              (t (setq $query "")))
        ;; First behavior
        (anything-swoop--recenter)
        (move-beginning-of-line 1)
        (anything-swoop--target-line-overlay-move)
        ;; Execute anything
        (let ((anything-display-function anything-swoop-split-window-function)
              (anything-display-source-at-screen-top nil)
              (anything-completion-window-scroll-margin 5))
          (anything :sources
                (or $source
                    (if (> anything-swoop-last-prefix-number 1)
                        (anything-c-source-swoop-multiline anything-swoop-last-prefix-number)
                      (anything-c-source-swoop)))
                :buffer anything-swoop-buffer
                :input $query
                :prompt anything-swoop-prompt
                :preselect
                ;; Get current line has content or else near one
                (if (string-match "^[\t\n\s]*$" (anything-swoop--get-string-at-line))
                    (save-excursion
                      (if (re-search-forward "[^\t\n\s]" nil t)
                          (format "^%s\s" (line-number-at-pos))
                        (re-search-backward "[^\t\n\s]" nil t)
                        (format "^%s\s" (line-number-at-pos))))
                  (format "^%s\s" (line-number-at-pos)))
                :candidate-number-limit anything-swoop-candidate-number-limit)))
    ;; Restore anything's hook and window function etc
    (anything-swoop--restore)))

;; Receive word from isearch ---------------
;;;###autoload
(defun anything-swoop-from-isearch ()
  "Invoke `anything-swoop' from isearch."
  (interactive)
  (let (($query (if isearch-regexp
                    isearch-string
                  (regexp-quote isearch-string))))
    (isearch-exit)
    (anything-swoop :$query $query)))
;; When doing isearch, hand the word over to anything-swoop
(define-key isearch-mode-map (kbd "M-i") 'anything-swoop-from-isearch)

;; Receive word from evil search ---------------
(defun anything-swoop-from-evil-search ()
  "Invoke `anything-swoop' from evil isearch"
  (interactive)
  (if (string-match "\\(isearch-\\|evil.*search\\)" (symbol-name real-last-command))
      (anything-swoop :$query (if isearch-regexp
                              isearch-string
                            (regexp-quote isearch-string)))
    (anything-swoop)))
;; When doing evil-search, hand the word over to anything-swoop
;; (define-key evil-motion-state-map (kbd "M-i") 'anything-swoop-from-evil-search)

;; Receive word from evil search ---------------
(defun anything-swoop-yank-thing-at-point ()
  "Insert string at which the point anything-swoop started."
  (interactive)
  (let ($amend)
    (with-selected-window anything-swoop-synchronizing-window
      (with-current-buffer (get-buffer (cdr anything-swoop-last-point))
        (save-excursion
          (goto-char (car anything-swoop-last-point))
          (setq $amend (thing-at-point 'symbol)))))
    (when $amend
      (with-selected-window (minibuffer-window)
        (insert $amend)))))

;; For anything-resume ------------------------
(defadvice anything-resume-select-buffer
  (around anything-swoop-if-selected-as-resume activate)
  "Resume if *Anything Swoop* buffer selected as a resume
 when anything-resume with prefix"
  (if (boundp 'anything-swoop-last-query)
      ad-do-it
    ;; If the buffer hasn't called anything-swoop, just hide from options
    (let ((anything-buffers (delete anything-swoop-buffer anything-buffers)))
      ad-do-it))
  (when (and (equal ad-return-value anything-swoop-buffer)
             (boundp 'anything-swoop-last-query))
    (anything-swoop :$query anything-swoop-last-query
                :$multiline anything-swoop-last-prefix-number)
    (setq ad-return-value nil)))

(defadvice anything-resume (around anything-swoop-resume activate)
  "Resume if the last used anything buffer is anything-swoop-buffer"
  (if (equal anything-last-buffer anything-swoop-buffer)
      (if (boundp 'anything-swoop-last-query)
          (if (not (ad-get-arg 0))
              (anything-swoop :$query anything-swoop-last-query
                          :$multiline anything-swoop-last-prefix-number))
        ;; Temporary apply second last buffer
        (let ((anything-last-buffer (cadr anything-buffers))) ad-do-it))
    ad-do-it))

;; For caret beginning-match -----------------------------
(defun anything-swoop--caret-match-delete ($o $aft $beg $end &optional $len)
  (if $aft
      (- $end $beg $len) ;; Unused argument? To avoid byte compile error
    (delete-region (overlay-start $o) (1- (overlay-end $o)))))

(defun anything-swoop-caret-match (&optional _$resume)
  (interactive)
  (let* (($prompt anything-swoop-prompt) ;; Accept change of the variable
         ($line-number-regexp "^[0-9]+.")
         ($prompt-regexp
          (funcall `(lambda ()
                      (rx bol ,$prompt))))
         ($prompt-regexp-with-line-number
          (funcall `(lambda ()
                      (rx bol ,$prompt (group ,$line-number-regexp)))))
         ($disguise-caret
          (lambda ()
            (save-excursion
              (re-search-backward $prompt-regexp-with-line-number nil t)
              (let (($o (make-overlay (match-beginning 1) (match-end 1))))
                (overlay-put $o 'face 'anything-swoop-target-word-face)
                (overlay-put $o 'modification-hooks '(anything-swoop--caret-match-delete))
                (overlay-put $o 'display "^")
                (overlay-put $o 'evaporate t))))))
    (if (and (minibufferp)
             (string-match $prompt-regexp
                           (buffer-substring-no-properties
                            (point-min) (point-max)))
             (eq (point) (+ 1 (length anything-swoop-prompt))))
        (progn
          (insert $line-number-regexp)
          (funcall $disguise-caret))
      (insert "^"))))

(unless (featurep 'anything-migemo)
  (define-key anything-map (kbd "^") 'anything-swoop-caret-match))

;;; @ anything-swoop-edit -----------------------------------------

(defvar anything-swoop-edit-target-buffer)
(defvar anything-swoop-edit-buffer "*Anything Swoop Edit*")
(defvar anything-swoop-edit-map
  (let (($map (make-sparse-keymap)))
    (define-key $map (kbd "C-x C-s") 'anything-swoop--edit-complete)
    (define-key $map (kbd "C-c C-g") 'anything-swoop--edit-cancel)
    $map))

(defun anything-swoop--clear-edit-buffer ($prop)
  (let ((inhibit-read-only t))
    (mapc (lambda ($ov)
            (when (overlay-get $ov $prop)
              (delete-overlay $ov)))
          (overlays-in (point-min) (point-max)))
    (set-text-properties (point-min) (point-max) nil)
    (goto-char (point-min))
    (erase-buffer)))

(defun anything-swoop--collect-edited-lines ()
  "Create a list of edited lines with each its own line number"
  (interactive)
  (let ($list)
    (goto-char (point-min))
    (while (re-search-forward "^\\([0-9]+\\)\s" nil t)
      (setq $list
            (cons (cons (string-to-number (match-string 1))
                        (buffer-substring-no-properties
                         (point)
                         (save-excursion
                           (if (re-search-forward
                                "^\\([0-9]+\\)\s\\|^\\(\\-+\\)" nil t)
                               (1- (match-beginning 0))
                             (goto-char (point-max))
                             (re-search-backward "\n" nil t)))))
                  $list)))
    $list))

(defun anything-swoop--edit ($candidate &rest _$ignored)
  "This function will only be called from `anything-swoop-edit'"
  (interactive)
  (setq anything-swoop-edit-target-buffer anything-swoop-target-buffer)
  (delete-overlay anything-swoop-line-overlay)
  (anything-swoop--delete-overlay 'target-buffer)
  (with-current-buffer (get-buffer-create anything-swoop-edit-buffer)

    (anything-swoop--clear-edit-buffer 'anything-swoop-edit)
    (let (($bufstr ""))
      ;; Get target line number to edit
      (with-current-buffer anything-swoop-buffer
        ;; Use selected line by [C-SPC] or [M-SPC]
        (mapc (lambda ($ov)
                (when (eq 'anything-visible-mark (overlay-get $ov 'face))
                  (setq $bufstr (concat (buffer-substring-no-properties
                                         (overlay-start $ov) (overlay-end $ov))
                                        $bufstr))))
              (overlays-in (point-min) (point-max)))
        (if (equal "" $bufstr)
            ;; Not found selected line
            (setq $bufstr (buffer-substring-no-properties
                           (point-min) (point-max)))
          ;; Attach title
          (setq $bufstr (concat "Anything Swoop\n" $bufstr))))

      ;; Set for edit buffer
      (insert $bufstr)
      (add-text-properties (point-min) (point-max)
                           '(read-only t rear-nonsticky t front-sticky t))

      ;; Set for editable context
      (let ((inhibit-read-only t))
        ;; Title and explanation
        (goto-char (point-min))
        (let (($o (make-overlay (point) (point-at-eol))))
          (overlay-put $o 'anything-swoop-edit t)
          (overlay-put $o 'face 'font-lock-function-name-face)
          (overlay-put $o 'after-string
                       (propertize " [C-x C-s] Complete, [C-c C-g] Cancel"
                                   'face 'anything-bookmark-addressbook)))
        ;; Line number and editable area
        (while (re-search-forward "^\\([0-9]+\s\\)\\(.*\\)$" nil t)
          (let* (($bol1 (match-beginning 1))
                 ($eol1 (match-end 1))
                 ($bol2 (match-beginning 2))
                 ($eol2 (match-end 2)))
            ;; Line number
            (add-text-properties $bol1 $eol1
                                 '(face font-lock-function-name-face
                                   intangible t))
            ;; Editable area
            (remove-text-properties $bol2 $eol2 '(read-only t))
            ;; For line tail
            (set-text-properties $eol2 (or (1+ $eol2) (point-max))
                                 '(read-only t rear-nonsticky t))))
        (anything-swoop--target-word-overlay 'edit-buffer 0))))

  (other-window 1)
  (switch-to-buffer anything-swoop-edit-buffer)
  (goto-char (point-min))
  (if (string-match "^[0-9]+" $candidate)
      (re-search-forward
       (concat "^" (match-string 0 $candidate)) nil t))
  (use-local-map anything-swoop-edit-map))

(defun anything-swoop--edit-complete ()
  "Apply changes and kill temporary edit buffer"
  (interactive)
  (let (($list (anything-swoop--collect-edited-lines)))
    (with-current-buffer anything-swoop-edit-target-buffer
      ;; Replace from the end of buffer
      (save-excursion
      (cl-loop for ($k . $v) in $list
            do (progn
                 (goto-char (point-min))
                 (delete-region (point-at-bol $k) (point-at-eol $k))
                 (goto-char (point-at-bol $k))
                 (insert $v)))))
    (select-window anything-swoop-synchronizing-window)
    (kill-buffer (get-buffer anything-swoop-edit-buffer)))
  (message "Successfully anything-swoop-edit applied to original buffer"))

(defun anything-swoop--edit-cancel ()
  "Cancel edit and kill temporary buffer"
  (interactive)
  (select-window anything-swoop-synchronizing-window)
  (kill-buffer (get-buffer anything-swoop-edit-buffer))
  (message "anything-swoop-edit canceled"))

(defun anything-swoop-edit ()
  (interactive)
  (anything-swoop-exit-and-execute-action 'anything-swoop--edit))

(defun anything-swoop-exit-and-execute-action (action)
  (setq anything-saved-action action)
  (setq anything-saved-selection (anything-get-selection))
  (anything-exit-minibuffer))

;;; @ anything-multi-swoop ----------------------------------------
(defvar anything-multi-swoop-buffer-list "*anything-multi-swoop buffers list*"
  "Buffer name")
(defvar anything-multi-swoop-ignore-buffers-match "^\\*"
  "Regexp to eliminate buffers you don't want to see")
(defvar anything-multi-swoop-candidate-number-limit 250)
(defvar anything-multi-swoop-last-selected-buffers nil)
(defvar anything-multi-swoop-last-query nil)
(defvar anything-multi-swoop-query nil)
(defvar anything-multi-swoop-buffer "*Anything Multi Swoop*")
(defvar anything-multi-swoop-all-from-anything-swoop-last-point nil
  "For the last position, when anything-multi-swoop-all-from-anything-swoop canceled")
(defvar anything-multi-swoop-move-line-action-last-buffer nil)

(defvar anything-multi-swoop-buffers-map
  (let (($map (make-sparse-keymap)))
    (set-keymap-parent $map anything-map)
    (define-key $map (kbd "RET")
      (lambda () (interactive)
        (anything-swoop-exit-and-execute-action 'anything-multi-swoop--exec)))
    (delq nil $map)))

;; action -----------------------------------------------------

(defadvice anything-next-line (around anything-multi-swoop-next-line disable)
  (let ((anything-move-to-line-cycle-in-source nil))
    ad-do-it
    (when (called-interactively-p 'any)
      (anything-multi-swoop--move-line-action))))

(defadvice anything-previous-line (around anything-multi-swoop-previous-line disable)
  (let ((anything-move-to-line-cycle-in-source nil))
    ad-do-it
    (when (called-interactively-p 'any)
      (anything-multi-swoop--move-line-action))))

(defadvice anything-toggle-visible-mark (around anything-multi-swoop-toggle-visible-mark disable)
  (let ((anything-move-to-line-cycle-in-source nil))
    ad-do-it
    (when (called-interactively-p 'any)
      (anything-multi-swoop--move-line-action))))

(defadvice anything-move--next-line-fn (around anything-multi-swoop-next-line-cycle disable)
  (if (not (anything-pos-multiline-p))
      (if (eq (point-max) (save-excursion (forward-line 1) (point)))
          (when anything-swoop-move-to-line-cycle
            (anything-beginning-of-buffer)
            (anything-swoop--recenter))
        (forward-line 1))
    (let ((line-num (line-number-at-pos)))
      (anything-move--next-multi-line-fn)
      (when (and anything-swoop-move-to-line-cycle
                 (eq line-num (line-number-at-pos)))
        (anything-beginning-of-buffer)))))

(defadvice anything-move--previous-line-fn (around anything-multi-swoop-previous-line-cycle disable)
  (if (not (anything-pos-multiline-p))
      (forward-line -1)
    (anything-move--previous-multi-line-fn))
  (when (and (anything-pos-header-line-p)
             (eq (point) (save-excursion (forward-line -1) (point))))
    (when anything-swoop-move-to-line-cycle
      (anything-end-of-buffer))
    (when (anything-pos-multiline-p)
      (anything-move--previous-multi-line-fn))))

(defun anything-multi-swoop--overlay-move (&optional $buf)
  (move-overlay
   anything-swoop-line-overlay
   (goto-char (point-at-bol))
   (save-excursion
     (goto-char (point-at-bol))
     (or (re-search-forward "\n" nil t) (point-max)))
   $buf)
  (anything-swoop--unveil-invisible-overlay))

(defun anything-multi-swoop--move-line-action ()
  (with-anything-window
    (let* (($key (buffer-substring (point-at-bol) (point-at-eol)))
           ($num (when (string-match "^[0-9]+" $key)
                   (string-to-number (match-string 0 $key))))
           ($source (anything-get-current-source))
           ($buf (get-buffer (assoc-default 'name $source))))
      ;; Synchronizing line position
      (with-selected-window anything-swoop-synchronizing-window
        (with-current-buffer $buf
          (when (not (eq $buf anything-multi-swoop-move-line-action-last-buffer))
            (set-window-buffer nil $buf)
            (anything-swoop--pattern-match))
          (anything-swoop--goto-line $num)
          (anything-multi-swoop--overlay-move $buf)
          (anything-swoop--recenter))
        (setq anything-multi-swoop-move-line-action-last-buffer $buf))
      (setq anything-swoop-last-line-info (cons $buf $num)))))

(defun anything-multi-swoop--get-marked-buffers ()
  (let ($list)
    (with-current-buffer anything-multi-swoop-buffer-list
      (mapc (lambda ($ov)
              (when (eq 'anything-visible-mark (overlay-get $ov 'face))
                (setq $list (cons
                             (let (($word (buffer-substring-no-properties
                                           (overlay-start $ov) (overlay-end $ov))))
                               (mapc (lambda ($r)
                                       (setq $word (replace-regexp-in-string
                                                    (car $r) (cdr $r) $word)))
                                     (list '("\\`[ \t\n\r]+" . "")
                                           '("[ \t\n\r]+\\'" . "")))
                               $word)
                             $list))))
            (overlays-in (point-min) (point-max))))
    (delete "" $list)))

;; core --------------------------------------------------------

(cl-defun anything-multi-swoop--exec (ignored &key $query $buflist $func $action)
  (interactive)
  (setq anything-swoop-synchronizing-window (selected-window))
  (setq anything-swoop-last-point
        (or anything-multi-swoop-all-from-anything-swoop-last-point
            (cons (point) (buffer-name (current-buffer)))))
  (setq anything-swoop-last-line-info
        (cons (current-buffer) (line-number-at-pos)))
  (let (($buffs (or $buflist (anything-multi-swoop--get-marked-buffers)
                    (error "No buffer selected")))
        $contents
        $preserve-position)
    (setq anything-multi-swoop-last-selected-buffers $buffs)
    ;; Create buffer sources
    (mapc (lambda ($buf)
            (with-current-buffer $buf
              (let* (($func
                      (or $func
                          (lambda () (split-string (anything-swoop--get-content) "\n"))))
                     ($action
                      (or $action
                          `(("Go to Line"
                             . (lambda ($line)
                                 (switch-to-buffer ,$buf)
                                 (anything-swoop--goto-line
                                  (when (string-match "^[0-9]+" $line)
                                    (string-to-number
                                     (match-string 0 $line))))
                                 (when (re-search-forward
                                        (mapconcat 'identity
                                                   (split-string
                                                    anything-pattern " ") "\\|")
                                        nil t)
                                   (goto-char (match-beginning 0)))
                                 (anything-swoop--recenter)))))))
                (setq $preserve-position
                      (cons (cons $buf (point)) $preserve-position))
                (setq
                 $contents
                 (cons
                  (anything-c-source-multi-swoop $buf $func $action)
                  $contents)))))
          $buffs)
    (unwind-protect
        (progn
          (ad-enable-advice 'anything-next-line 'around
                            'anything-multi-swoop-next-line)
          (ad-activate 'anything-next-line)
          (ad-enable-advice 'anything-previous-line 'around
                            'anything-multi-swoop-previous-line)
          (ad-activate 'anything-previous-line)
          (ad-enable-advice 'anything-toggle-visible-mark 'around
                            'anything-multi-swoop-toggle-visible-mark)
          (ad-activate 'anything-toggle-visible-mark)
          (ad-enable-advice 'anything-move--next-line-fn 'around
                            'anything-multi-swoop-next-line-cycle)
          (ad-activate 'anything-move--next-line-fn)
          (ad-enable-advice 'anything-move--previous-line-fn 'around
                            'anything-multi-swoop-previous-line-cycle)
          (ad-activate 'anything-move--previous-line-fn)
          (add-hook 'anything-update-hook 'anything-swoop--pattern-match)
          (add-hook 'anything-after-update-hook 'anything-swoop--keep-nearest-position t)
          (setq anything-swoop-line-overlay
                (make-overlay (point) (point)))
          (overlay-put anything-swoop-line-overlay
                       'face 'anything-swoop-target-line-face)
          (anything-multi-swoop--overlay-move)
          ;; Execute anything
          (let ((anything-display-function anything-swoop-split-window-function)
                (anything-display-source-at-screen-top nil)
                (anything-completion-window-scroll-margin 5))
            (anything :sources $contents
                  :buffer anything-multi-swoop-buffer
                  :input (or $query anything-multi-swoop-query "")
                  :prompt anything-swoop-prompt
                  :candidate-number-limit
                  anything-multi-swoop-candidate-number-limit
                  :preselect
                  (format "%s %s" (line-number-at-pos)
                          (anything-swoop--get-string-at-line)))))
      ;; Restore
      (progn
        (when (= 1 anything-exit-status)
          (anything-swoop-back-to-last-point t)
          (anything-swoop--restore-unveiled-overlay))
        (setq anything-swoop-invisible-targets nil)
        (ad-disable-advice 'anything-next-line 'around
                           'anything-multi-swoop-next-line)
        (ad-activate 'anything-next-line)
        (ad-disable-advice 'anything-previous-line 'around
                           'anything-multi-swoop-previous-line)
        (ad-activate 'anything-previous-line)
        (ad-disable-advice 'anything-toggle-visible-mark 'around
                           'anything-multi-swoop-toggle-visible-mark)
        (ad-activate 'anything-toggle-visible-mark)
        (ad-disable-advice 'anything-move--next-line-fn 'around
                           'anything-multi-swoop-next-line-cycle)
        (ad-activate 'anything-move--next-line-fn)
        (ad-disable-advice 'anything-move--previous-line-fn 'around
                           'anything-multi-swoop-previous-line-cycle)
        (ad-activate 'anything-move--previous-line-fn)
        (remove-hook 'anything-update-hook 'anything-swoop--pattern-match)
        (remove-hook 'anything-after-update-hook 'anything-swoop--keep-nearest-position)
        (setq anything-multi-swoop-last-query anything-swoop-pattern)
        (anything-swoop--restore-unveiled-overlay)
        (setq anything-multi-swoop-query nil)
        (setq anything-multi-swoop-all-from-anything-swoop-last-point nil)
        (mapc (lambda ($buf)
                (let (($current-buffer (buffer-name (current-buffer))))
                  (with-current-buffer (car $buf)
                    ;; Delete overlay
                    (delete-overlay anything-swoop-line-overlay)
                    (anything-swoop--delete-overlay 'target-buffer)
                    ;; Restore each buffer's position
                    (unless (equal (car $buf) $current-buffer)
                      (goto-char (cdr $buf))))))
              $preserve-position)))))

(defun anything-multi-swoop--get-buffer-list ()
  (let ($buflist1 $buflist2)
    ;; eliminate buffers start with whitespace and dired buffers
    (mapc (lambda ($buf)
            (setq $buf (buffer-name $buf))
            (unless (string-match "^\\s-" $buf)
              (unless (eq 'dired-mode (with-current-buffer $buf major-mode))
                (setq $buflist1 (cons $buf $buflist1)))))
          (buffer-list))
    ;; eliminate buffers match pattern
    (mapc (lambda ($buf)
            (unless (string-match
                     anything-multi-swoop-ignore-buffers-match
                     $buf)
              (setq $buflist2 (cons $buf $buflist2))))
          $buflist1)
    $buflist2))

(defun anything-c-source-anything-multi-swoop-buffers ()
  "Show buffer list to select"
  `((name . "anything-multi-swoop select buffers")
    (candidates . anything-multi-swoop--get-buffer-list)
    (header-line . "[C-SPC]/[M-SPC] select, [RET] next step")
    (keymap . ,anything-multi-swoop-buffers-map)))

;;;###autoload
(defun anything-multi-swoop (&optional $query $buflist)
  "\
Usage:
M-x anything-multi-swoop
1. Select any buffers by [C-SPC] or [M-SPC]
2. Press [RET] to start anything-multi-swoop

C-u M-x anything-multi-swoop
If you have done anything-multi-swoop before, you can skip select buffers step.
Last selected buffers will be applied to anything-multi-swoop.
"
  (interactive)
  (cond ($query
         (setq anything-multi-swoop-query $query))
        (mark-active
         (let (($st (buffer-substring-no-properties
                     (region-beginning) (region-end))))
           (if (string-match "\n" $st)
               (message "Multi line region is not allowed")
             (setq anything-multi-swoop-query
                   (anything-swoop-pre-input-optimize $st)))))
        ((setq anything-multi-swoop-query
               (anything-swoop-pre-input-optimize
                (funcall anything-swoop-pre-input-function))))
        (t (setq anything-multi-swoop-query "")))
  (if (equal current-prefix-arg '(4))
      (anything-multi-swoop--exec nil
                              :$query anything-multi-swoop-query
                              :$buflist $buflist)
    (if $buflist
        (anything-multi-swoop--exec nil
                                :$query $query
                                :$buflist $buflist)
      (anything :sources (anything-c-source-anything-multi-swoop-buffers)
            :buffer anything-multi-swoop-buffer-list
            :prompt "Mark any buffers by [C-SPC] or [M-SPC]: "))))

;;;###autoload
(defun anything-multi-swoop-all (&optional $query)
  "Apply all buffers to anything-multi-swoop"
  (interactive)
  (cond ($query
         (setq anything-multi-swoop-query $query))
        (mark-active
         (let (($st (buffer-substring-no-properties
                     (region-beginning) (region-end))))
           (if (string-match "\n" $st)
               (message "Multi line region is not allowed")
             (setq anything-multi-swoop-query
                   (anything-swoop-pre-input-optimize $st)))))
        ((setq anything-multi-swoop-query
               (anything-swoop-pre-input-optimize
                (funcall anything-swoop-pre-input-function))))
        (t (setq anything-multi-swoop-query "")))
  (anything-multi-swoop--exec nil
                          :$query anything-multi-swoop-query
                          :$buflist (anything-multi-swoop--get-buffer-list)))

(defun get-buffers-matching-mode ($mode)
  "Returns a list of buffers where their major-mode is equal to MODE"
  (let ($buffer-mode-matches)
    (mapc (lambda ($buffer)
            (with-current-buffer $buffer
              (if (eq $mode major-mode)
                  (add-to-list '$buffer-mode-matches (buffer-name $buffer)))))
          (buffer-list))
    $buffer-mode-matches))

(defun anything-multi-swoop-by-mode ($mode &optional $query)
  "Apply all buffers whose mode is MODE to anything-multi-swoop"
  (cond ($query
         (setq anything-multi-swoop-query $query))
        (mark-active
         (let (($st (buffer-substring-no-properties
                     (region-beginning) (region-end))))
           (if (string-match "\n" $st)
               (message "Multi line region is not allowed")
             (setq anything-multi-swoop-query
                   (anything-swoop-pre-input-optimize $st)))))
        ((setq anything-multi-swoop-query
               (anything-swoop-pre-input-optimize
                (funcall anything-swoop-pre-input-function))))
        (t (setq anything-multi-swoop-query "")))
  (if (get-buffers-matching-mode $mode)
      (anything-multi-swoop--exec nil
                              :$query anything-multi-swoop-query
                              :$buflist (get-buffers-matching-mode $mode))
    (message "there are no buffers in that mode right now")))

;;;###autoload
(defun anything-multi-swoop-org (&optional $query)
  "Applies all org-mode buffers to anything-multi-swoop"
  (interactive)
  (anything-multi-swoop-by-mode 'org-mode $query))

;;;###autoload
(defun anything-multi-swoop-current-mode (&optional $query)
  "Applies all buffers of the same mode as the current buffer to anything-multi-swoop"
  (interactive)
  (anything-multi-swoop-by-mode major-mode $query))


;; option -------------------------------------------------------

(defun anything-multi-swoop-all-from-isearch ()
  "Invoke `anything-multi-swoop-all' from isearch."
  (interactive)
  (let (($query (if isearch-regexp
                    isearch-string
                  (regexp-quote isearch-string))))
    (isearch-exit)
    (anything-multi-swoop-all $query)))
;; When doing isearch, hand the word over to anything-swoop
;; (define-key isearch-mode-map (kbd "C-x M-i") 'anything-multi-swoop-all-from-isearch)

(defun anything-multi-swoop-all-from-anything-swoop ()
  "Invoke `anything-multi-swoop-all' from anything-swoop."
  (interactive)
  (anything-swoop--restore)
  (delete-overlay anything-swoop-line-overlay)
  (setq anything-multi-swoop-all-from-anything-swoop-last-point anything-swoop-last-point)
  (let (($query anything-pattern))
    (run-with-timer 0 nil (lambda () (anything-multi-swoop-all $query))))
  (anything-exit-minibuffer))

(defun anything-multi-swoop-current-mode-from-anything-swoop ()
  "Invoke `anything-multi-swoop-all' from anything-swoop."
  (interactive)
  (anything-swoop--restore)
  (delete-overlay anything-swoop-line-overlay)
  (setq anything-multi-swoop-all-from-anything-swoop-last-point anything-swoop-last-point)
  (let (($query anything-pattern))
    (run-with-timer 0 nil (lambda () (anything-multi-swoop-current-mode $query))))
  (anything-exit-minibuffer))
;; (define-key anything-swoop-map (kbd "M-m") 'anything-multi-swoop-current-mode-from-anything-swoop)

(defadvice anything-resume (around anything-multi-swoop-resume activate)
  "Resume if the last used anything buffer is *Anything Swoop*"
  (if (equal anything-last-buffer anything-multi-swoop-buffer)

      (if (boundp 'anything-multi-swoop-last-query)
          (if (not (ad-get-arg 0))
              (anything-multi-swoop anything-multi-swoop-last-query
                                anything-multi-swoop-last-selected-buffers))
        ;; Temporary apply second last buffer
        (let ((anything-last-buffer (cadr anything-buffers))) ad-do-it))
    ad-do-it))

;;; @ anything-multi-swoop-edit -----------------------------------
(defvar anything-multi-swoop-edit-save t
  "Save each buffer you edit when editing is complete")
(defvar anything-multi-swoop-edit-buffer "*Anything Multi Swoop Edit*")

(defvar anything-multi-swoop-edit-map
  (let (($map (make-sparse-keymap)))
    (define-key $map (kbd "C-x C-s") 'anything-multi-swoop--edit-complete)
    (define-key $map (kbd "C-c C-g") 'anything-multi-swoop--edit-cancel)
    $map))

(defun anything-multi-swoop--edit ($candidate)
  "This function will only be called from `anything-swoop-edit'"
  (interactive)
  (delete-overlay anything-swoop-line-overlay)
  (anything-swoop--delete-overlay 'target-buffer)
  (with-current-buffer (get-buffer-create anything-multi-swoop-edit-buffer)
    (anything-swoop--clear-edit-buffer 'anything-multi-swoop-edit)
    (let (($bufstr "") ($mark nil))
      ;; Get target line number to edit
      (with-current-buffer anything-multi-swoop-buffer
        ;; Set overlay to anything-source-header for editing marked lines
        (save-excursion
          (goto-char (point-min))
          (let (($beg (point)) $end)
            (overlay-recenter (point-max))
            (while (setq $beg (text-property-any $beg (point-max)
                                              'face 'anything-source-header))
              (setq $end (next-single-property-change $beg 'face))
              (overlay-put (make-overlay $beg $end) 'source-header t)
              (setq $beg $end)
              (goto-char $end))))
        ;; Use selected line by [C-SPC] or [M-SPC]
        (mapc (lambda ($ov)
                (when (overlay-get $ov 'source-header)
                  (setq $bufstr (concat (buffer-substring
                                         (overlay-start $ov) (overlay-end $ov))
                                        $bufstr)))
                (when (eq 'anything-visible-mark (overlay-get $ov 'face))
                  (let (($str (buffer-substring (overlay-start $ov) (overlay-end $ov))))
                    (unless (equal "" $str) (setq $mark t))
                    (setq $bufstr (concat (buffer-substring
                                           (overlay-start $ov) (overlay-end $ov))
                                          $bufstr)))))
              (overlays-in (point-min) (point-max)))
        (if $mark
            (progn (setq $bufstr (concat "Anything Multi Swoop\n" $bufstr))
                   (setq $mark nil))
          (setq $bufstr (concat "Anything Multi Swoop\n"
                                (buffer-substring
                                 (point-min) (point-max))))))

      ;; Set for edit buffer
      (insert $bufstr)
      (add-text-properties (point-min) (point-max)
                           '(read-only t rear-nonsticky t front-sticky t))

      ;; Set for editable context
      (let ((inhibit-read-only t))
        ;; Title and explanation
        (goto-char (point-min))
        (let (($o (make-overlay (point) (point-at-eol))))
          (overlay-put $o 'anything-multi-swoop-edit t)
          (overlay-put $o 'face 'font-lock-function-name-face)
          (overlay-put $o 'after-string
                       (propertize " [C-x C-s] Complete, [C-c C-g] Cancel"
                                   'face 'anything-bookmark-addressbook)))
        ;; Line number and editable area
        (while (re-search-forward "^\\([0-9]+\s\\)\\(.*\\)$" nil t)
          (let* (($bol1 (match-beginning 1))
                 ($eol1 (match-end 1))
                 ($bol2 (match-beginning 2))
                 ($eol2 (match-end 2)))

            ;; Line number
            (add-text-properties $bol1 $eol1
                                 '(face font-lock-function-name-face
                                   intangible t))
            ;; Editable area
            (remove-text-properties $bol2 $eol2 '(read-only t))
            ;; (add-text-properties $bol2 $eol2 '(font-lock-face anything-match))

            ;; For line tail
            (set-text-properties $eol2 (or (1+ $eol2) (point-max))
                                 '(read-only t rear-nonsticky t))))
        (anything-swoop--target-word-overlay 'edit-buffer 0))))

  (other-window 1)
  (switch-to-buffer anything-multi-swoop-edit-buffer)
  (goto-char (point-min))
  (if (string-match "^[0-9]+" $candidate)
      (re-search-forward
       (concat "^" (match-string 0 $candidate)) nil t))
  (use-local-map anything-multi-swoop-edit-map))

(defun anything-multi-swoop--separate-text-property-into-list ($property)
  (interactive)
  (let ($list $end)
    (save-excursion
      (goto-char (point-min))
      (while (setq $end (next-single-property-change (point) $property))
        ;; Must eliminate last return because of unexpected edit result
        (setq $list (cons
                     (let (($str (buffer-substring-no-properties (point) $end)))
                       (if (string-match "\n\n\\'" $str)
                           (replace-regexp-in-string "\n\\'" "" $str)
                         $str))
                     $list))
        (goto-char $end))
      (setq $list (cons (buffer-substring-no-properties (point) (point-max))
                        $list)))
    (nreverse $list)))

(defun anything-multi-swoop--collect-edited-lines ()
  "Create a list of edited lines with each its own line number"
  (interactive)
  (let* (($list
          (anything-multi-swoop--separate-text-property-into-list 'anything-header))
         ($length (length $list))
         ($i 1) ;; 0th $list is header
         $pairs)
    (while (<= $i $length)
      (let ($contents)
        ;; Make ((number . line) (number . line) (number . line) ...)
        (with-temp-buffer
         (insert (format "%s" (nth (1+ $i) $list)))
         (goto-char (point-min))
         (while (re-search-forward "^\\([0-9]+\\)\s" nil t)
           (setq $contents
                 (cons (cons (string-to-number (match-string 1))
                             (buffer-substring-no-properties
                              (point)
                              (save-excursion
                                (if (re-search-forward
                                     "^\\([0-9]+\\)\s\\|^\\(\\-+\\)" nil t)
                                    (1- (match-beginning 0))
                                  (goto-char (point-max))
                                  (re-search-backward "\n" nil t)))))
                       $contents))))
        ;; Make ((buffer-name (number . line) (number . line) ...)
        ;;       (buffer-name (number . line) (number . line) ...) ...)
        (setq $pairs (cons (cons (nth $i $list) $contents) $pairs)))
      (setq $i (+ $i 2)))
    (delete '(nil) $pairs)))

(defun anything-multi-swoop--edit-complete ()
  "Apply changes to buffers and kill temporary edit buffer"
  (interactive)
  (let (($list (anything-multi-swoop--collect-edited-lines))
        $read-only)
    (mapc (lambda ($x)
            (with-current-buffer (car $x)
              (unless buffer-read-only
                (save-excursion
                  (cl-loop for ($k . $v) in (cdr $x)
                        do (progn
                             (goto-char (point-min))
                             (delete-region (point-at-bol $k) (point-at-eol $k))
                             (goto-char (point-at-bol $k))
                             (insert $v)))))
              (if anything-multi-swoop-edit-save
                  (if buffer-read-only
                      (setq $read-only t)
                    (save-buffer)))))
          $list)
    (select-window anything-swoop-synchronizing-window)
    (kill-buffer (get-buffer anything-multi-swoop-edit-buffer))
    (if $read-only
        (message "Couldn't save some buffers because of read-only")
      (message "Successfully anything-multi-swoop-edit applied to original buffer"))))

(defun anything-multi-swoop--edit-cancel ()
  "Cancel edit and kill temporary buffer"
  (interactive)
  (select-window anything-swoop-synchronizing-window)
  (kill-buffer (get-buffer anything-multi-swoop-edit-buffer))
  (message "anything-multi-swoop-edit canceled"))

;;;###autoload
(defun anything-multi-swoop-edit ()
  (interactive)
  (anything-swoop-exit-and-execute-action 'anything-multi-swoop--edit))

;;; @ anything-swoop-same-face-at-point -----------------------------------

(defsubst anything-swoop--get-at-face (&optional $point)
  (or $point (setq $point (point)))
  (let (($face (or (get-char-property $point 'read-face-name)
                   (get-char-property $point 'face))))
      $face))

(defun anything-swoop--cull-face-include-line ($face)
  (let (($list) ($po (point-min)))
    (save-excursion
      (while (setq $po (next-single-property-change $po 'face))
        (when (equal $face (anything-swoop--get-at-face $po))
          (goto-char $po)
          (setq $list (cons (format "%s %s"
                                    (line-number-at-pos $po)
                                    (buffer-substring (point-at-bol) (point-at-eol)))
                            $list))
          (let (($ov (make-overlay $po (or (next-single-property-change $po 'face)
                                           (point-max)))))
            (overlay-put $ov 'face 'anything-swoop-target-word-face)
            (overlay-put $ov 'target-buffer 'anything-swoop-target-word-face)))))
      (nreverse (delete-dups $list))))

(defun anything-swoop-same-face-at-point (&optional $face)
  (interactive)
  (or $face (setq $face (anything-swoop--get-at-face)))
  (anything-swoop :$query ""
              :$source
              `((name . "anything-swoop-same-face-at-point")
                (candidates . ,(anything-swoop--cull-face-include-line $face))
                (header-line . ,(format "%s" $face))
                (action
                 . (("Go to Line"
                     . (lambda ($line)
                         (anything-swoop--goto-line
                          (when (string-match "^[0-9]+" $line)
                            (string-to-number (match-string 0 $line))))
                         (let (($po (point))
                               ($poe (point-at-eol)))
                           (while (<= (setq $po (next-single-property-change $po 'face)) $poe)
                             (when (eq 'anything-swoop-target-word-face (anything-swoop--get-at-face $po))
                               (goto-char $po))))
                         (anything-swoop--recenter))))))))

(defun anything-multi-swoop-same-face-at-point (&optional $face)
  (interactive)
  (or $face (setq $face (anything-swoop--get-at-face)))
  (anything-multi-swoop--exec
   nil
   :$query ""
   :$func (lambda () (anything-swoop--cull-face-include-line $face))
   :$action (lambda ($line)
              (switch-to-buffer (assoc-default 'name (anything-get-current-source)))
              (anything-swoop--goto-line
               (when (string-match "^[0-9]+" $line)
                 (string-to-number (match-string 0 $line))))
              (let (($po (point))
                    ($poe (point-at-eol)))
                (while (<= (setq $po (next-single-property-change $po 'face)) $poe)
                  (when (eq 'anything-swoop-target-word-face (anything-swoop--get-at-face $po))
                    (goto-char $po))))
              (anything-swoop--recenter))
   :$buflist (anything-multi-swoop--get-buffer-list)))

(provide 'anything-swoop)
;;; anything-swoop.el ends here
