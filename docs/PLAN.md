# Design log

What was decided for this core, why, and what was measured. Newest last.

## 2026-10-14: TIC-80 through its own embedding API

**Decided.** The core is built from TIC-80's main branch (nesbox/TIC-80
3801892c, 2026-10-14), its own code throughout. BizHawk has a TIC-80 core;
it was read for ideas only, and nothing was taken from it (the owner's
instruction for the cores of this round).

TIC-80 has a libretro core in its tree, but also a small API for a program
that embeds it (`include/tic80.h`: create, load, tick, sound). The core
uses that API, not the libretro layer: the libretro layer adds a mouse
emulated from a joypad, a frame-time callback and a pointer drawn by
itself, none of which a movie wants, and the API is what TIC-80's own
player uses. `waterbox/cinterface.c` is that program.

**What is built.** The machine and thirteen languages: Lua, MoonScript,
Fennel, YueScript, JavaScript (QuickJS), Squirrel, Scheme (s7), Wren,
WebAssembly (wasm3), Janet, Python (pocketpy), MiniScript and Forth
(pForth), each a library with the files and flags upstream's CMake gives it
(read from its `compile_commands.json`, docs/BUILDING.md). Ruby (mruby) is
left out: its build runs Ruby's own `rake`, which neither this machine nor
the CI runner has. A Ruby cart is refused by name ("written in ruby"), where
TIC-80 would have run it as Lua and failed.

Left out on purpose: the network client (naett), the editors, console and
game browser (the studio), and the capture of the computer's sound for a
cart's `fft()` (`TIC80_FFT_UNSUPPORTED`: TIC-80 turns that on only with its
`--fft` option, and a machine in a movie may not hear the room).

**Carts.** `.tic` and `.png`, what TIC-80's free build loads. Text carts
(`.lua` and the like) load only in TIC-80 PRO, which its author sells; the
licence would allow the core to load them, and it does not, by the same
choice upstream's free build makes. A decision the owner may revisit.

**The clock.** TIC-80's `time()` is milliseconds from a counter the program
gives it; the core's counter is the frames run (1000 a frame, 60000 a
second), so `time()` is exactly frame / 60 seconds. `tstamp()`, Lua's string
hash seed, and the languages' random seeds read the C library's clocks, so
the core defines `time`, `gettimeofday`, `clock_gettime`, `timespec_get`,
`clock` and `localtime(_r)`: the Starting Clock setting plus the frames
run. Measured: `time()` is 4983 in the 300th frame, `tstamp()` 946684804
with the default and 1234567894 with 1234567890 (`tic:clock`).

**The same numbers in both builds.** Lua's `math.random` and Squirrel's
`rand()` call the C library's `rand()`, which is glibc's in the native build
and musl's in the sandbox; the core defines `rand`/`srand` as musl has them.
s7 saves the signal mask around its errors with `sigsetjmp`, which the
sandbox's C library does not have; it is given `setjmp` in both builds (the
sandbox has no signals). With these, the native and sandbox runs print the
same digests for the test cart and for every language's demo; WebAssembly's
runtime prints a pointer when it starts, which differs, and nothing else.

**Controls.** Four gamepads of eight buttons, the mouse's three buttons, the
94 keys, and six axes. Every control is live whatever the cart's `input`
tag says: TIC-80's machine passes them all to a cart, and a cart that
declares the gamepad may still read a key. A cart sees four keys at once
(TIC80_KEY_BUFFER); held beyond that, the first four in key order.

Mouse X and Y are the mouse's place as a fraction of the picture shown,
0 to 65535 (the spelling Chimera's newer cores use for a place on the
screen), turned into TIC-80's pixel the core's own way:
`pixel = axis * width / 65536`, plus the border when the picture is the
screen alone. A cart can ask for the mouse's movement instead (TIC-80's
relative mode, a bit it sets in its own memory); the core then gives Mouse
Move X and Y, a separate pair, so that a movie never makes movement out of
two places. Scroll X and Y are the wheel's turn, -32 to 31 as TIC-80 holds
them.

**Lag frames.** Patch 0001 counts every look at the controls: `btn`,
`btnp`, `key`, `keyp`, `mouse`, and a `peek` or `memcpy` of the bytes the
controls are kept in. The machine's own look at the keys for the gamepad
mapping (`tic_core_tick_io`) is taken back out. A frame with no look is a
lag frame. Measured: the test cart has none in 300 frames, its twin that
reads nothing 300 (`tic:lag`).

**The picture.** TIC-80 draws 256x144: the 240x136 screen in a border that
carts draw on too. The Picture setting shows all of it ('full', the
default) or the screen alone. The mouse cursor is drawn on top when the cart
uses the mouse, as TIC-80's player does: the cart's sprite, or one of the
three arrows of TIC-80's built-in configuration cart
(`build/assets/config.tic.dat`, decompressed at start). It is drawn on the
picture only, never into the machine (`tic:picture`: hidden, the picture
differs and the memory does not).

**Save memory.** A cart's `pmem()` is 1 KB of TIC-80's memory (at $14004).
Export Save Data writes it as `<cart>.pmem` once it holds anything; a
project's save data slot loads it before the first frame. Measured: 300
after 300 frames, 400 after 100 more from the exported file
(`tic:save-data`).

**What was measured beside the test script.** The Lua demo and the test
cart were looked at as pictures: Sweetie 16's colours, the border, the
arrow cursor at the mouse's place. Chimera's window plays the test cart and
the Lua demo to the headless runner's memory (`tests/run-frontend.sh`, 3/0).
On Windows, Chimera's headless runner (`chimera-run.exe`) plays four
projects of 600 frames - the test cart with gamepad, key and mouse presses
and a Starting Clock of its own, and the Python, JavaScript and Scheme demos
with the figure moved - to the same memory as on Linux. Chimera's window was
tried on Linux only. Not tried: any cart from tic80.com.

## 2026-10-14: pForth's dictionary is made by the build

**Found.** A fresh clone did not build: `pfdicdat.h`, pForth's dictionary
as a C header, is not in pForth's repository. Upstream's CMake writes it
into pForth's source folder when it configures, and the working tree here
had it only because upstream's CMake had been run there to read its file
lists.

**Decided.** `waterbox/make-pforth-dic.sh` makes it, as upstream's CMake
does, on a copy of pForth's folder, and the build uses it. It loads
`system.fth` by a relative name where upstream's CMake gives the absolute
path, which pForth records in the dictionary: upstream's header carried the
folder it was built in, this one carries no path. Measured: the Forth demo
gives the same results as before (`lang:forth`), and a fresh clone builds.

## 2026-10-14: the same commit makes the same package

**Found.** Two builds of the same commit, in two folders, made different
`core.wbx` files: pForth and MiniScript print the day and time they were
compiled (`__DATE__`, `__TIME__`), and pForth's dictionary holds four
addresses of the program that wrote it, which differ from run to run with
the address space laid out at random.

**Decided.** Both macros are fixed for the whole build (`meson.build`), and
`waterbox/make-pforth-dic.sh` runs pForth with `setarch -R` (no random
layout) when the machine has it. Measured: a fresh clone and the working
tree make the same `core.wbx`, byte for byte, and the Forth demo gives the
same results as before.

## 2026-10-14: the default bindings name keys Chimera has

**Found.** 16 of the keys the package binds by default had names Chimera
does not give its keys: the digits ("0" for "Number0"), "Grave",
"LeftControl", "Return", "KeypadPlus", "KeypadMinus" and "KeypadPeriod".
Those controls shipped unbound. The window test checked only that Chimera
takes the package's bindings, not that the keys exist.

**Decided.** The names are Chimera's (its DistinctKey list and the names
DistinctKeyNameOverrides gives some keys), and a new test,
`package:key-names` (`tests/check-key-names.py`), reads that list from
Chimera's source and checks every binding against it. Measured: the old
bindings fail it with those 16 keys, the new ones pass.

## 2026-10-14: the modifier keys too

**Found.** Chimera hands a key to the bindings under one name only: the
name DistinctKeyNameOverrides gives it ("Number1", "Enter", "Backtick",
"KeypadAdd"), or else its DistinctKey name (Input.cs). By default it also
reads the left and right Shift, Ctrl and Alt as one key each, "Shift",
"Ctrl" and "Alt" (Config.MergeLAndRModifierKeys). A binding to any other
name never fires, so those controls shipped unbound.

**Decided.** The bindings use those names; where both keys of a modifier
were bound, the left one is on the merged key and the right one ships
unbound. The test `package:key-names` (`tests/check-key-names.py`) reads the
names from Chimera's source and checks every binding.

Measured: after the fix above, Key Ctrl, Key Shift and Key Alt were still on
LeftCtrl, LeftShift and LeftAlt, which a default setup never sends; they are
now on Ctrl, Shift and Alt.

**Changed the same day.** A modifier is bound under both names: the merged
one, which a default setup sends, and the side's own ("Shift, LeftShift";
the right key on "RightShift"), which fires when the merging is turned off,
as other cores already do. `package:key-names` accepts a left or right name
only when the merged one is bound too. Checked on Xvfb: with 1, Return, left
Shift and Up held, Chimera's window reports Number1, Enter, Shift and Up.

## The cursor is the first video bank's (chimera#318, 2026-10-20)

Hollow Knight Demake's mouse cursor showed on every other frame once Capture
Mouse hid Windows' own arrow. TIC-80 keeps the cursor in each video bank's
memory ($3FFB), and the core drew the one of the bank the frame ended on.
That cart draws two layers, background and foreground, in an order that
alternates frame by frame, so it ends every other frame on its second bank,
whose cursor byte is 0 (no cursor): measured at $3FFB, 0x80 (the system
arrow) on one frame and 0x00 on the next. TIC-80's own player reads the
active bank the same way; TIC-80 itself treats the cursor as one for both
banks when it switches for OVR.

The core now draws the first bank's cursor whichever bank is active. It is
the picture only: nothing of the machine changes, so no movie does.

Test: the test cart has a "banks" variant that clears its second bank's
cursor and ends every other frame on that bank; tic:cursor-banks holds that
each of 40 pictures differs from the same frame with Mouse Cursor 'hide'. On
the published core 20 of the 40 had no cursor. Hollow Knight Demake in play
(chimera-run, frames 1200 to 1207, the mouse still) has the arrow on every
frame.

## 2026-10-21: the keyboard in rows (chimera#337)

The 94 keys were listed in TIC-80's own code order (A to Z, 0 to 9, then the
rest). They are now listed as they sit on a keyboard, row by row from the
top (Escape and the F keys, the number row, the QWERTY row, the home row, the
Z row, then Ctrl, Alt and Space), then the keys beside the rows, the arrows
and the keypad: the table `kKeys` in `waterbox/cinterface.c`, which carries
each key's TIC-80 code, and the package follows it. A cart still sees at most
four keys at once, and with more held it sees the four with the lowest codes,
as before, so a project replays as it did. The gate checks each key against
its code. Measured: gate 41 of 41 (with the core sending list places instead
of codes, 3 failed); frontend 3 of 3.
