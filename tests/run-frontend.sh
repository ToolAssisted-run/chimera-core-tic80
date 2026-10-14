#!/bin/bash
# The package in Chimera's own window (Chimera.exe under Mono, on a private
# Xvfb display), which the headless runner cannot show:
#  - the test cart (tests/make-tic80-cart.py) runs in the window and leaves
#    the memory the headless runner leaves at the same frame, with a button
#    and a key pressed, at TIC-80's picture size (256x144);
#  - the keys the package ships become Chimera's keys for the controls;
#  - upstream's Lua demo cart (in TIC-80's source) runs in the window and
#    leaves the headless runner's memory.
#
# Usage: tests/run-frontend.sh --chimera-root <chimera checkout> [--frames N] [--keep]
#   --keep   leave the work folder (logs, configurations, projects) and say where it is
# Needs: mono, Xvfb, Chimera built with its window (dotnet build), and the
# package installed in that checkout (waterbox/build-package.sh -r <chimera>).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
wb="$root/waterbox"
frames=300
chimera_root=""
keep=""
while [ $# -gt 0 ]; do
	case "$1" in
		--keep) keep=1 ;;
		--chimera-root) chimera_root="$2"; shift ;;
		--frames) frames="$2"; shift ;;
		-*) echo "unknown option: $1" >&2; exit 2 ;;
		*) break ;;
	esac
	shift
done
[ -n "$chimera_root" ] && [ -d "$chimera_root" ] || { echo "say where Chimera is: --chimera-root <chimera checkout>" >&2; exit 2; }
chimera_root="$(cd "$chimera_root" && pwd)"

emu_exe="$chimera_root/build/Chimera.exe"
package="$chimera_root/build/Cores/tic80.chimeraCore"
runwbx="$root/build/meson-native/run-wbx"
core="$root/build/meson-guest/core.wbx"
runner="$chimera_root/build/meson-linux/chimera-run"
[ -f "$emu_exe" ] || { echo "Chimera's window is not built: $emu_exe" >&2; exit 1; }
[ -f "$package" ] || { echo "the package is not installed: $package (run waterbox/build-package.sh -r $chimera_root)" >&2; exit 1; }
[ -x "$runwbx" ] && [ -f "$core" ] || { echo "the sandbox build is not there: $runwbx, $core" >&2; exit 1; }
[ -x "$runner" ] || { echo "Chimera's headless runner is not built: $runner" >&2; exit 1; }

work="$(mktemp -d)"
xvfb_pid=""
cleanup() {
	[ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null
	if [ -n "$keep" ]; then echo "work folder kept: $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT

export LD_LIBRARY_PATH="$chimera_root/build/dll:$chimera_root/build:/usr/lib/x86_64-linux-gnu"
export MONO_CRASH_NOFILE=1 MONO_WINFORMS_XIM_STYLE=disabled ALSOFT_DRIVERS=null
# always a display of this test's own: nobody's desktop is drawn on
command -v Xvfb >/dev/null || { echo "Xvfb not found (apt install xvfb)" >&2; exit 1; }
for n in 90 91 92 93 94 95 96; do
	if [ ! -e "/tmp/.X11-unix/X$n" ]; then
		Xvfb ":$n" -screen 0 1024x768x24 -nolisten tcp > /dev/null 2>&1 & xvfb_pid=$!
		export DISPLAY=":$n"; break
	fi
done
[ -n "$xvfb_pid" ] || { echo "no free display number for Xvfb" >&2; exit 1; }
sleep 1

config="$work/config.ini"
( cd "$chimera_root" && timeout 120 mono "$emu_exe" --headless "--config=$config" "--lua=$here/exit.lua" ) > "$work/bootstrap.log" 2>&1
[ -f "$config" ] || { echo "Chimera did not write a configuration:"; tail -5 "$work/bootstrap.log"; exit 1; } >&2
sed -i 's/"DispMethod": [0-9]/"DispMethod": 1/' "$config"

ok=0
failed=0
skipped=0
report() {
	printf '%-16s %-5s %s\n' "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok + 1)) ;; SKIP) skipped=$((skipped + 1)) ;; *) failed=$((failed + 1)) ;; esac
}

# make_project <tag> <frames> <cart> [<setting>=<value> | press=...]...
# A project with the cart beside it, where Chimera looks, and a movie of
# that many frames over the controls.
make_project() {
	local tag="$1" nframes="$2" gamefile="$3"; shift 3
	local dir="$work/$tag"
	mkdir -p "$dir"
	cp "$gamefile" "$dir/"
	python3 "$here/make-project.py" "$package" "$dir/$tag.chimeraProject" "$nframes" "panel=$work/panel.out" "$@" \
		-- "cart=$dir/$(basename "$gamefile")" > "$work/$tag.log" 2>&1
}
# run_frontend <tag> <configuration> <frames> <domain or "">: the project in the window
run_frontend() {
	local tag="$1" cfg="$2" nframes="$3" domain="$4" job="$work/job.$1.txt"
	{
		echo "frames=$nframes"
		echo "out=$work/$tag.ram.bin"
		echo "meta=$work/$tag.meta.txt"
		echo "shot="
		echo "domain=$domain"
	} > "$job"
	( cd "$chimera_root" && MINIHAWK_JOB="$job" timeout 900 mono "$emu_exe" --headless \
		"--config=$cfg" "--project=$work/$tag/$tag.chimeraProject" "--lua=$here/frontend-ram.lua" ) >> "$work/$tag.log" 2>&1
	[ -f "$work/$tag.meta.txt" ] && grep -q "^status=OK" "$work/$tag.meta.txt"
}
value() { sed -n "s/^$2=//p" "$work/$1.meta.txt" 2>/dev/null; }

python3 "$here/settings-config.py" "$config" "$work/config.base.ini" '{}'

# ---- the test cart: needs no file of anyone's
mkdir -p "$work/cart" "$work/probe"
python3 "$here/make-tic80-cart.py" "$work/cart/test.tic" > /dev/null
cp "$work/cart/test.tic" "$work/probe/test.tic"
printf '{"cart":["test.tic"]}' > "$work/probe/slots"; printf '{}' > "$work/probe/settings"
"$runwbx" "$core" "$work/probe" --frames 1 --list-panel > "$work/panel.out" 2> /dev/null
# the movie is longer than the run: a window whose movie ends stops there;
# P1 A is held from frame 100 (row 99) to the end, and the key Q from 150
make_project tt $((frames + 100)) "$work/cart/test.tic" "press=P1 A:99:$frames" "press=Key Q:149:$frames"
"$runner" --project "$work/tt/tt.chimeraProject" "$package" --files "$work/tt" --frames "$frames" \
	--dump "RAM=$work/engine.ram.bin" > "$work/engine.log" 2>&1
pads="$(od -An -tx1 -j $((0x8004)) -N4 "$work/engine.ram.bin" 2> /dev/null | tr -d ' ')"
keyq="$(od -An -tx1 -j $((0x800A)) -N1 "$work/engine.ram.bin" 2> /dev/null | tr -d ' ')"
if ! run_frontend tt "$work/config.base.ini" "$frames" "RAM"; then
	report "window:tic" FAIL "Chimera did not finish the run: $(value tt detail) $(tail -2 "$work/tt.log" | tr '\n' ' ' | cut -c1-200)"
elif [ "$(value tt frames)" != "$frames" ] || [ "$(value tt width)" != 256 ] || [ "$(value tt height)" != 144 ]; then
	report "window:tic" FAIL "frames $(value tt frames) of $frames, picture $(value tt width)x$(value tt height) and not 256x144"
elif [ -s "$work/engine.ram.bin" ] && cmp -s "$work/engine.ram.bin" "$work/tt.ram.bin" && [ "$pads" = 10000000 ] && [ "$keyq" = 01 ]; then
	report "window:tic" PASS "the test cart ran $frames frames in Chimera's window, 256x144, with P1 A held from frame 100 and Q from 150 (the cart read $pads and $keyq); its memory ($(wc -c < "$work/tt.ram.bin") bytes) is what the headless runner leaves"
else
	report "window:tic" FAIL "the memory differs from the headless runner's (or one of the two is missing), or P1 A and Q did not reach the cart ($pads $keyq)"
fi

python3 "$here/forget-controller.py" "$work/config.base.ini" "$work/config.keys.ini" "TIC-80 Controls"
mkdir -p "$work/keys"; cp "$work/tt/test.tic" "$work/keys/"; sed 's/"tic80-test-[^"]*"/"tic80-test-keys"/' "$work/tt/tt.chimeraProject" > "$work/keys/keys.chimeraProject"
if run_frontend keys "$work/config.keys.ini" 1 ""; then
	if python3 "$here/check-keybinds.py" "$work/config.keys.ini" "$wb/default_keybinds.json" "TIC-80 Controls" "P1 A" > "$work/keys.txt" 2>&1; then
		report "window:keys" PASS "$(cat "$work/keys.txt")"
	else
		report "window:keys" FAIL "$(head -1 "$work/keys.txt")"
	fi
else
	report "window:keys" FAIL "Chimera did not finish the run: $(tail -2 "$work/keys.log" | tr '\n' ' ' | cut -c1-200)"
fi

# ---- upstream's Lua demo cart, in the window, with P1 Right held
dframes=600
python3 "$here/extract-demo.py" "$root/extern/tic80/build/assets/luademo.tic.dat" "$work/cart/luademo.tic"
make_project demo $((dframes + 100)) "$work/cart/luademo.tic" "press=P1 Right:99:200"
"$runner" --project "$work/demo/demo.chimeraProject" "$package" --files "$work/demo" --frames "$dframes" \
	--dump "RAM=$work/demo-engine.ram.bin" > "$work/demo-engine.log" 2>&1
if ! run_frontend demo "$work/config.base.ini" "$dframes" "RAM"; then
	report "window:demo" FAIL "Chimera did not finish the run: $(value demo detail) $(tail -2 "$work/demo.log" | tr '\n' ' ' | cut -c1-200)"
elif [ "$(value demo frames)" = "$dframes" ] && [ -s "$work/demo-engine.ram.bin" ] && cmp -s "$work/demo-engine.ram.bin" "$work/demo.ram.bin"; then
	report "window:demo" PASS "upstream's Lua demo cart ran $dframes frames in the window, $(value demo width)x$(value demo height), and left the memory the headless runner leaves"
else
	report "window:demo" FAIL "frames $(value demo frames) of $dframes, or the memory differs from the headless runner's"
fi

echo
echo "$ok passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
