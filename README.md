<!-- [![melpa badge][melpa-badge]][melpa-link] [![melpa stable badge][melpa-stable-badge]][melpa-stable-link] -->

List match lines to another buffer, which is able to squeeze by any words you input. At the same time, the original buffer's cursor is jumping line to line according to moving up and down the line list.

<!-- ![anything-swoop](https://raw.githubusercontent.com/ShingoFukuyama/images/master/anything-swoop.gif) -->

### Feature

* Culling all lines in buffer with your input
* Highlight multiple matched pattern
* Jumping line to line according to list buffer's move
* Cache result until modifies the buffer
* Go back to the last line
* Multi separated line culling
* Culling lines are editable

### Usage

#### Now anything-swoop has several ways.

* `M-x anything-swoop` when region active
* `M-x anything-swoop` when the cursor is at any symbol
* `M-x anything-swoop` when the cursor is not at any symbol
* `M-3 M-x anything-swoop` or `C-u 5 M-x anything-swoop` multi separated line culling
* `M-x anything-multi-swoop` multi-occur like feature
* `M-x anything-multi-swoop-all` apply all buffers
* `C-u M-x anything-multi-swoop` apply last selected buffers from the second time
* `M-x anything-multi-swoop-org` apply to all org-mode buffers
* `M-x anything-multi-swoop-current-mode` apply to all buffers with the same major-mode as the current buffer
* `M-x anything-swoop-same-face-at-point` list lines have the same face at the cursor is on
* During isearch `M-i` to hand the word over to anything-swoop
* During anything-swoop `M-i` to hand the word over to anything-multi-swoop-all
* While doing `anything-swoop` press `C-c C-e` to edit mode, apply changes to original buffer by `C-x C-s`

It's able to use words within a region or a word at symbol as search query when it called. Also use a keybind you set just type like M-i instead of `M-x anything-swoop`. 

#### Edit mode
While doing `anything-swoop` type `C-c C-e` to enter the edit mode.
Before enter the edit mode, you can choose some lines marked by `C-SPC` or `M-SPC` to edit.
Apply changes to original buffer type `C-x C-s`.

#### Across multiple buffers

##### `M-x anything-multi-swoop`
1. Select any buffers by [C-SPC] or [M-SPC]
2. Press [RET] to start anything-multi-swoop

<!-- ![anything-multi-swoop](https://raw.githubusercontent.com/ShingoFukuyama/images/master/anything-multi-swoop.gif) -->

##### `M-x anything-multi-swoop-all`
Skip select phase and apply all buffers.

##### `C-u M-x anything-multi-swoop`
Skip select phase and apply last selected buffers, if you have done anything-multi-swoop before.

#### `M-x anything-multi-swoop-org`
Skip the select phase and apply to all org-mode buffers

#### `M-x anything-multi-swoop-current-mode`
Skip the select phase and apply to all buffers with the same major mode as the current buffer

#### Multiline behavior 
`M-4 M-x anything-swoop` or `C-u 4 M-x anything-swoop`

<!-- ![anything-swoop2](https://raw.githubusercontent.com/ShingoFukuyama/images/master/anything-swoop2.gif) -->

### Config

```elisp
;; anything from https://github.com/emacs-anything/anything
(require 'anything)

;; Locate the anything-swoop folder to your path
(add-to-list 'load-path "~/.emacs.d/elisp/anything-swoop")
(require 'anything-swoop)

;; Change the keybinds to whatever you like :)
(global-set-key (kbd "M-i") 'anything-swoop)
(global-set-key (kbd "M-I") 'anything-swoop-back-to-last-point)
(global-set-key (kbd "C-c M-i") 'anything-multi-swoop)
(global-set-key (kbd "C-x M-i") 'anything-multi-swoop-all)

;; When doing isearch, hand the word over to anything-swoop
(define-key isearch-mode-map (kbd "M-i") 'anything-swoop-from-isearch)
;; From anything-swoop to anything-multi-swoop-all
(define-key anything-swoop-map (kbd "M-i") 'anything-multi-swoop-all-from-anything-swoop)
;; When doing evil-search, hand the word over to anything-swoop
;; (define-key evil-motion-state-map (kbd "M-i") 'anything-swoop-from-evil-search)

;; Instead of anything-multi-swoop-all, you can also use anything-multi-swoop-current-mode
(define-key anything-swoop-map (kbd "M-m") 'anything-multi-swoop-current-mode-from-anything-swoop)

;; Move up and down like isearch
(define-key anything-swoop-map (kbd "C-r") 'anything-previous-line)
(define-key anything-swoop-map (kbd "C-s") 'anything-next-line)
(define-key anything-multi-swoop-map (kbd "C-r") 'anything-previous-line)
(define-key anything-multi-swoop-map (kbd "C-s") 'anything-next-line)

;; Save buffer when anything-multi-swoop-edit complete
(setq anything-multi-swoop-edit-save t)

;; If this value is t, split window inside the current window
(setq anything-swoop-split-with-multiple-windows nil)

;; Split direcion. 'split-window-vertically or 'split-window-horizontally
(setq anything-swoop-split-direction 'split-window-vertically)

;; If nil, you can slightly boost invoke speed in exchange for text color
(setq anything-swoop-speed-or-color nil)

;; ;; Go to the opposite side of line from the end or beginning of line
(setq anything-swoop-move-to-line-cycle t)

;; Optional face for line numbers
;; Face name is `anything-swoop-line-number-face`
(setq anything-swoop-use-line-number-face t)

```

#### Configure pre-input search query

By default, anything-swoop uses search query at the cursor.
You can configure this behavior by setting `anything-swoop-pre-input-function` on your own.

i.e.

```elisp
;; use search query at the cursor  (default)
(setq anything-swoop-pre-input-function
      (lambda () (thing-at-point 'symbol)))

;; disable pre-input
(setq anything-swoop-pre-input-function
      (lambda () ""))

;; match only for symbol
(setq anything-swoop-pre-input-function
      (lambda () (format "\\_<%s\\_> " (thing-at-point 'symbol))))

;; Always use the previous search for anything. Remember C-<backspace> will delete entire line
(setq anything-swoop-pre-input-function
      (lambda () (if (boundp 'anything-swoop-pattern)
                     anything-swoop-pattern "")))

;; If there is no symbol at the cursor, use the last used words instead.
(setq anything-swoop-pre-input-function
      (lambda ()
        (let (($pre-input (thing-at-point 'symbol)))
          (if (eq (length $pre-input) 0)
              anything-swoop-pattern ;; this variable keeps the last used words
            $pre-input))))
```

### Require

[anything.el](http://www.emacswiki.org/emacs/Anything)



<!-- [melpa-link]: http://melpa.org/#/anything-swoop -->
<!-- [melpa-stable-link]: http://stable.melpa.org/#/anything-swoop -->
<!-- [melpa-badge]: http://melpa.org/packages/anything-swoop-badge.svg -->
<!-- [melpa-stable-badge]: http://stable.melpa.org/packages/anything-swoop-badge.svg -->
