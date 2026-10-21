#!/usr/bin/env python3
"""Writes a TIC-80 cart (.tic) whose program is a small test of the controls,
the clock and the save memory for the TIC-80 core's tests. It needs no file
of anyone's.

usage: make-tic80-cart.py <out.tic> [nopad | relative | error | banks]

The cart is in Lua. Every frame it:
  - counts its frames in the long word at $8000 (the map's memory, which it
    never draws);
  - writes the 32 gamepad buttons, btn(0) to btn(31), as bits of $8004 to
    $8007, and the 94 keys, key(1) to key(94), as bits of $8008 to $8013;
  - writes mouse(): x and y as signed words at $8014 and $8016, then the
    left, middle and right buttons and the scroll x and y, a byte each, at
    $8018 to $801C;
  - writes time() (milliseconds) at $8020, tstamp() (seconds) at $8024 and
    a number from math.random(0, 255) at $8028;
  - counts its frames in pmem(0), its save memory;
  - clears the screen to a colour that changes with the frame, prints the
    count, and plays a square wave whose pitch changes every 30 frames.
With "nopad" it reads no control, so every frame is a lag frame; it does
map P1's first button to the Z key (the gamepad mapping at $14E04), so the
machine itself looks at that key every frame, and that look must not count
as the cart's. With
"relative" it asks for the mouse's movement instead of its place (TIC-80's
relative mode: bit 7 of $FF87). With "error" its code stops with an error
on the first frame. With "banks" it clears the second video bank's cursor
($3FFB) and ends every other frame with that bank active, as a cart that
draws two layers may (Hollow Knight Demake, chimera#318).
"""
import struct
import sys

CHUNK_CODE = 5
CHUNK_DEFAULT = 17


def chunk(kind, data, bank=0):
    return struct.pack("<BHB", kind | (bank << 5), len(data), 0) + data


def program(variant):
    reads = """
  local pads = 0
  for i = 0, 31 do if btn(i) then pads = pads | (1 << i) end end
  for b = 0, 3 do poke(0x8004 + b, (pads >> (8 * b)) & 255) end
  for b = 0, 11 do
    local v = 0
    for k = 0, 7 do
      local code = b * 8 + k + 1
      if code <= 94 and key(code) then v = v | (1 << k) end
    end
    poke(0x8008 + b, v)
  end
  local x, y, l, m, r, sx, sy = mouse()
  poke(0x8014, x & 255) poke(0x8015, (x >> 8) & 255)
  poke(0x8016, y & 255) poke(0x8017, (y >> 8) & 255)
  poke(0x8018, l and 1 or 0) poke(0x8019, m and 1 or 0) poke(0x801A, r and 1 or 0)
  poke(0x801B, sx & 255) poke(0x801C, sy & 255)
"""
    start = ""
    if variant == "nopad":
        reads = ""
        start = "  poke(0x14E04, 26)\n"
    if variant == "relative":
        start = "  poke(0x7FC3F, 1, 1)\n"
    if variant == "error":
        start = "  error('the test cart stops here')\n"
    banks = ""
    if variant == "banks":
        # the second bank's cursor byte cleared ($3FFB: no cursor), as a cart
        # that keeps a layer there may leave it
        banks = "  vbank(1) poke(0x3FFB, 0) vbank(n % 2)\n"
    return """-- title:  chimera test
-- author: chimera-core-tic80
-- script: lua

local n = 0

local function put32(addr, v)
  for b = 0, 3 do poke(addr + b, (v >> (8 * b)) & 255) end
end

function TIC()
%s  n = n + 1
  put32(0x8000, n)
%s  put32(0x8020, math.floor(time()))
  put32(0x8024, tstamp())
  poke(0x8028, math.random(0, 255))
  pmem(0, pmem(0) + 1)
  cls(n %% 16)
  print("frame " .. n, 84, 64, 12)
  -- a square wave on the first sound channel ($FF9C: frequency and
  -- volume in a word, then 32 four-bit samples), its pitch moving every
  -- 30 frames
  local f = 220 + ((n // 30) %% 4) * 55
  poke(0xFF9C, f & 255) poke(0xFF9D, ((f >> 8) & 15) | (10 << 4))
  for i = 0, 15 do poke(0xFF9E + i, i < 8 and 0 or 255) end
%send
""" % (start, reads, banks)


def main():
    out = sys.argv[1]
    variant = sys.argv[2] if len(sys.argv) > 2 else ""
    code = program(variant).encode()
    # the default chunk gives the cart TIC-80's standard palette and waveforms
    data = chunk(CHUNK_DEFAULT, b"") + chunk(CHUNK_CODE, code)
    open(out, "wb").write(data)
    print("%s: %d bytes of Lua%s" % (out, len(code), (" (%s)" % variant) if variant else ""))


if __name__ == "__main__":
    main()
