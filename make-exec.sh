#!/bin/sh
sbcl --no-sysinit --load speed-up-gif.lisp --eval \
    "(sb-ext:save-lisp-and-die \"speed-up-gif\" :toplevel #'main :executable t)"
