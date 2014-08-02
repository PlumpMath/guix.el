;;; guix.el --- Interface for GNU Guix package manager

;; Copyright © 2014 Alex Kost

;; Author: Alex Kost <alezost@gmail.com>
;; Version: 0.01
;; Package-Requires: ((geiser "0.3"))
;; URL: https://github.com/alezost/guix.el
;; Keywords: tools

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

;; This package is under development.  The goal is to make a
;; full-featured Emacs interface for Guix package manager
;; <http://www.gnu.org/software/guix/>.

;; Currently this package provides an interface for searching, listing
;; and getting information about Guix packages and generations.

;; To install this package, add the following to your init-file:
;;
;;   (add-to-list 'load-path "/path/to/guix-dir")
;;   (autoload 'guix-search-by-name "guix" nil t)
;;   (autoload 'guix-search-by-regexp "guix" nil t)
;;   (autoload 'guix-installed-packages "guix" nil t)
;;   (autoload 'guix-obsolete-packages "guix" nil t)
;;   (autoload 'guix-all-available-packages "guix" nil t)
;;   (autoload 'guix-newest-available-packages "guix" nil t)
;;   (autoload 'guix-generations "guix" nil t)

;;; Code:

(require 'guix-list)
(require 'guix-info)

(defgroup guix nil
  "Interface for Guix package manager."
  :prefix "guix-"
  :group 'external)

(defcustom guix-list-single-package nil
  "If non-nil, list a package even if it is the only matching result.
If nil, show a single package in the info buffer."
  :type 'boolean
  :group 'guix)

(defcustom guix-show-generations-function 'guix-generation-list-get-show
  "Default function used to display generations."
  :type '(choice (function-item guix-generation-list-get-show)
                 (function-item guix-generation-info-get-show))
  :group 'guix)

(defvar guix-search-params '(name synopsis description)
  "Default list of package parameters for searching by regexp.")

(defvar guix-search-history nil
  "A history of minibuffer prompts.")

(defun guix-get-show-packages (search-type &rest search-vals)
  "Search for packages and show results.

See `guix-get-entries' for the meaning of SEARCH-TYPE and
SEARCH-VALS.

Results are displayed in the list buffer, unless a single package
is found and `guix-list-single-package' is nil."
  (let* ((list-params (guix-package-list-get-params-for-receiving))
         (packages (guix-get-entries 'package search-type
                                     search-vals list-params)))
    (if (or guix-list-single-package
            (cdr packages))
        (guix-package-list-set packages search-type search-vals)
      (let ((info-params (guix-package-info-get-params-for-receiving)))
        (unless (equal list-params info-params)
          ;; If we don't have required info, we should receive it again
          (setq packages (guix-get-entries 'package search-type
                                           search-vals info-params))))
      (guix-package-info-set packages search-type search-vals))))

(defun guix-get-show-generations (search-type &rest search-vals)
  "Search for generations and show results."
  (apply guix-show-generations-function search-type search-vals))

;;;###autoload
(defun guix-search-by-name (name)
  "Search for Guix packages by NAME.
NAME is a string with name specification.  It may optionally contain
a version number.  Examples: \"guile\", \"guile-2.0.11\"."
  (interactive
   (list (read-string "Package name: " nil 'guix-search-history)))
  (guix-get-show-packages 'name name))

;;;###autoload
(defun guix-search-by-regexp (regexp &rest params)
  "Search for Guix packages by REGEXP.
PARAMS are package parameters that should be searched.
If PARAMS are not specified, use `guix-search-params'."
  (interactive
   (list (read-string "Regexp: " nil 'guix-search-history)))
  (or params (setq params guix-search-params))
  (guix-get-show-packages 'regexp regexp params))

;;;###autoload
(defun guix-installed-packages ()
  "Display information about installed Guix packages."
  (interactive)
  (guix-get-show-packages 'installed))

;;;###autoload
(defun guix-obsolete-packages ()
  "Display information about obsolete Guix packages."
  (interactive)
  (guix-get-show-packages 'obsolete))

;;;###autoload
(defun guix-all-available-packages ()
  "Display information about all available Guix packages."
  (interactive)
  (guix-get-show-packages 'all-available))

;;;###autoload
(defun guix-newest-available-packages ()
  "Display information about the newest available Guix packages."
  (interactive)
  (guix-get-show-packages 'newest-available))

;;;###autoload
(defun guix-generations (&optional number)
  "Display information about last NUMBER generations.
If NUMBER is nil, display all generations.

Generations can be displayed in a list or info buffers depending
on `guix-show-generations-function'.

Interactively, NUMBER is defined by a numeric prefix."
  (interactive "P")
  (guix-get-show-generations
   'last (if (numberp number) number 0)))

(provide 'guix)

;;; guix.el ends here
