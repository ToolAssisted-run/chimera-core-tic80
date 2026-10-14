#!/usr/bin/env python3
"""Writes one of the carts TIC-80 carries in its source (build/assets/*.dat:
a C list of the bytes of a zlib-compressed cart) as a .tic file. The core's
tests use upstream's demo cart of each language this way.

usage: extract-demo.py <name.tic.dat> <out.tic>
"""
import re
import sys
import zlib

text = open(sys.argv[1]).read()
data = bytes(int(v, 16) for v in re.findall(r"0x([0-9a-fA-F]{2})", text))
open(sys.argv[2], "wb").write(zlib.decompress(data))
