#!/bin/sh
# Writes janet.c, the whole Janet language in one C file, the way TIC-80's
# own build gets it: Janet's Makefile builds a small Janet with the build
# machine's compiler and has it write the file. It is done on a copy of
# Janet's folder, so the submodule stays as it is.
#
# usage: make-janet.sh <Janet's folder> <janet.c to write> <work folder>
set -eu
src="$1"
out="$2"
work="$3"
rm -rf "$work"
mkdir -p "$work"
cp -r "$src/." "$work/"
rm -rf "$work/build"
# JANET_BUILD is the build's name inside janet.c; without it the Makefile
# asks git, which would answer with this repository's commit
make -s -C "$work" CC="${CC_FOR_BUILD:-cc}" JANET_BUILD='"\"tic80\""' build/c/janet.c >/dev/null
cp "$work/build/c/janet.c" "$out"
