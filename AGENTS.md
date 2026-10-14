# AGENTS.md - TIC-80 core for Chimera

This repository builds TIC-80 (https://github.com/nesbox/TIC-80), the
fantasy computer, as a core for Chimera
(https://github.com/ToolAssisted-run/chimera), a frontend for tool-assisted
speedruns. It produces one file, `tic80.chimeraCore`: TIC-80 compiled to run
inside Chimera's sandbox (miniBox), a small program around it, and the
declarations Chimera reads (buttons, settings, file types).

Read [docs/BUILDING.md](docs/BUILDING.md) before building and
[docs/PLAN.md](docs/PLAN.md) before changing how the core works: it is the
design log, with what was decided, why, and what was measured.

## Layout

- `extern/tic80` - TIC-80 at a commit of its main branch, a submodule, with
  its own submodules (the languages) under `vendor/`. Never edited in place:
  a change is a numbered patch in `patches/`, laid over the submodule by
  `waterbox/apply-patches.sh` and written by `waterbox/make-patches.sh` (its
  list says which file is in which patch; a file is in one patch, whole).
  Every change is inside `#ifdef CHIMERA_CORE` with a comment that says why.
- `meson.build` - the build of both flavors: TIC-80's machine and each
  language as a library, with the files and flags upstream's CMake gives
  them, written down by hand.
- `waterbox/cinterface.c` - the program around TIC-80: it drives TIC-80's
  own embedding API (`include/tic80.h`), gives it the controls, keeps the
  clock, draws the mouse cursor, and is what Chimera's engine calls. It also
  defines the C library's time functions and `rand()`. The same file is
  compiled for the sandbox and for the host.
- `waterbox/make-janet.sh` - writes Janet's one-file source, as upstream's
  build does, from a copy of Janet's folder.
- `waterbox/guest-syscalls.c` - sandbox-only answers to "is this file there".
- `waterbox/waterbox.config`, `file_slots.json`, `default_keybinds.json`,
  `package-licenses.json` - what the package declares.
- `waterbox/run-native.c`, `waterbox/run-wbx.c` - the native runner and the
  sandbox runner. They take the same options and print the same lines
  (`waterbox/gate-harness.h` is the part they share).
- `waterbox/*.sh` - `apply-patches.sh`, `make-patches.sh`, `setup-guest.sh`
  (configures the sandbox build), `build-package.sh`, `run-gate.sh` (the
  test script).
- `tests/` - `make-tic80-cart.py` (writes the test cart), `extract-demo.py`
  (writes one of TIC-80's built-in carts as a .tic), `run-frontend.sh` (the
  window test, with its helpers), `make-project.py` (writes a project).
- `build/` - every build output, ignored by git.

## Build and test

```sh
git submodule update --init --recursive
meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest
waterbox/build-package.sh -r <chimera checkout>
CHIMERA_ROOT=<chimera checkout> bash waterbox/run-gate.sh
TMPDIR=$PWD/build/t bash tests/run-frontend.sh --chimera-root <chimera checkout>
```

Run both test scripts before every commit that touches what they cover, and
say in the commit what ran, with the numbers. A new test is broken on
purpose once and seen to fail.

## Rules of the repository

- **One thread, one clock.** TIC-80 runs a frame at a time on one thread.
  The core defines `time`, `gettimeofday`, `clock_gettime`, `timespec_get`,
  `clock`, `localtime` and `localtime_r`: the time is the Starting Clock
  setting plus the frames run, at 60 a second. TIC-80's `time()` and
  `tstamp()` and the languages' random seeds all come from it. The test
  `tic:clock` holds it.
- **The same numbers in both builds.** `rand()` is defined in the core (as
  the sandbox's C library has it), because Lua and Squirrel use it and the
  native build's C library would draw other numbers. A difference between
  the native and the sandbox runs is a bug to find, not to accept.
- **Nothing from outside the machine.** No network client (upstream's naett
  is not built), no sound capture (`TIC80_FFT_UNSUPPORTED`: a cart's `fft()`
  reads silence), no files but the project's.
- **The machine's state is its memory.** A savestate is the sandbox's copy
  of the core's memory. The cart's save memory (`pmem`) is part of TIC-80's
  memory; Export Save Data writes it, and the save data slot gives it back.
- **The controls are in two places that must agree**: the tables in
  `cinterface.c` and the `input` in `waterbox.config`. The test
  `package:controls` compares them.
- **Only what TIC-80's free build loads.** `.tic` and `.png` carts. Text
  carts (`.lua` and the like) are a feature of TIC-80 PRO, which its author
  sells; the core does not load them.
- **The test cart keeps a press only while it lasts.** A test that compares
  memory at the end holds the control to the end. A movie's row N is the
  test runner's frame N + 1.
- **Say what was not tried.** A cart that was not run has not been shown to
  work.
- **Write in plain language**: commit messages, documents, comments and
  setting descriptions are read by people who have never seen this
  repository. `.md` files are ASCII.
- **Commits**: `type(scope): what changed`; a short body with what changed,
  why, and how it was tested, with the numbers. Stage explicit paths. No
  amending, no force push.

## What is the owner's to decide

Publishing, the roster row in Chimera, moving to another TIC-80 commit, and
anything a licence does not plainly allow.
