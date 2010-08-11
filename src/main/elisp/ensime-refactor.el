;;; ensime-refactor.el
;;
;;;; License
;;
;;     Copyright (C) 2010 Aemon Cannon
;;
;;     This program is free software; you can redistribute it and/or
;;     modify it under the terms of the GNU General Public License as
;;     published by the Free Software Foundation; either version 2 of
;;     the License, or (at your option) any later version.
;;
;;     This program is distributed in the hope that it will be useful,
;;     but WITHOUT ANY WARRANTY; without even the implied warranty of
;;     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;;     GNU General Public License for more details.
;;
;;     You should have received a copy of the GNU General Public
;;     License along with this program; if not, write to the Free
;;     Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
;;     MA 02111-1307, USA.


(defvar ensime-refactor-id-counter 0
  "Each refactoring is given a unique id.")

(defvar ensime-refactor-info-buffer-name "*Ensime Refactoring Procedure*")

(defvar ensime-refactor-info-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") (lambda()(interactive)
				(funcall continue-refactor)
				(ensime-popup-buffer-quit-function)
				))
    (define-key map (kbd "q") (lambda()(interactive)
				(funcall cancel-refactor)
				(ensime-popup-buffer-quit-function)
				))
    map)
  "Type and package inspector specific key bindings 
   (in addition to those defined by popup-buffer-mode)")


(defmacro* ensime-refactor-with-info-buffer ((&optional select) &body body)
  "Extend the standard popup buffer with inspector-specific bindings."
  `(ensime-with-popup-buffer
    (,ensime-refactor-info-buffer-name t ,select)
    (use-local-map ensime-refactor-info-map)
    ,@body
    ))

(defun ensime-refactor-insert-prompt (text)
  (ensime-insert-with-face 
   (concat text " (c to confirm, q to cancel)") 
   'font-lock-constant-face)
  (insert "\n----------------------------------------\n\n"))

(defun ensime-refactor-notify-failure (result)
  (message "Refactoring failed: %s" (plist-get result :reason)))

(defun ensime-refactor-organize-imports ()
  (interactive)
  (ensime-assert-buffer-saved-interactive
   (let ((filename buffer-file-name))
     (incf ensime-refactor-id-counter)
     (message "Please wait...")
     (ensime-rpc-refactor-prep 
      ensime-refactor-id-counter
      'organizeImports
      `(file ,filename)
      'ensime-refactor-organize-imports-step-2
      ))))

(defun ensime-refactor-organize-imports-step-2 (result)
  (let ((status (plist-get result :status))
	(id (plist-get result :procedure-id)))
    (if (equal status 'success)
	(ensime-rpc-refactor-perform 
	 id 'organizeImports '()
	 'ensime-refactor-organize-imports-step-3)
      (ensime-refactor-notify-failure result)
      )))

(defun ensime-refactor-organize-imports-step-3 (result)
  (let ((status (plist-get result :status))
	(id (plist-get result :procedure-id))
	(changes (plist-get result :changes)))
    (if (equal status 'success)
	(let ((cont `(lambda () (ensime-rpc-refactor-exec
				 ,id 'organizeImports
				 '() 'ensime-refactor-handle-result)))
	      (cancel `(lambda () (ensime-rpc-refactor-cancel ,id))))

	  (ensime-refactor-with-info-buffer
	   (t)
	   (set (make-local-variable 'cancel-refactor) cancel)
	   (set (make-local-variable 'continue-refactor) cont)
	   (ensime-refactor-insert-prompt "See revised file below.")
	   (dolist (ch changes)
	     (insert (plist-get ch :file))
	     (insert "\n\n--------------------------\n")
	     (insert (plist-get ch :text))
	     (insert "\n\n"))
	   (goto-char (point-min))
	   ))
      
      (ensime-refactor-notify-failure result)
      )))


(defun ensime-refactor-handle-result (result)
  (let ((touched (plist-get result :touched-files)))
    (dolist (f touched)
      (when-let (buf (find-buffer-visiting f))
	(with-current-buffer buf
	  (revert-buffer t t)
	  (ensime-typecheck-current-file))
	))))



(provide 'ensime-refactor)