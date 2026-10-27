# chimera-core-tic80

A core for [Chimera](https://github.com/ToolAssisted-run/chimera), the
frontend for tool-assisted speedruns, for the fantasy computer
**[TIC-80](https://tic80.com)**. It is built on TIC-80's own source and
produces one file, `tic80.chimeraCore`, that goes in Chimera's `cores`
folder.

## Status

New, and not published yet.

- Carts run in every language TIC-80 has except Ruby: Lua, MoonScript,
  Fennel, YueScript, JavaScript, Squirrel, Scheme, Wren, WebAssembly, Janet,
  Python, MiniScript and Forth. TIC-80's demo cart of each runs, and the
  sandboxed core gives the same results as a plain native build.
- Tried: those demo carts and the core's own test cart, on Linux and, in
  Chimera's headless runner, on Windows (the same memory on both). No game
  from tic80.com has been tried yet.
- Not there: Ruby (its build needs Ruby's own tools), and TIC-80's editors,
  console and game browser: the core is the machine that runs a cart.

## What you bring

A cart: a `.tic` file, or a `.png` cart (a picture with the cart inside, as
tic80.com offers them). Nothing else is needed.

## Buttons and settings

- **Gamepads**: P1 to P4, each with Up, Down, Left, Right, A, B, X and Y.
- **The mouse**: Mouse X and Mouse Y say where it is on the picture, and
  Mouse Left, Middle and Right are its buttons. A cart that asks for the
  mouse's movement instead reads Mouse Move X and Y. Scroll X and Y are the
  wheel.
- **The keyboard**: TIC-80's 94 keys, under their names. A cart sees four
  keys at once, as in TIC-80.
- **Settings**: Starting Clock (the date a cart reads with `tstamp()`;
  movies need the same value), Picture (the whole picture with its border,
  or the screen alone) and Mouse Cursor (drawn or not).

What a cart saves with `pmem()` is its save data: Emulator > Export Save Data
writes it as a `.pmem` file, and a project can start from one.

RAM Watch and RAM Search read TIC-80's 96 KB of memory as a cart's `peek()`
sees it.

## Building and testing

[docs/BUILDING.md](docs/BUILDING.md) has every step. [docs/PLAN.md](docs/PLAN.md)
is the design log: what was decided, why, and what was measured.

## Licence

This repository's own code is MIT, and so is TIC-80. The languages and
libraries TIC-80 carries are under their own licences, all permissive except
the sound resampler blip_buf (LGPL 2.1 or later). The package carries every
licence text. See [LICENSE](LICENSE).
