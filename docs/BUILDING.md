# Building

This core is built on Linux. The result, `core.wbx`, is one file that runs in
Chimera on Linux and on Windows.

## What is needed

- GCC 13 or newer (C and C++), meson, ninja, make, git, python3.
- A checkout of Chimera with miniBox built, with its C++ guest toolchain
  (Chimera's `AGENTS.md`, "Build"). Below, `<miniBox>` is its
  `extern/chimera-common-minibox` folder.

## TIC-80's source

TIC-80 is a submodule, `extern/tic80`, at a commit of its main branch. The
languages it runs are its own submodules, under `extern/tic80/vendor`:

```sh
git submodule update --init --recursive
```

A change to TIC-80 is kept as a numbered patch in `patches/`.
`waterbox/apply-patches.sh` lays the patches over the submodule (the build
runs it; it does nothing to a tree that has them). To make a patch, edit the
files in `extern/tic80`, build and test, add the file to the list in
`waterbox/make-patches.sh` if it is new, and run that script.

## What is compiled

Upstream builds with CMake. `meson.build` lists what that CMake compiles for
the machine and for each language, with the include folders and definitions
it gives each, as it was read from upstream's own configuration
(`-DBUILD_SDL=OFF -DBUILD_LIBRETRO=ON -DBUILD_STATIC=ON -DBUILD_WITH_ALL=ON`,
its `compile_commands.json`). Four files upstream's CMake writes are made
here instead:

- `version.h`, from `extern/tic80/version.h.in` with the version written in
  `meson.build` (upstream asks git for it);
- `pnglibconf.h`, copied from libpng's prebuilt one, as upstream does;
- `janet.c`, Janet's one-file source, which Janet's own Makefile writes by
  building a small Janet first (`waterbox/make-janet.sh`, on a copy of
  Janet's folder, with the build machine's compiler);
- `pfdicdat.h`, pForth's dictionary, which pForth writes once it is built
  with the build machine's compiler and has loaded its system words
  (`waterbox/make-pforth-dic.sh`, on a copy of pForth's folder). Upstream's
  CMake writes it into pForth's own folder; a header left there by such a
  build would be taken before this one, so the folder must not have it.

Moving the submodule to another commit means reading upstream's CMake again
for new or removed files, and the version in `meson.build`.

## The two flavors

- `native`: for the host. `run-native` is the reference the tests compare
  the sandbox with.
- `guest`: for miniBox's sandbox. This is `core.wbx`, and `run-wbx` runs it.

```sh
meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest
```

Both runners take a work folder that holds what the sandbox would see: the
cart under its name, a file `slots` (`{"cart":["game.tic"]}`, with
`"savedata":["game.pmem"]` for a saved game) and a file `settings` (`{}` or,
say, `{"picture":"screen"}`). `waterbox/gate-harness.h` lists the options
they share (`--frames`, `--report`, `--press`, `--axis`, `--vid-out`,
`--dump-domain`, `--savedata-out`, `--list-panel`).
`CHIMERA_TIC80_TRACE=1` prints what the cart writes with `trace()`; an error
in a cart's code is always printed.

## The package

```sh
waterbox/build-package.sh -r <chimera checkout>
```

builds the sandbox core and writes `build/Cores/tic80.chimeraCore` in that
checkout. `tests/make-project.py` writes a project for a cart, which
Chimera's `chimera-run --project` then plays.

## The tests

```sh
CHIMERA_ROOT=<chimera checkout> bash waterbox/run-gate.sh
TMPDIR=$PWD/build/t bash tests/run-frontend.sh --chimera-root <chimera checkout>
```

The first runs every test and says, for each, what was compared. It needs no
file of anyone's: `tests/make-tic80-cart.py` writes a cart whose program
reads every control and the clocks, and TIC-80's source carries a demo cart
of each language (`extern/tic80/build/assets/*demo.tic.dat`, which
`tests/extract-demo.py` writes out). The second runs the package in
Chimera's window under Mono on a private Xvfb display; it needs Chimera's
interface built (`dotnet build`).

Chimera's own checks of a package:

```sh
CHIMERA_CORES_DIR=<folder with the package> dotnet test source/gui/Chimera.Tests.Client.Common/Chimera.Tests.Client.Common.csproj -c Release --filter "FullyQualifiedName~InstalledCorePackagesTests|FullyQualifiedName~MnemonicUniquenessTests"
```

run in the Chimera checkout.
