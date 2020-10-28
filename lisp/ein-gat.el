;;; ein-gat.el --- hooks to gat -*- lexical-binding: t; -*-

;; Copyright (C) 2019 The Authors

;; Authors: dickmao <github id: dickmao>

;; This file is NOT part of GNU Emacs.

;; ein-gat.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; ein-gat.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with ein-gat.el.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'magit-process nil t)
(declare-function ein:jupyter-running-notebook-directory "ein-jupyter")

;; (declare-function magit--process-coding-system "magit-process")
;; (declare-function magit-call-process "magit-process")
;; (declare-function magit-start-process "magit-process")
;; (declare-function magit-process-sentinel "magit-process")

(defconst ein:gat-status-cd 7 "gat exits 7 if requiring a change directory.")

(defcustom ein:gat-python-command (if (equal system-type 'windows-nt)
                                      (or (executable-find "py")
                                          (executable-find "pythonw")
                                          "python")
                                    "python")
  "Python executable name."
  :type (append '(choice)
                (let (result)
                  (dolist (py '("python" "python3" "pythonw" "py")
                              result)
                    (setq result (append result `((const :tag ,py ,py))))))
                '((string :tag "Other")))
  :group 'ein)

(defsubst ein:gat-shell-command (command)
  (string-trim (shell-command-to-string (concat "2>/dev/null " command))))

(defcustom ein:gat-gce-zone (ein:gat-shell-command "gcloud config get-value compute/zone")
  "gcloud project zone."
  :type 'string
  :group 'ein)

(defcustom ein:gat-gce-region (ein:gat-shell-command "gcloud config get-value compute/region")
  "gcloud project region."
  :type 'string
  :group 'ein)

(defcustom ein:gat-aws-region (ein:gat-shell-command "aws configure get region")
  "gcloud project region."
  :type 'string
  :group 'ein)

(defcustom ein:gat-gce-project (ein:gat-shell-command "gcloud config get-value core/project")
  "gcloud project id."
  :type 'string
  :group 'ein)

(defcustom ein:gat-aws-machine-types (split-string "g3s.xlarge p2.xlarge p3.2xlarge")
  "gcloud machine types."
  :type '(repeat string)
  :group 'ein)

(defcustom ein:gat-gce-machine-types (split-string (ein:gat-shell-command (format "gcloud compute machine-types list --filter=\"zone:%s\" --format=\"value[terminator=' '](name)\"" ein:gat-gce-zone)))
  "gcloud machine types."
  :type '(repeat string)
  :group 'ein)

(defcustom ein:gat-gpu-types (split-string "nvidia-tesla-t4")
  "https://accounts.google.com/o/oauth2/auth?client_id=[client-id]&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/compute&response_type=code
curl -d code=[page-code] -d client_id=[client-id] -d client_secret=[client-secret] -d redirect_uri=urn:ietf:wg:oauth:2.0:oob -d grant_type=authorization_code https://accounts.google.com/o/oauth2/token
curl -sLk -H \"Authorization: Bearer [access-token]\" https://compute.googleapis.com/compute/v1/projects/[project-id]/zones/[zone-id]/acceleratorTypes | jq -r -c '.items[].selfLink'"
  :type '(repeat string)
  :group 'ein)

(defcustom ein:gat-base-images '("jupyter/scipy-notebook"
                                 "jupyter/tensorflow-notebook"
				 "jupyter/datascience-notebook"
				 "jupyter/r-notebook"
				 "jupyter/minimal-notebook"
				 "jupyter/base-notebook"
				 "jupyter/pyspark-notebook"
                                 "jupyter/all-spark-notebook"
                                 "dickmao/pytorch-gpu")
  "Known https://hub.docker.com/u/jupyter images."
  :type '(repeat (string :tag "FROM-appropriate docker image"))
  :group 'ein)

(defvar ein:gat-previous-worktree nil)

(defconst ein:gat-master-worktree "master")

(defvar ein:gat-current-worktree ein:gat-master-worktree)

(defvar-local ein:gat-disksizegb-history '("default")
  "Hopefully notebook-specific history of user entered disk size.")

(defvar-local ein:gat-gpus-history '("0")
  "Hopefully notebook-specific history of user entered gpu count.")

(defvar-local ein:gat-machine-history nil
  "Hopefully notebook-specific history of user entered machine type.")

(defun ein:gat-where-am-i (&optional print-message)
  (interactive "p")
  (if-let ((notebook-dir (ein:jupyter-running-notebook-directory))
           (notebook (ein:get-notebook))
           (where (directory-file-name
                   (concat (file-name-as-directory notebook-dir)
                           (file-name-directory (ein:$notebook-notebook-path notebook))))))
      (prog1 where
        (when print-message
          (message where)))
    (prog1 nil
      (when print-message
	(message "nowhere")))))

;; (defvar magit-process-popup-time)
;; (defvar inhibit-magit-refresh)
;; (defvar magit-process-raise-error)
;; (defvar magit-process-display-mode-line-error)
(cl-defun ein:gat-chain (buffer callback &rest args &key public-ip-address &allow-other-keys)
  (declare (indent 0))
  (when public-ip-address
    (setq args (butlast args 2))
    (ein:login (ein:url (format "http://%s:8888" public-ip-address))
               (lambda (buffer _url-or-port) (pop-to-buffer buffer))))
  (let* ((default-directory (ein:gat-where-am-i))
         (default-process-coding-system (magit--process-coding-system))
	 (inhibit-magit-refresh t)
	 (process-environment (cons (concat "GOOGLE_APPLICATION_CREDENTIALS="
					    (or (getenv "GAT_APPLICATION_CREDENTIALS")
                                                (error "GAT_APPLICATION_CREDENTIALS undefined")))
				    process-environment))
         (activate-with-editor-mode
          (when (string= (car args) with-editor-emacsclient-executable)
            (lambda () (when (string= (buffer-name) (car (last args)))
                         (with-editor-mode 1)))))
         (process (apply #'magit-start-process args)))
    (when activate-with-editor-mode
      (add-hook 'find-file-hook activate-with-editor-mode))
    (set-process-sentinel
     process
     (lambda (proc event)
       (let* ((gat-status (process-exit-status proc))
              (process-buf (process-buffer proc))
              (section (process-get proc 'section))
              (gat-status-cd-p (= gat-status ein:gat-status-cd))
              worktree-dir public-ip-address)
         (when activate-with-editor-mode
           (remove-hook 'find-file-hook activate-with-editor-mode))
	 (let ((magit-process-display-mode-line-error
		(if gat-status-cd-p nil magit-process-display-mode-line-error))
	       (magit-process-raise-error
		(if gat-status-cd-p nil magit-process-raise-error))
               (short-circuit (lambda (&rest _args) (when gat-status-cd-p 0))))
           (add-function :before-until (symbol-function 'process-exit-status)
                         short-circuit)
           (unwind-protect
               (magit-process-sentinel proc event)
             (remove-function (symbol-function 'process-exit-status) short-circuit)))
	 (cond
          ((or (zerop gat-status) gat-status-cd-p)
           (alet (and (bufferp process-buf)
                      (with-current-buffer process-buf
                        (buffer-substring-no-properties (oref section content)
                                                        (oref section end))))
             (when it
               (when gat-status-cd-p
                 (setq worktree-dir (when (string-match "^cd\\s-+\\(\\S-+\\)" it)
                                          (string-trim (match-string 1 it)))))
               (when-let ((last-line (car (last (split-string (string-trim it) "\n")))))
                 (setq public-ip-address
                       (when (string-match "^\\([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\\)\\s-+\\S-+$" last-line)
                         (string-trim (match-string 1 last-line))))))
             (when callback
               (with-current-buffer buffer
                 (let ((magit-process-popup-time 0))
                   (apply callback
                          (append
                           (when worktree-dir
                             `(:worktree-dir ,worktree-dir))
                           (when public-ip-address
                             `(:public-ip-address ,public-ip-address)))))))))
          (t
           (ein:log 'error "ein:gat-chain: %s exited %s"
		     (car args) (process-exit-status proc)))))))
    process))

(defun ein:gat--path (archepath worktree-dir)
  "Form new relative path from ARCHEPATH root, WORKTREE-DIR subroot, and ARCHEPATH leaf.

With WORKTREE-DIR of 3/4/1/2/.gat/fantab,
1/2/eager.ipynb -> 1/2/.gat/fantab/eager.ipynb
1/2/.gat/fubar/subdir/eager.ipynb -> 1/2/.gat/fantab/subdir/eager.ipynb

With WORKTREE-DIR of /home/dick/gat/test-repo2
.gat/getout/eager.ipynb -> eager.ipynb
"
  (when-let ((root (directory-file-name (or (awhen (cl-search ".gat/" archepath :from-end)
                                              (cl-subseq archepath 0 it))
                                            (file-name-directory archepath)
                                            ""))))
    (if (zerop (length root))
        (concat (replace-regexp-in-string
                 "^\\./" ""
                 (file-name-as-directory
                  (cl-subseq worktree-dir
                             (or (cl-search ".gat/" worktree-dir :from-end)
                                 (length worktree-dir)))))
                (file-name-nondirectory archepath))
      (concat (file-name-as-directory
               (cl-subseq worktree-dir
                          (cl-search root worktree-dir :from-end)))
              (or (awhen (string-match "\\(\\.gat/[^/]+/\\)" archepath)
                    (cl-subseq archepath (+ it (length (match-string 1 archepath)))))
                  (file-name-nondirectory archepath))))))

(defun ein:gat-edit (&optional _refresh)
  (interactive "P")
  (if-let ((default-directory (ein:gat-where-am-i))
           (notebook (ein:get-notebook))
           (gat-chain-args `("gat" nil "--project" "-"
                             "--region" ,ein:gat-aws-region "--zone" "-")))
      (if (special-variable-p 'magit-process-popup-time)
          (let ((magit-process-popup-time -1))
            (apply #'ein:gat-chain (current-buffer)
                   (cl-function
                    (lambda (&rest args &key worktree-dir)
                      (ein:notebook-open
                       (ein:$notebook-url-or-port notebook)
                       (ein:gat--path (ein:$notebook-notebook-path notebook)
                                      worktree-dir)
                       (ein:$notebook-kernelspec notebook))))
                   (append gat-chain-args
                           (list "edit"
                                 (alet (ein:gat-elicit-worktree t)
                                   (setq ein:gat-previous-worktree ein:gat-current-worktree)
                                   (setq ein:gat-current-worktree it))))))
        (error "ein:gat-create: magit not installed"))
    (message "ein:gat-edit: not a notebook buffer")))

(defun ein:gat-create (&optional _refresh)
  (interactive "P")
  (if-let ((default-directory (ein:gat-where-am-i))
           (notebook (ein:get-notebook))
           (gat-chain-args `("gat" nil "--project" "-"
                             "--region" ,ein:gat-aws-region "--zone" " -")))
      (if (special-variable-p 'magit-process-popup-time)
          (let ((magit-process-popup-time 0))
            (apply #'ein:gat-chain (current-buffer)
                   (cl-function
                    (lambda (&rest args &key worktree-dir)
                      (ein:notebook-open
                       (ein:$notebook-url-or-port notebook)
                       (ein:gat--path (ein:$notebook-notebook-path notebook)
                                      worktree-dir)
                       (ein:$notebook-kernelspec notebook))))
                   (append gat-chain-args
                           (list "create"
                                 (alet (ein:gat-elicit-worktree nil)
                                   (setq ein:gat-previous-worktree ein:gat-current-worktree)
                                   (setq ein:gat-current-worktree it))))))
        (error "ein:gat-create: magit not installed"))
    (message "ein:gat-create: not a notebook buffer")))

(defsubst ein:gat-run-local (&optional refresh)
  (interactive "P")
  (ein:gat--run-local-or-remote nil refresh nil))

(defsubst ein:gat-run-remote (&optional refresh)
  (interactive "P")
  (ein:gat--run-local-or-remote t refresh nil))

(defun ein:gat-hash-password (raw-password)
  (let ((gat-hash-password-python
         (format "%s - <<EOF
from notebook.auth import passwd
print(passwd('%s'))
EOF
" ein:gat-python-command raw-password)))
    (ein:gat-shell-command gat-hash-password-python)))

(defun ein:gat-crib-password ()
  (let* ((gat-crib-password-python
          (format "%s - <<EOF
from traitlets.config.application import Application
from traitlets import Unicode
class NotebookApp(Application):
  password = Unicode(u'', config=True,)

app = NotebookApp()
app.load_config_file('jupyter_notebook_config.py', '~/.jupyter')
print(app.password)
EOF
" ein:gat-python-command))
         (config-dir
          (elt (assoc-default
                'config
                (json-read-from-string (ein:gat-shell-command "jupyter --paths --json")))
               0))
         (config-json (expand-file-name "jupyter_notebook_config.json" config-dir))
         (config-py (expand-file-name "jupyter_notebook_config.py" config-dir))
         password)
    (when (file-exists-p config-py)
      (setq password
            (ein:gat-shell-command gat-crib-password-python)))
    (unless (stringp password)
      (when (file-exists-p config-json)
        (-let* (((&alist 'NotebookApp (&alist 'password))
                 (json-read-file config-json)))
          password)))
    password))

(defun ein:gat-kaggle-env (var json-key)
  (when-let ((val (or (getenv var)
                      (let ((json (expand-file-name "kaggle.json" "~/.kaggle")))
                        (when (file-exists-p json)
                          (assoc-default json-key (json-read-file json)))))))
    (format "--env %s=%s" var val)))

(defun ein:gat--run-local-or-remote (remote-p refresh batch-p)
  (unless with-editor-emacsclient-executable
    (error "Could not determine emacsclient"))
  (if-let ((default-directory (ein:gat-where-am-i))
           (notebook (aand (ein:get-notebook)
                           (ein:$notebook-notebook-name it)))
           (password (or (ein:gat-crib-password)
                         (let ((new-password
                                (read-passwd "Enter new password for remote server [none]: " t)))
                           (if (zerop (length new-password))
                               ""
                             (let ((hashed (ein:gat-hash-password new-password)))
                               (if (string-prefix-p "sha1:" hashed)
                                   hashed
                                 (prog1 nil
                                   (ein:log 'error "ein:gat--run-local-or-remote: %s %s"
                                            "Could not hash" new-password))))))))
           (gat-chain-args `("gat" nil
                             "--project" "-"
                             "--region" ,ein:gat-aws-region
                             "--zone" "-"))
           (gat-chain-run (if remote-p
                              (append '("run-remote")
                                      `("--user" "root")
                                      `("--env" "GRANT_SUDO=1")
                                      (awhen (ein:gat-kaggle-env "KAGGLE_USERNAME" 'username)
                                        (split-string it))
                                      (awhen (ein:gat-kaggle-env "KAGGLE_KEY" 'key)
                                        (split-string it))
                                      (awhen (ein:gat-kaggle-env "KAGGLE_NULL" 'null)
                                        (split-string it))
                                      `("--machine" ,(ein:gat-elicit-machine))
                                      `(,@(aif (ein:gat-elicit-disksizegb)
                                              (list "--disksizegb"
                                                    (number-to-string it))))
                                      `(,@(-when-let* ((gpus (ein:gat-elicit-gpus))
                                                       (nonzero (not (zerop gpus))))
                                            (list "--gpus"
                                                  (number-to-string gpus)))))
                            (list "run-local"))))
      (cl-destructuring-bind (pre-docker . post-docker) (ein:gat-dockerfiles-state)
        (if (or refresh (null pre-docker) (null post-docker))
            (if (fboundp 'magit-with-editor)
                (magit-with-editor
                  (let* ((dockerfile (format "Dockerfile.%s" (file-name-sans-extension notebook)))
                         (base-image (ein:gat-elicit-base-image))
                         (_ (with-temp-file
                                dockerfile
                              (insert (format "FROM %s\nCOPY --chown=jovyan:users ./%s .\n" base-image notebook))
                              (insert (cond (batch-p
                                             (format "CMD [ \"start.sh\", \"jupyter\", \"nbconvert\", \"--ExecutePreprocessor.timeout=21600\", \"--to\", \"notebook\", \"--execute\", \"%s\" ]\n" notebook))
                                            ((zerop (length password))
                                             (format "CMD [ \"start-notebook.sh\", \"--NotebookApp.token=''\" ]\n"))
                                            (t
                                             (format "CMD [ \"start-notebook.sh\", \"--NotebookApp.password=%s\" ]\n" password))))))
                         (my-editor (when (and (boundp 'server-name)
                                               (server-running-p server-name))
                                      `("-s" ,server-name))))
                    (apply #'ein:gat-chain
                           (current-buffer)
                           (apply #'apply-partially
                                  #'ein:gat-chain
                                  (current-buffer)
                                  (apply #'apply-partially
                                         #'ein:gat-chain
                                         (current-buffer)
                                         (when remote-p
                                           (apply #'apply-partially #'ein:gat-chain (current-buffer) nil
                                                  (append gat-chain-args (list "log" "-f"))))
                                         (append gat-chain-args gat-chain-run (list "--dockerfile" dockerfile)))
                                  (append gat-chain-args (list "dockerfile" dockerfile)))
                           `(,with-editor-emacsclient-executable nil ,@my-editor ,dockerfile))))
              (error "ein:gat--run-local-or-remote: magit not installed"))
          (if (special-variable-p 'magit-process-popup-time)
              (let ((magit-process-popup-time 0))
                (apply #'ein:gat-chain (current-buffer)
                       (when remote-p
                         (apply #'apply-partially #'ein:gat-chain (current-buffer) nil
                                (append gat-chain-args (list "log" "-f"))))
                       (append gat-chain-args gat-chain-run (list "--dockerfile" pre-docker))))
            (error "ein:gat--run-local-or-remote: magit not installed"))))
    (message "ein:gat--run-local-or-remote: aborting")))

(defun ein:gat-elicit-base-image ()
  "Using a defcustom as HIST is suspect but pithy."
  (ein:completing-read
   "FROM image: " ein:gat-base-images nil 'confirm
   nil 'ein:gat-base-images (car ein:gat-base-images)))

(defun ein:gat-elicit-machine ()
  (interactive)
  (ein:completing-read
   "Machine Type: " ein:gat-aws-machine-types nil t nil
   'ein:gat-machine-history (car (or ein:gat-machine-history ein:gat-aws-machine-types))))

(defun ein:gat-elicit-gpus ()
  (interactive)
  (cl-loop for answer =
	   (string-to-number (ein:completing-read
			      "Number GPUs: " '("0") nil nil nil
			      'ein:gat-gpus-history (car ein:gat-gpus-history)))
	   until (>= answer 0)
	   finally return answer))
(add-function :override (symbol-function 'ein:gat-elicit-gpus) #'ignore)

(defun ein:gat-elicit-worktree (extant)
  (let ((already (split-string
                  (ein:gat-shell-command
                   (format "gat --project %s --region %s --zone - list"
                           "-" ein:gat-aws-region)))))
    (if extant
        (ein:completing-read
         "Experiment: " already nil t nil nil
         ein:gat-previous-worktree)
      (read-string "New experiment: "))))

(defun ein:gat-elicit-disksizegb ()
  "Return nil for default [currently max(8, 6 + image size)]."
  (interactive)
  (cl-loop with answer
	   do (setq answer (ein:completing-read
			    "Disk GiB: " '("default") nil nil nil
			    'ein:gat-disksizegb-history (car ein:gat-disksizegb-history)))
	   if (string= answer "default")
	   do (setq answer nil)
	   else
	   do (setq answer (string-to-number answer))
	   end
	   until (or (null answer) (> answer 0))
	   finally return answer))

(defun ein:gat-dockerfiles-state ()
  "Return cons of (pre-Dockerfile . post-Dockerfile).
Pre-Dockerfile is Dockerfile.<notebook> if extant, else Dockerfile."
  (-if-let* ((default-directory (ein:gat-where-am-i))
             (notebook (ein:get-notebook))
	     (notebook-name (ein:$notebook-notebook-name notebook))
	     (dockers (directory-files (file-name-as-directory default-directory)
				       nil "^Dockerfile")))
      (let* ((pre-docker-p (lambda (f) (or (string= f (format "Dockerfile.%s" (file-name-sans-extension notebook-name)))
					   (string= f "Dockerfile"))))
	     (pre-docker (seq-find pre-docker-p (sort (cl-copy-list dockers) #'string>)))
	     (post-docker-p (lambda (f) (string= f (format "%s.gat" pre-docker))))
	     (post-docker (and (stringp pre-docker) (seq-find post-docker-p (sort (cl-copy-list dockers) #'string>)))))
	`(,pre-docker . ,post-docker))
    '(nil)))

(provide 'ein-gat)