;;; -*- mode: lisp; syntax: common-lisp; coding: utf-8; package: cl-inotify; -*-

;; Copyright (c) 2011, Olof-Joachim Frahm
;; All rights reserved.

;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions are met:
;;     * Redistributions of source code must retain the above copyright
;;       notice, this list of conditions and the following disclaimer.
;;     * Redistributions in binary form must reproduce the above copyright
;;       notice, this list of conditions and the following disclaimer in the
;;       documentation and/or other materials provided with the distribution.
;;     * The name of the author may not be used to endorse or promote products
;;       derived from this software without specific prior written permission.

;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;; ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
;; (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
;; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
;; ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
;; THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(in-package #:cl-inotify)

(defbitfield (inotify-flag :uint32)
  (:access        #.in-access)
  (:modify        #.in-modify)
  (:attrib        #.in-attrib)
  (:close-write   #.in-close-write)
  (:close-nowrite #.in-close-nowrite)
  (:close         #.in-close)
  (:open          #.in-open)
  (:moved-from    #.in-moved-from)
  (:moved-to      #.in-moved-to)
  (:move          #.in-move)
  (:create        #.in-create)
  (:delete        #.in-delete)
  (:delete-self   #.in-delete-self)
  (:move-self     #.in-move-self)
  (:unmount       #.in-unmount)
  (:q-overflow    #.in-q-overflow)
  (:ignored       #.in-ignored)
  (:onlydir       #.in-onlydir)
  (:dont-follow   #.in-dont-follow)
  (:mask-add      #.in-mask-add)
  (:isdir         #.in-isdir)
  (:oneshot       #.in-oneshot)
  (:all-events    #.in-all-events))

(deftype inotify-add/read-flag ()
  "Shared valid flags for the WATCH-RAW and READ-EVENT functions."
  '(member
    :access :attrib 
    :close-write :close-nowrite :close
    :create :delete :delete-self
    :modify
    :move-self :moved-from :moved-to :move
    :open :all-events))

(deftype inotify-read-flag ()
  "Valid flags which are returned from READ-EVENT."
  '(or inotify-add/read-flag
    (member :ignored :isdir :q-overflow :unmount)))

(deftype inotify-add-flag ()
  "Valid flags for the WATCH-RAW function."
  '(or inotify-add/read-flag
    (member :dont-follow :mask-add :oneshot :onlydir)))

(defun valid-watch-flag-p (x)
  (and (typep x 'inotify-add-flag)
       (not (eq :mask-add x))
       (not (eq :oneshot x))))

(defun valid-watch-flag-list-p (list)
  (every #'valid-watch-flag-p list))

(deftype watch-flag-list ()
  "Valid flags argument for the WATCH function, a list of keywords from
INOTIFY-ADD-FLAG.  Basically only :MASK-ADD and :ONESHOT are removed.
The :MASK-ADD behaviour is replicated with the REPLACE-P argument; the
:ONESHOT behaviour doesn't play well with the WATCH function design (and
thus should be used only with WATCH-RAW)."
  '(or (satisfies valid-watch-flag-p)
       (and list (satisfies valid-watch-flag-list-p))))

(defcfun ("inotify_init" c-inotify-init) :int
  "Initialises a new inotify event queue.")

(defcfun ("inotify_add_watch" c-inotify-add-watch) :int
  "Watches a path on a event queue."
  (fd :int)
  (pathname :string)
  (mask inotify-flag))

(defcfun ("inotify_rm_watch" c-inotify-rm-watch) :int
  "Removes a watched path from a event queue."
  (fd :int)
  (wd :int))

(binary-types:define-signed int #.(cffi:foreign-type-size :int))

(binary-types:define-binary-struct inotify-event ()
  "An inotify native event structure.
WD is the watch/file descriptor,
MASK is the (parsed) combination of events,
COOKIE is a unique integer which connects related events,
NAME optionally identifies a file relative to a watched directory."
  (wd 0 :binary-type int)
  (mask 0 :binary-type binary-types:u32)
  (cookie 0 :binary-type binary-types:u32)
  (name NIL))

(defstruct (inotify-instance
	     (:constructor make-inotify-instance ())
	     (:conc-name inotify-))
  "Contains the stream and file descriptor for a inotify instance."
  fd
  stream
  nonblocking)

;;;; initialisation and stuff

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun read-new-value (&optional (stream *query-io*))
    "READs a value from the STREAM and returns it (wrapped in a list)."
    (format stream "Enter a new value: ~%")
    (list (read *query-io*))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun init-endian ()
    "Initialises the endianess for the BINARY-TYPES library.  Is automatically
called when the library is loaded."
    (setf binary-types:*endian*
	  (restart-case #+little-endian :little-endian
			#+big-endian :big-endian
			#-(or little-endian big-endian) (error "unknown endianess")
			(use-value (value)
			  :report "Enter a correct value (either :LITTLE-ENDIAN or :BIG-ENDIAN)."
			  :interactive read-new-value
			  ;; TODO: better way to test for correct value/retry values?
			  (case value
			    ((:little-endian :big-endian) value)
			    (T (error "wrong value supplied (not :LITTLE-ENDIAN or :BIG-ENDIAN)"))))))))

;; initialise the endianess
(eval-when (:compile-toplevel :load-toplevel :execute)
  (init-endian))

;;;; basic wrapping of the API

(defun read-raw-event-from-stream (stream)
  "Reads a raw event from the inotify stream."
  (let* ((event (binary-types:read-binary 'inotify-event stream))
	 (len (binary-types:read-binary 'binary-types:u32 stream)))
    (when (plusp len)
      (with-slots (name) event
	(let ((buffer (make-array len :element-type '(unsigned-byte 8))))
	  (read-sequence buffer stream :end len)
	  (setf name (trivial-utf-8:utf-8-bytes-to-string buffer :end (position 0 buffer))))))
    event))

(defun read-event-from-stream (stream)
  "Reads a event from the inotify stream and converts bitmasks on reading."
  (let ((event (read-raw-event-from-stream stream)))
    (with-slots (mask) event
      (setf mask (foreign-bitfield-symbols 'inotify-flag mask)))
    event))

(defun set-nonblocking (fd nonblocking)
  "Enables or disables NONBLOCKING mode on a file descriptor FD."
  (let ((flags (sb-posix:fcntl fd sb-posix:f-getfl)))
    ;; an error is raised if this fails, so we don't have to do it ourselves
    (sb-posix:fcntl fd sb-posix:f-setfl
		    (funcall (if nonblocking #'logior #'logxor)
			     flags sb-posix:o-nonblock)))
  (values))

(defun init-unregistered-inotify (inotify &optional (nonblocking T))
  "Creates a new inotify event queue.  If NONBLOCKING is set (default),
the file descriptor is set to non-blocking I/O."
  (let ((result (c-inotify-init)))
    (when (minusp result)
      (perror "inotify_init failed"))
    (with-slots (fd stream (non-block nonblocking)) inotify
      (unwind-protect
	   ;; file descriptor is collected with auto-close
	   (progn
	     (setf fd result)
	     (when nonblocking
	       (set-nonblocking fd T)
	       (setf non-block nonblocking))
	     (setf stream
		   (sb-sys:make-fd-stream
		    fd
		    :input T
		    :element-type '(unsigned-byte 8)
		    :name (format NIL "inotify event queue ~A" fd)
		    :auto-close T
		    :buffering (if nonblocking :none :full))))
	;; if stream is constructed, gc'ing it will cleanup the file descriptor
	(unless stream
	  (sb-posix:close fd)))))
  inotify)

(defun make-unregistered-inotify ()
  "Creates a new unregistered INOTIFY instance."
  (init-unregistered-inotify (make-inotify-instance)))

(defun close-inotify (inotify)
  "Closes the inotify event queue."
  (close (inotify-stream inotify))
  (values))

(defun perror (prefix-string)
  #+sbcl (sb-int:simple-perror prefix-string)
  #-(or sbcl) (error prefix-string))

(defun ensure-list (arg)
  (if (listp arg) arg `(,arg)))

(defun translate-keyword-flags (flags)
  (typecase flags
    ((or keyword list)
     (foreign-bitfield-value 'inotify-flag (ensure-list flags)))
    (T flags)))

(defun watch-raw (inotify pathname flags)
  "Adds PATHNAME (either of type PATHNAME or STRING) to be watched.  FLAGS
determines how exactly (see inotify(7) for detailed information) and can
be of type LIST, KEYWORD or a raw numerical value (which isn't checked
for validity though).  Returns a handle which can be used with UNWATCH-RAW."
  (let* ((path (etypecase pathname
		 (string pathname)
		 (pathname (namestring pathname))))
	 (result (c-inotify-add-watch (inotify-fd inotify)
				      path (translate-keyword-flags flags))))
    (when (minusp result)
      (perror "inotify_add_watch failed"))
    result))

(defun unwatch-raw (inotify handle)
  "Stops watching the path associated with a HANDLE established by WATCH-RAW."
  (let ((result (c-inotify-rm-watch (inotify-fd inotify) handle)))
    (when (minusp result)
      (perror "inotify_rm_watch failed")))
  (values))

;;;; support functions, making life easier

(defstruct (registered-inotify-instance
	     (:include inotify-instance)
	     (:constructor make-registered-inotify-instance ())
	     (:conc-name inotify-))
  "Additionally to the information in INOTIFY-INSTANCE, records watched
paths in a dictionary."
  watched)

(defun make-inotify (&optional (nonblocking T))
  "Creates a new registered INOTIFY instance.  In NONBLOCKING mode, the file
descriptor is set to non-blocking mode.  The resulting object has to be
closed with CLOSE-INOTIFY."
  (let ((result (make-registered-inotify-instance)))
    (init-unregistered-inotify result nonblocking)
    (with-slots (watched) result
      (setf watched (make-hash-table :test 'equal)))
    result))

(defun pathname-handle/flags (inotify pathname)
  "Returns a CONS cell with the values HANDLE and FLAGS if PATHNAME is
being watched by INOTIFY, else NIL.  The match is exact."
  (gethash pathname (inotify-watched inotify)))

(defun event-pathname/flags (inotify event &optional (handle (slot-value event 'wd)))
  "Returns two values PATHNAME and FLAGS for an EVENT which were used during
registration.  If HANDLE is specified EVENT is ignored."
  (block NIL
    (maphash (lambda (pathname entry)
	       (when (eql (car entry) handle)
		 (return (values pathname (cdr entry)))))
	     (inotify-watched inotify))))

(defun sane-user-flags (inotify pathname flags &key (replace-p T))
  (check-type flags watch-flag-list)
  ;; now, :mask-add can't be member of flags
  ;; merge the flags
  (let* ((flags (ensure-list flags))
	 (rep-flags (if replace-p
			(cons :mask-add flags)
			flags)))
    (let ((it (gethash pathname (slot-value inotify 'watched))))
      (if it
	  (union (cdr it) rep-flags :test #'eq)
	  rep-flags))))

(defun watch (inotify pathname flags &key (replace-p T))
  "Adds PATHNAME (either pathname or string) to be watched and records the
watched paths.  FLAGS (a list of keywords) determines how exactly (see
inotify(7) for detailed information).  Returns a handle which can be used
with UNWATCH and EVENT-PATHNAME/FLAGS.  If REPLACE-P is set to T (default),
the flags mask is replaced rather than OR-ed to the current mask (if it
exists).  The :MASK-ADD flag is therefore removed from the FLAGS argument."
  (let* ((flags (sane-user-flags inotify pathname flags :replace-p replace-p))
	 (handle (watch-raw inotify pathname flags)))
    (with-slots (watched) inotify
      (setf (gethash pathname watched) (cons handle flags)))
    handle))

(defun unwatch (inotify &key pathname event handle)
  "Disables watching the path associated with the supplied HANDLE (which
may be one from a given EVENT) or PATHNAME."
  (unless (or pathname event handle)
    (error "either PATHNAME, EVENT or HANDLE have to be specified"))
  (when event
    (setf handle (slot-value event 'wd)))
  (if handle
      (unwatch-raw inotify handle)
      (let ((handle (car (pathname-handle/flags inotify pathname))))
	(unless handle
	  (error "PATHNAME ~S isn't being watched" pathname))
	;; remove even if unwatch-raw throws an error (which can happen if :oneshot is specified)
	(remhash pathname (inotify-watched inotify))
	(unwatch-raw inotify handle)))
  (values))

(defun list-watched (inotify)
  "Returns a LIST of all watched pathnames in no particular order."
  (loop
    for pathname being each hash-key in (inotify-watched inotify)
    collect pathname))

(defun unix-eagain-p (fd-stream)
  "Returns T on a FD-STREAM if trying to read from the stream raised a
EAGAIN error."
  (multiple-value-bind (result error)
      (sb-unix:unix-read (sb-sys:fd-stream-fd fd-stream) NIL 0)
    (declare (ignore result))
    (= error sb-unix:eagain)))

(defun event-available-p (inotify)
  "Returns T if an event is available on the queue."
  (if (inotify-nonblocking inotify)
      (not (unix-eagain-p (inotify-stream inotify)))
      (listen (inotify-stream inotify))))

(defun read-event (inotify)
  "Reads an event from the queue.  Blocks if no event is available."
  (read-event-from-stream (inotify-stream inotify)))

(defun next-event (inotify)
  "Reads an event from the queue.  Returns NIL if none is available."
  (when (event-available-p inotify)
    (read-event inotify)))

(defmacro do-events ((var inotify &key blocking-p) &body body)
  "Loops BODY with VAR bound to the next events retrieved from INOTIFY.
The macro uses NEXT-EVENT, so reading an event won't block and the loop
terminates if no events are available."
  (check-type var symbol)
  (let ((inotify-sym (gensym)))
   `(loop
      with ,var and ,inotify-sym = ,inotify
      ,.(unless blocking-p
	  `(while (event-available-p ,inotify-sym)))
      do (progn
	   (setf ,var (read-event ,inotify-sym))
	   ,.body))))

(defun next-events (inotify)
  "Reads all available events from the queue.  Returns a LIST of events."
  (loop
    while (event-available-p inotify)
    collect (read-event inotify)))
