;;; guix-backend.el --- Communication with Geiser

;; Copyright © 2014 Alex Kost

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file provides the code for interacting with Guile using Geiser.

;; By default (if `guix-use-guile-server' is non-nil) 2 Geiser REPLs are
;; started.  The main one (with "guile --listen" process) is used for
;; "interacting" with a user - for showing a progress of
;; installing/deleting Guix packages.  The second (internal) REPL is
;; used for synchronous evaluating, e.g. when information about
;; packages/generations should be received for a list/info buffer.
;;
;; This "2 REPLs concept" makes it possible to have a running process of
;; installing/deleting packages and to continue to search/list/get info
;; about other packages at the same time.  If you prefer to use a single
;; Guix REPL, do not try to receive any information while there is a
;; running code in the REPL (see
;; <https://github.com/jaor/geiser/issues/28>).
;;
;; If you need to use "guix.el" in another Emacs (i.e. when there is
;; a runnig "guile --listen..." REPL somewhere), you can either change
;; `guix-default-port' in that Emacs instance or set
;; `guix-use-guile-server' to t.
;;
;; Guix REPLs (unlike the usual Geiser REPLs) are not added to
;; `geiser-repl--repls' variable, and thus cannot be used for evaluating
;; while editing scm-files.  The only purpose of Guix REPLs is to be an
;; intermediate between "Guix/Guile level" and "Emacs interface level".
;; That being said you can still want to use a Guix REPL while hacking
;; auxiliary scheme-files for "guix.el".  You can just use "M-x
;; connect-to-guile" (connect to "localhost" and `guix-default-port') to
;; have a usual Geiser REPL with all stuff defined by "guix.el" package.

;;; Code:

(require 'geiser-mode)

(defvar guix-load-path
  (file-name-directory (or load-file-name
                           (locate-library "guix")))
  "Directory with scheme files for \"guix.el\" package.")

(defvar guix-helper-file
  (expand-file-name "guix-helper.scm" guix-load-path)
  "Auxiliary scheme file for loading.")

(defvar guix-guile-program (or geiser-guile-binary "guile")
  "Name of the guile executable used for Guix REPL.
May be either a string (the name of the executable) or a list of
strings of the form:

  (NAME . ARGS)

Where ARGS is a list of arguments to the guile program.")


;;; REPL

(defgroup guix-repl nil
  "Settings for Guix REPLs."
  :prefix "guix-repl-"
  :group 'guix)

(defcustom guix-repl-startup-time 30000
  "Time, in milliseconds, to wait for Guix REPL to startup.
Same as `geiser-repl-startup-time' but is used for Guix REPL.
If you have a slow system, try to increase this time."
  :type 'integer
  :group 'guix-repl)

(defcustom guix-repl-buffer-name "*Guix REPL*"
  "Default name of a Geiser REPL buffer used for Guix."
  :type 'string
  :group 'guix-repl)

(defcustom guix-after-start-repl-hook ()
  "Hook called after Guix REPL is started."
  :type 'hook
  :group 'guix-repl)

(defcustom guix-use-guile-server t
  "If non-nil, start guile with '--listen' argument.
This allows to receive information about packages using an additional
REPL while some packages are being installed/removed in the main REPL."
  :type 'boolean
  :group 'guix-repl)

(defcustom guix-default-port 37246
  "Default port used if `guix-use-guile-server' is non-nil."
  :type 'integer
  :group 'guix-repl)

(defvar guix-repl-buffer nil
  "Main Geiser REPL buffer used for communicating with Guix.
This REPL is used for processing package actions and for
receiving information if `guix-use-guile-server' is nil.")

(defvar guix-internal-repl-buffer nil
  "Additional Geiser REPL buffer used for communicating with Guix.
This REPL is used for receiving information only if
`guix-use-guile-server' is non-nil.")

(defvar guix-internal-repl-buffer-name "*Guix Internal REPL*"
  "Default name of an internal Guix REPL buffer.")

(defun guix-get-guile-program (&optional internal)
  "Return a value suitable for `geiser-guile-binary'."
  (if (or internal
          (not guix-use-guile-server))
      guix-guile-program
    (append (if (listp guix-guile-program)
                guix-guile-program
              (list guix-guile-program))
            ;; Guile understands "--listen=..." but not "--listen ..."
            (list (concat "--listen="
                          (number-to-string guix-default-port))))))

(defun guix-start-process-maybe ()
  "Start Geiser REPL configured for Guix if needed."
  (guix-start-repl-maybe)
  (if guix-use-guile-server
      (guix-start-repl-maybe 'internal)
    (setq guix-internal-repl-buffer guix-repl-buffer)))

(defun guix-start-repl-maybe (&optional internal)
  "Start Guix REPL if needed.
If INTERNAL is non-nil, start an internal REPL."
  (let* ((repl-var (guix-get-repl-buffer-variable internal))
         (repl (symbol-value repl-var)))
    (unless (and (buffer-live-p repl)
                 (get-buffer-process repl))
      ;; Kill REPL buffer with a dead process
      (and (buffer-live-p repl) (kill-buffer repl))
      (or internal
          (message "Starting Geiser REPL for Guix ..."))
      (let ((geiser-guile-binary (guix-get-guile-program internal))
            (geiser-guile-init-file (or internal guix-helper-file))
            (repl (get-buffer-create
                   (guix-get-repl-buffer-name internal))))
        (condition-case err
            (guix-start-repl repl
                             (and internal
                                  (geiser-repl--read-address
                                   "localhost" guix-default-port)))
          (text-read-only
           (error (concat "Couldn't start Guix REPL.  Perhaps the port %s is busy.\n"
                          "See buffer '%s' for details")
                  guix-default-port (buffer-name repl))))
        (set repl-var repl)
        (unless internal
          (message "Guix REPL has been started.")
          (run-hooks 'guix-after-start-repl-hook))))))

(defun guix-start-repl (buffer &optional address)
  "Start Guix REPL in BUFFER.
If ADDRESS is non-nil, connect to a remote guile process using
this address (it should be defined by
`geiser-repl--read-address')."
  ;; A mix of the code from `geiser-repl--start-repl' and
  ;; `geiser-repl--to-repl-buffer'.
  (let ((impl 'guile)
        (geiser-guile-load-path (list guix-load-path))
        (geiser-repl-startup-time guix-repl-startup-time))
    (with-current-buffer buffer
      (geiser-repl-mode)
      (geiser-impl--set-buffer-implementation impl)
      (geiser-repl--autodoc-mode -1)
      (goto-char (point-max))
      (let* ((prompt-re (geiser-repl--prompt-regexp impl))
             (deb-prompt-re (geiser-repl--debugger-prompt-regexp impl))
             (prompt (geiser-con--combined-prompt prompt-re deb-prompt-re)))
        (or prompt-re
            (error "Oh no! Guix REPL in the buffer '%s' has not been started"
                   (buffer-name buffer)))
        (geiser-repl--save-remote-data address)
        (geiser-repl--start-scheme impl address prompt)
        (geiser-repl--quit-setup)
        (geiser-repl--history-setup)
        (setq-local geiser-repl--repls (list buffer))
        (geiser-repl--set-this-buffer-repl buffer)
        (setq geiser-repl--connection
              (geiser-con--make-connection
               (get-buffer-process (current-buffer))
               prompt-re
               deb-prompt-re))
        (geiser-repl--startup impl address)
        (geiser-repl--autodoc-mode 1)
        (geiser-company--setup geiser-repl-company-p)
        (add-hook 'comint-output-filter-functions
                  'geiser-repl--output-filter
                  nil t)
        (set-process-query-on-exit-flag
         (get-buffer-process (current-buffer))
         geiser-repl-query-on-kill-p)))))

(defun guix-get-repl-buffer (&optional internal)
  "Return Guix REPL buffer; start REPL if needed.
If INTERNAL is non-nil, return an additional internal REPL."
  (guix-start-process-maybe)
  (let ((repl (symbol-value (guix-get-repl-buffer-variable internal))))
    ;; If a new Geiser REPL is started, `geiser-repl--repl' variable may
    ;; be set to the new value in a Guix REPL, so set it back to a
    ;; proper value here.
    (with-current-buffer repl
      (geiser-repl--set-this-buffer-repl repl))
    repl))

(defun guix-get-repl-buffer-variable (&optional internal)
  "Return the name of a variable with a REPL buffer."
  (if internal
      'guix-internal-repl-buffer
    'guix-repl-buffer))

(defun guix-get-repl-buffer-name (&optional internal)
  "Return the name of a REPL buffer."
  (if internal
      guix-internal-repl-buffer-name
    guix-repl-buffer-name))

(defun guix-switch-to-repl (&optional internal)
  "Switch to Guix REPL.
If INTERNAL is non-nil (interactively with prefix), switch to the
additional internal REPL if it exists."
  (interactive "P")
  (geiser-repl--switch-to-buffer (guix-get-repl-buffer internal)))


;;; Evaluating expressions

(defun guix-make-guile-expression (fun &rest args)
  "Return string containing a guile expression for calling FUN with ARGS."
  (format "(%S %s)" fun
          (mapconcat
           (lambda (arg)
             (cond
              ((null arg) "'()")
              ((or (eq arg t)
                   ;; An ugly hack to separate 'false' from nil
                   (equal arg 'f)
                   (keywordp arg))
               (concat "#" (prin1-to-string arg t)))
              ((or (symbolp arg) (listp arg))
               (concat "'" (prin1-to-string arg)))
              (t (prin1-to-string arg))))
           args
           " ")))

(defun guix-eval (str &optional wrap)
  "Evaluate guile expression STR.
If WRAP is non-nil, wrap STR into (begin ...) form.
Return a list of strings with result values of evaluation."
  (with-current-buffer (guix-get-repl-buffer 'internal)
    (let* ((wrapped (if wrap (geiser-debug--wrap-region str) str))
           (code `(:eval (:scm ,wrapped)))
           (ret (geiser-eval--send/wait code)))
      (if (geiser-eval--retort-error ret)
          (error "Error in evaluating guile expression: %s"
                 (geiser-eval--retort-output ret))
        (cdr (assq 'result ret))))))

(defun guix-eval-read (str &optional wrap)
  "Evaluate guile expression STR.
For the meaning of WRAP, see `guix-eval'.
Return elisp expression of the first result value of evaluation."
  ;; Parsing scheme code with elisp `read' is probably not the best idea.
  (read (replace-regexp-in-string
         "#f\\|#<unspecified>" "nil"
         (replace-regexp-in-string
          "#t" "t" (car (guix-eval str wrap))))))

(defun guix-eval-in-repl (str)
  "Switch to Guix REPL and evaluate STR with guile expression there."
  (let ((repl (guix-get-repl-buffer)))
    (with-current-buffer repl
      (delete-region (geiser-repl--last-prompt-end) (point-max))
      (goto-char (point-max))
      (insert str)
      (geiser-repl--send-input))
    (geiser-repl--switch-to-buffer repl)))

(provide 'guix-backend)

;;; guix-backend.el ends here
