;;;; restas-daemon.lisp
;;;;
;;;; Usage:
;;;; sbcl --noinform --no-userinit --no-sysinit --load /path/to/restas-daemon.lisp /path/to/daemon.conf COMMAND
;;;; where COMMAND one of: start stop zap kill restart nodaemon
;;;;
;;;; If successful, the exit code is 0, otherwise 1
;;;;
;;;; Error messages look in /var/log/messages (usually, depend on syslog configuration)
;;;;
;;;; This file is part of the RESTAS library, released under Lisp-LGPL.
;;;; See file COPYING for details.
;;;;
;;;; Author: Moskvitin Andrey <archimag@gmail.com>

(setf sb-impl::*default-external-format* :utf-8)

(defpackage #:sbcl.daemon
  (:use #:cl
        #:sb-alien
        #:sb-ext))

(in-package #:sbcl.daemon)

(defvar *daemon-config-pathname* (second *posix-argv*))
(defvar *daemon-command* (third *posix-argv*))

(defparameter *as-daemon* (not (string= *daemon-command* "nodaemon")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; aux
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun finish (&key exit-code)
                                        ;  (if (string> (lisp-implementation-version) "1.0.56.55")
                                        ;     (sb-ext:exit :code exit-code)
  (sb-ext:quit :unix-status exit-code)
                                        ;      )
  )


(defmacro with-exit-on-error (&body body)
  `(if *as-daemon*
       (handler-case (progn ,@body)
         (error (err)
           (with-output-to-string (*standard-output*)
             (let ((*print-escape* nil))
               (print-object err *error-output*)
               (write #\Newline :stream *error-output*)
               (finish :exit-code 1)))))
       (progn ,@body)))

(defmacro with-silence (&body body)
  `(with-output-to-string (*trace-output*)
     (with-output-to-string (*standard-output*)
       ,@body)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; basic parameters
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defpackage #:sbcl.daemon.preferences
  (:use #:cl)
  (:export #:*name*
           #:*user*
           #:*group*
           #:*fasldir*
           #:*logdir*
           #:*pidfile*
           #:*swankport*
           #:*default-host-redirect*
           #:*asdf-central-registry*
           #:*quicklisp-home*
           #:*asdf-load-systems*
           #:*sites*))

(with-exit-on-error
  (let ((*package* (find-package '#:sbcl.daemon.preferences)))
    (load *daemon-config-pathname*)))

(defmacro defpref (name &optional default)
  `(with-exit-on-error
     (defparameter ,name
       (let ((symbol (find-symbol (symbol-name ',name) '#:sbcl.daemon.preferences)))
         (if (boundp symbol)
             (symbol-value symbol)
             ,default)))))

(defpref *name* (error "The param *name* is unbound"))

(defpref *user* *name*)

(defpref *group*)

(defpref *fasldir*
    (make-pathname :directory (list :absolute "var" "cache" *name* "fasl")))

(defpref *logdir*
    (make-pathname :directory (list :absolute "var" "log" *name*)))

(defpref *pidfile* (format nil "/var/run/~A/~A.pid" *name* *name*))

(defpref *swankport*)

(defpref *asdf-central-registry*)

(defpref *quicklisp-home*)

(defpref *asdf-load-systems*)

(defpref *sites*)

(defpref *default-host-redirect*)

(defpref *acceptor-class*)

(delete-package '#:sbcl.daemon.preferences)

;;; set fasl dir

(require 'asdf)

;(break "~A" asdf::*user-cache*)

(setf asdf::*user-cache* *fasldir*)
;(setf asdf::*system-cache* asdf::*user-cache*)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Create necessary directories
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(with-silence
  (require 'sb-posix))

(ensure-directories-exist *fasldir*)
(ensure-directories-exist *pidfile*)
(ensure-directories-exist *logdir*)

(let ((uid (sb-posix:passwd-uid (sb-posix:getpwnam *user*)))
      (gid (if *group*
               (sb-posix:group-gid (sb-posix:getgrnam *group*))
               (sb-posix:passwd-gid (sb-posix:getpwnam *user*)))))
  (sb-posix:chown *fasldir* uid gid)
  (sb-posix:chown *logdir* uid gid)
  (sb-posix:chown (directory-namestring *pidfile*) uid gid))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Processing command line arguments
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; command-line COMMAND

;;;; quit if COMMAND is unknown

(unless (find *daemon-command* '("start" "stop" "zap" "kill" "restart" "nodaemon") :test #'string-equal)
  (with-exit-on-error
    (error "RESTAS-DAEMON: Bad command-line options. Want start, stop, zap, kill, restart or nodaemon.")))

;;;; zap - remove pid file

(when (string-equal *daemon-command* "zap")
  (with-exit-on-error
    (delete-file *pidfile*)
    (finish :exit-code 0)))

;;;; stop - send to daemon sigusr1 signal, wait and remove pid file

(defun read-pid ()
  (with-open-file (in *pidfile*)
    (read in)))

(defun stop-daemon ()
  (sb-posix:syslog sb-posix:log-daemon "Stopping '~A' daemon..." *name*)
  (let ((pid (read-pid)))
    (sb-posix:kill pid sb-posix:sigusr1)
    (loop
       while (not (null (ignore-errors (sb-posix:kill pid 0))))
       do (sleep 0.1)))
  (delete-file *pidfile*)
  (sb-posix:syslog sb-posix:log-daemon "Daemon '~A' stopped." *name*))

(when (string-equal *daemon-command* "stop")
  (with-exit-on-error
    (stop-daemon)
    (finish :exit-code 0)))

;;;; kill - send to daemon kill signal and remove pid file

(when (string-equal *daemon-command* "kill")
  (with-exit-on-error
    (sb-posix:kill (read-pid)
                   sb-posix:sigkill)
    (delete-file *pidfile*)
    (finish :exit-code 0)))

;;;; restart daemon

(when (string-equal *daemon-command* "restart")
  (with-exit-on-error
    (stop-daemon)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; load asdf/quicklisp
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(loop
   for path in *asdf-central-registry*
   do (push path asdf:*central-registry*))

(when *quicklisp-home*
  (load (merge-pathnames "setup.lisp" *quicklisp-home*)))

(asdf:load-system :sb-daemon)

(defpackage :swank-loader
  (:use :cl)
  (:export :init
           :dump-image
           :*source-directory*
           :*fasl-directory*))

(when *swankport*
  (when *fasldir*
    (defparameter swank-loader:*fasl-directory* *fasldir*))
(asdf:oos 'asdf:load-op :swank))

(asdf:operate 'asdf:load-op '#:restas)

(loop
   for system in *asdf-load-systems*
   do (asdf:operate 'asdf:load-op system))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;
;;;; Start daemon!
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun signal-handler (signal)
  ;(format t "~A received~%" signal)
  (sb-posix:syslog sb-posix:log-daemon "~A received~%" signal)
  (finish :exit-code 0))

(when *as-daemon*)

(when *as-daemon*
  (sb-posix:syslog sb-posix:log-daemon "Starting '~A' daemon... ~A" *name* *user*)
  (if (probe-file *pidfile*)
      (progn
        (warn "RESTAS-DAEMON: PID file found. Already run?")
        (finish :exit-code 1))

      #| Daemonize! |#
      (sb-daemon:daemonize
       :exit-parent t
       :pidfile *pidfile*
       :disable-debugger t
       :output (merge-pathnames "stdout.log" *logdir*)
       :error  (merge-pathnames "stderr.log" *logdir*)
       :sigabrt 'signal-handler
       :sigterm 'signal-handler
       :sigint  'signal-handler
       :user *user*)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; start swank server
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(when *swankport*
  (setf swank:*use-dedicated-output-stream* nil)
  (swank:create-server :port *swankport*
                       :dont-close t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Start restas server
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(setf (symbol-value (read-from-string "restas:*default-host-redirect*"))
      *default-host-redirect*)

(loop
   for site in *sites*
   do (if (consp site)
          (apply #'restas:start
		 (first site)
                                        ;         :acceptor-class (if *acceptor-class* (read-from-string *acceptor-class*))
		 :hostname (second site)
		 :port (third site)
		 (let* ((ssl-files (fourth site)))
		   (list :ssl-certificate-file (first ssl-files)
			 :ssl-privatekey-file (second ssl-files)
			 :ssl-privatekey-password (third ssl-files))))
          (restas:start site)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; end daemon initialize
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(when *as-daemon*
  (sb-posix:syslog sb-posix:log-daemon "Daemon '~A' started." *name*))

(when *as-daemon*
  (loop
     (sleep 10)))
