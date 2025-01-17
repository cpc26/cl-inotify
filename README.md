CL-INOTIFY - Interface to the Linux inotify API.

Copyright (C) 2011 Olof-Joachim Frahm
Released under a Simplified BSD license.

Working, but unfinished.
Implementations currently running on: SBCL.

Uses CFFI, binary-types (from [my Github][1] or see [CLiki][2]) and
trivial-utf-8.  Doesn't use iolib, because we don't need most of the
functionality, although it might gain us some implementation
independence (patches which can be conditionally compiled are welcome).

A similar package is at [stassats Github][3].


# HOWTO

After loading the library use `MAKE-INOTIFY` to create a new event
queue.  The `NONBLOCKING` argument currently determines if we use the
standard `CL:LISTEN` function or `SB-UNIX:UNIX-READ` to check for
available events.

The result of `MAKE-INOTIFY` is used with `WATCH` and `UNWATCH`, the first
being used to watch a file or directory, the second to stop watching
it.  The `FLAGS` parameter of `WATCH` is described in the notify(7)
manpage; you can use a combination of the flags (as keywords) to create
a suitable bitmask.  The types `INOTIFY-ADD/READ-FLAG`,
`INOTIFY-READ-FLAG` and `INOTIFY-ADD-FLAG` are also defined and can be
examined.

For example, to watch for modified or closed files in a directory, call
`(WATCH inotify "foo/" '(:modify :close))`.

The result of `WATCH` is a handle (currently a `FIXNUM`, but I wouldn't
rely on that) which can be fed to `UNWATCH` and can be translated from
events with `EVENT-PATHNAME/FLAGS`.

To finally get the events from the queue, use `READ-EVENT` (which
blocks) or `NEXT-EVENT` (which doesn't block).  `EVENT-AVAILABLEP` does
what it should do, `NEXT-EVENTS` retrieves all currently available
events as a list and `DO-EVENTS` (nonblocking) iterates over available
events.

The enhanced API registers all watched paths in a hashtable, so you can
use `PATHNAME-HANDLE/FLAGS` to check if a pathname (exact match) is
being watched and `LIST-WATCHED` to return all watched paths as a list.
`EVENT-PATHNAME/FLAGS` may be used to get the pathname and flags for a
read event.

`UNWATCH` has to be called with the path or the handle of the watched
file or directory (a path will be looked up in the same table as with
`PATHNAME-HANDLE/FLAGS`). 


The raw API, which doesn't register watched paths, consists of
`READ-RAW-EVENT-FROM-STREAM`, `READ-EVENT-FROM-STREAM`, `WATCH-RAW` and
`UNWATCH-RAW`.  They are just a thin wrapper around the C functions, but
they're exported in case someone doesn't like the upper layers.


In case you want to use `epoll` or `select` on the event queue you can
access the file descriptor yourself and then use the normal functions
afterwards.  Currently no such functionality is integrated here.


# EXAMPLE

    > (use-package '#:cl-inotify)
    > (defvar *tmp*)
    > (setf *tmp* (make-notify))
    > (watch *tmp* "/var/tmp/" :all-events)
    > (next-events *tmp*)
    > (close-inotify *tmp*)


# TODO

- more functionality to examine read events
- extend to other APIs?
- make things more implementation independent
- (maybe) don't use the libc for this, direct syscall
- (maybe) add iolib replacement for io functions
- easier interface for (e)poll/select maybe using iolib (done, using
  CL:LISTEN and/or SB-UNIX:UNIX-READ)


LINKS

[1]: https://github.com/Ferada/binary-types
[2]: http://www.cliki.net/Binary-types
[3]: https://github.com/stassats/inotify