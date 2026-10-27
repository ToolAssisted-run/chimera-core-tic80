#!/bin/bash
# The package in Chimera's own window (run headless: it needs no display),
# which the headless runner cannot show:
#  - the test cart (tests/make-tic80-cart.py) runs in the window and leaves
#    the memory the headless runner leaves at the same frame, with a button
#    and a key pressed, at TIC-80's picture size (256x144);
#  - the keys the package ships become Chimera's keys for the controls;
#  - upstream's Lua demo cart (in TIC-80's source) runs in the window and
#    leaves the headless runner's memory.
#
# Usage: tests/run-frontend.sh --chimera-root <chimera checkout> [--frames N] [--keep]
#   --keep   leave the work folder (logs, configurations, projects) and say where it is
# Needs: Chimera built with its window (chimera --headless), and the
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

chimera_exe="$chimera_root/build/meson-linux/source/ui/chimera"
package="$chimera_root/build/Cores/tic80.chimeraCore"
runwbx="$root/build/meson-native/run-wbx"
core="$root/build/meson-guest/core.wbx"
runner="$chimera_root/build/meson-linux/chimera-run"
[ -x "$chimera_exe" ] || { echo "Chimera's window is not built: $chimera_exe" >&2; exit 1; }
[ -f "$package" ] || { echo "the package is not installed: $package (run waterbox/build-package.sh -r $chimera_root)" >&2; exit 1; }
[ -x "$runwbx" ] && [ -f "$core" ] || { echo "the sandbox build is not there: $runwbx, $core" >&2; exit 1; }
[ -x "$runner" ] || { echo "Chimera's headless runner is not built: $runner" >&2; exit 1; }

work="$(mktemp -d)"
cleanup() {
	if [ -n "$keep" ]; then echo "work folder kept: $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT

# run-wbx finds miniBox's host library in Chimera's build/dll
export LD_LIBRARY_PATH="$chimera_root/build/dll${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Chimera's window, run headless: the cores installed in the checkout, its
# settings, cache and recovery files the run's own, and nothing carried over
# from a Chimera installed on this machine
export ALSOFT_DRIVERS=null CHIMERA_CORES_DIR="$chimera_root/build/Cores" CHIMERA_QT_CACHE="$work/qt-cache" CHIMERA_QT_RECOVERY="$work/qt-recovery" \
	CHIMERA_QT_HASHES="$work/qt-file-hashes.txt" CHIMERA_QT_CHIMERA_SETTINGS="$work/no-chimera-config.ini"

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
	( cd "$chimera_root" && MINIHAWK_JOB="$job" timeout 900 "$chimera_exe" --headless \
		"--config=$cfg" "--project=$work/$tag/$tag.chimeraProject" "--lua=$here/frontend-ram.lua" ) >> "$work/$tag.log" 2>&1
	[ -f "$work/$tag.meta.txt" ] && grep -q "^status=OK" "$work/$tag.meta.txt"
}
value() { sed -n "s/^$2=//p" "$work/$1.meta.txt" 2>/dev/null; }

python3 "$here/settings-config.py" "$work/settings.base.json" '{}'

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
if ! run_frontend tt "$work/settings.base.json" "$frames" "RAM"; then
	report "window:tic" FAIL "Chimera did not finish the run: $(value tt detail) $(tail -2 "$work/tt.log" | tr '\n' ' ' | cut -c1-200)"
elif [ "$(value tt frames)" != "$frames" ] || [ "$(value tt width)" != 256 ] || [ "$(value tt height)" != 144 ]; then
	report "window:tic" FAIL "frames $(value tt frames) of $frames, picture $(value tt width)x$(value tt height) and not 256x144"
elif [ -s "$work/engine.ram.bin" ] && cmp -s "$work/engine.ram.bin" "$work/tt.ram.bin" && [ "$pads" = 10000000 ] && [ "$keyq" = 01 ]; then
	report "window:tic" PASS "the test cart ran $frames frames in Chimera's window, 256x144, with P1 A held from frame 100 and Q from 150 (the cart read $pads and $keyq); its memory ($(wc -c < "$work/tt.ram.bin") bytes) is what the headless runner leaves"
else
	report "window:tic" FAIL "the memory differs from the headless runner's (or one of the two is missing), or P1 A and Q did not reach the cart ($pads $keyq)"
fi

# the keys the package ships are the machine's when nobody changed them (the
# window keeps only the keys a person changed; fresh settings have none)
mkdir -p "$work/keys"; cp "$work/tt/test.tic" "$work/keys/"; sed 's/"tic80-test-[^"]*"/"tic80-test-keys"/' "$work/tt/tt.chimeraProject" > "$work/keys/keys.chimeraProject"
printf 'out=%s/keys.controls.json\nmeta=%s/keys.meta.txt\n' "$work" "$work" > "$work/job.keys.txt"
( cd "$chimera_root" && MINIHAWK_JOB="$work/job.keys.txt" timeout 900 "$chimera_exe" --headless \
	"--config=$work/settings.keys.json" "--project=$work/keys/keys.chimeraProject" "--lua=$here/dump-controls.lua" ) >> "$work/keys.log" 2>&1
if [ -f "$work/keys.meta.txt" ] && grep -q "^status=OK" "$work/keys.meta.txt"; then
	if python3 "$here/check-keybinds.py" "$work/keys.controls.json" "$wb/default_keybinds.json" "TIC-80 Controls" "P1 A" > "$work/keys.txt" 2>&1; then
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
if ! run_frontend demo "$work/settings.base.json" "$dframes" "RAM"; then
	report "window:demo" FAIL "Chimera did not finish the run: $(value demo detail) $(tail -2 "$work/demo.log" | tr '\n' ' ' | cut -c1-200)"
elif [ "$(value demo frames)" = "$dframes" ] && [ -s "$work/demo-engine.ram.bin" ] && cmp -s "$work/demo-engine.ram.bin" "$work/demo.ram.bin"; then
	report "window:demo" PASS "upstream's Lua demo cart ran $dframes frames in the window, $(value demo width)x$(value demo height), and left the memory the headless runner leaves"
else
	report "window:demo" FAIL "frames $(value demo frames) of $dframes, or the memory differs from the headless runner's"
fi

echo
echo "$ok passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
