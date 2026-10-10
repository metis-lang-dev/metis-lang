;; SPDX-License-Identifier: Apache-2.0
;;; llp-mode.el --- Metis LLP (rulescript v2) major mode -*- lexical-binding: t; -*-

;; Author: metis
;; Keywords: languages
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.1

;;; Commentary:
;; Syntax highlighting + eglot integration for .llp catalogs.
;; The language server is the metis toolchain itself
;; (metis/lang/lsp.py): diagnostics are the REAL compiler findings,
;; hover shows declarations, imenu/outline via documentSymbol.
;; `M-x eglot' in an .llp buffer connects (or (add-hook
;; 'llp-mode-hook #'eglot-ensure) to connect always).

;;; Code:

(defgroup llp nil "Metis LLP language support." :group 'languages)

(defcustom llp-server-command nil
  "Command to launch the LLP language server.
nil means auto-detect: metis/lang/lsp.py located up from the buffer's
directory, run with the theia venv python ($THEIA_ROOT, else the metis
checkout's ../theia sibling, else python3)."
  :type '(choice (const :tag "Auto-detect" nil) (repeat string))
  :group 'llp)

(defun llp--server-command (&optional _interactive)
  "Resolve the LLP server command (see `llp-server-command')."
  (or llp-server-command
      (let* ((root (locate-dominating-file
                    default-directory "metis/lang/lsp.py"))
             (lsp (and root (expand-file-name "metis/lang/lsp.py" root)))
             (python
              (catch 'py
                (dolist (base (list (getenv "THEIA_ROOT")
                                    (and root (expand-file-name
                                               "../theia" root))))
                  (when base
                    (let ((p (expand-file-name ".venv/bin/python" base)))
                      (when (file-executable-p p) (throw 'py p)))))
                "python3")))
        (unless lsp
          (error "llp: no metis/lang/lsp.py above %s" default-directory))
        (list python lsp))))

(defvar llp-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?% "<" st)      ; % and %% start comments
    (modify-syntax-entry ?\n ">" st)
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?- "_" st)      ; idents carry hyphens
    (modify-syntax-entry ?_ "_" st)
    (modify-syntax-entry ?$ "'" st)      ; persist marker
    st))

(defconst llp-font-lock-keywords
  `(;; %% doc lines (the human-approved unit) — doc face
    ("^\\s-*%%.*$" 0 font-lock-doc-face t)
    ;; header keywords
    (,(regexp-opt '("catalog" "provenance" "extends" "include"
                    "layers" "stages")
                  'symbols)
     . font-lock-keyword-face)
    ;; declaration keywords
    (,(regexp-opt '("type" "namespace" "pred" "bwd" "weight"
                    "guard" "input" "output" "stage" "qui"
                    "produce" "consume" "reads" "if" "one")
                  'symbols)
     . font-lock-builtin-face)
    ;; rule head:  name [layer] :
    ("^\\s-*\\([a-z][A-Za-z0-9_-]*\\)\\s-*\\[\\([A-Za-z][A-Za-z0-9_-]*\\)\\]\\s-*:"
     (1 font-lock-function-name-face)
     (2 font-lock-constant-face))
    ;; declared names after a decl keyword
    ("^\\s-*\\(?:type\\|namespace\\|pred\\|bwd\\|weight\\|guard\\|stage\\|qui\\)\\s-+\\([A-Za-z][A-Za-z0-9_-]*\\)"
     1 font-lock-function-name-face)
    ;; weight port refs:  @w [~]factor
    ("\\(@w\\)\\s-*\\(~\\)?\\s-*\\([A-Za-z][A-Za-z0-9_-]*\\)?"
     (1 font-lock-preprocessor-face)
     (3 font-lock-type-face nil t))
    ;; the lolli and friends
    ("-o\\|:-\\|<>" . font-lock-preprocessor-face)
    ;; persist marker
    ("\\(\\$\\)\\([A-Za-z][A-Za-z0-9_-]*\\)"
     (1 font-lock-preprocessor-face)
     (2 font-lock-variable-name-face))
    ;; VARIABLES (uppercase-first)
    ("\\_<[A-Z][A-Za-z0-9_-]*\\_>" . font-lock-variable-name-face))
  "Font lock for `llp-mode'.")

(defun llp--imenu ()
  "Imenu over stages, rules and vocabulary."
  (let (index)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              "^\\s-*\\(?:\\(stage\\|qui\\|pred\\|weight\\|type\\)\\s-+\\([A-Za-z][A-Za-z0-9_-]*\\)\\|\\([a-z][A-Za-z0-9_-]*\\)\\s-*\\[\\)"
              nil t)
        (let ((name (or (match-string-no-properties 2)
                        (match-string-no-properties 3))))
          (when name
            (push (cons name (match-beginning 0)) index)))))
    (nreverse index)))

;;;###autoload
(define-derived-mode llp-mode prog-mode "LLP"
  "Major mode for Metis LLP (rulescript v2) catalogs."
  :syntax-table llp-mode-syntax-table
  (setq-local comment-start "% "
              comment-start-skip "%+\\s-*"
              font-lock-defaults '(llp-font-lock-keywords)
              imenu-create-index-function #'llp--imenu))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.llp\\'" . llp-mode))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(llp-mode . llp--server-command)))

(provide 'llp-mode)
;;; llp-mode.el ends here
