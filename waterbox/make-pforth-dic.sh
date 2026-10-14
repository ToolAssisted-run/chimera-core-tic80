#!/bin/sh
# Writes pfdicdat.h, pForth's standard dictionary as a C header, the way
# TIC-80's own build makes it (cmake/forth.cmake): pForth is built with the
# build machine's compiler, made to load its system words, and asked to
# write the header. It is done on a copy of pForth's folder, so the
# submodule stays as it is. The core is 64-bit, as the build machine is,
# which the dictionary must match.
#
# usage: make-pforth-dic.sh <pForth's folder> <pfdicdat.h to write> <work folder>
set -eu
src="$1"
out="$2"
work="$3"
rm -rf "$work"
mkdir -p "$work"
cp -r "$src/." "$work/"
rm -f "$work/csrc/pfdicdat.h" "$work/fth/pforth" "$work/fth/pforth.dic"
c="$work/csrc"
files=""
for f in $(grep '\.c$' "$c/sources.cmake"); do files="$files $c/$f"; done
# the stdio input and output TIC-80's bootstrap uses, in place of a console
${CC_FOR_BUILD:-cc} -O1 -w -DPF_SUPPORT_FP -I"$c" $files "$c/stdio/pf_fileio_stdio.c" "$c/stdio/pf_io_stdio.c" \
	"$c/pf_main.c" -lm -o "$work/fth/pforth"
# The dictionary keeps a few addresses of the program that wrote it. They
# mean nothing to the core (the Forth demo runs the same whatever they are),
# but with the address space laid out at random they differ from build to
# build, and so would the package: setarch -R lays it out the same way each
# time.
norandom=""
setarch "$(uname -m)" -R true 2> /dev/null && norandom="setarch $(uname -m) -R"
(cd "$work/fth" && $norandom ./pforth -i system.fth < /dev/null > /dev/null 2>&1)
(cd "$work/fth" && $norandom ./pforth mkdicdat.fth < /dev/null > /dev/null 2>&1)
[ -s "$work/fth/pfdicdat.h" ] || { echo "pForth did not write pfdicdat.h" >&2; exit 1; }
cp "$work/fth/pfdicdat.h" "$out"
