#!/bin/bash
# The core's tests. Each line says what was compared. The script ends with a
# count of tests that passed, failed and were skipped, and with an error if
# any failed. A skipped test is not a pass.
#
#   waterbox/run-gate.sh
#
# CHIMERA_ROOT=<a Chimera checkout> adds the test that runs the package in
# Chimera's own headless runner (waterbox/build-package.sh -r <it> first).
#
# Needs the native build (meson setup build/meson-native ... && ninja) and
# the sandboxed core (waterbox/setup-guest.sh && ninja -C build/meson-guest):
# docs/BUILDING.md.
#
# WHAT RUNS WITH NO FILES OF YOURS: everything. tests/make-tic80-cart.py
# writes a cart whose program reads every control and the clocks into its
# memory, and TIC-80's own source carries a demo cart for each of its
# languages (build/assets/*demo.tic.dat), which tests/extract-demo.py writes
# out as .tic files.
#
# The ways a test passes on a broken thing (Chimera's docs/gates.md) that
# these are written against: a machine that did nothing agrees with itself,
# so a run is first checked to have got somewhere; the end of a run hides a
# run that went another way and came back, so runs are compared as a stream
# of digests; and a comparison that cannot fail proves nothing, so each
# "the same" has a run beside it that must come out different.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
native="$root/build/meson-native/run-native"
runwbx="$root/build/meson-native/run-wbx"
core="$root/build/meson-guest/core.wbx"
chimera_root="${CHIMERA_ROOT:-}"
assets="$root/extern/tic80/build/assets"

work="$(mktemp -d)"
# GATE_KEEP=1 keeps the work folder (the runs' output and dumps) and says where
if [ -n "${GATE_KEEP:-}" ]; then trap 'echo "work folder kept: $work"' EXIT; else trap 'rm -rf "$work"' EXIT; fi
ok=0; failed=0; skipped=0
report() { # <test> <PASS|FAIL|SKIP> <what>
	printf '%-22s %-6s %s\n' "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok + 1)) ;; FAIL) failed=$((failed + 1)) ;; *) skipped=$((skipped + 1)) ;; esac
}
# check <test> <what> <condition...>
check() {
	ck_test="$1"; ck_what="$2"; shift 2
	if "$@"; then report "$ck_test" PASS "$ck_what"; else report "$ck_test" FAIL "$ck_what"; fi
}
stream() { grep '^frame' "$1"; }
same() { [ -s "$1" ] && [ -s "$2" ] && cmp -s "$1" "$2"; }
differ() { [ -s "$1" ] && [ -s "$2" ] && ! cmp -s "$1" "$2"; }
# field <file> <name>: the value after a name in the file's last report line
field() { stream "$1" | tail -1 | awk -v f="$2" '{for (i = 1; i <= NF; i++) if ($i == f) { print $(i + 1); exit }}'; }
pictures() { stream "$1" | awk '{print $7}' | sort -u | wc -l; }
# what the test cart keeps in the map's memory (tests/make-tic80-cart.py),
# little-endian: hex <dump> <address> <length>, and one value as u32, s16, s8
hex() { od -v -An -tx1 -j $(($2)) -N"$3" "$1" 2> /dev/null | tr -d ' \n'; }
u32() { od -v -An -tu4 -j $(($2)) -N4 "$1" 2> /dev/null | tr -d ' '; }
s16() { od -v -An -td2 -j $(($2)) -N2 "$1" 2> /dev/null | tr -d ' '; }
s8() { od -v -An -td1 -j $(($2)) -N1 "$1" 2> /dev/null | tr -d ' '; }
# folder <name> <settings json> <cart> [<save data>]: a work folder as the
# sandbox mounts a project - every file under its name
folder() {
	mkdir -p "$work/$1"
	cp "$3" "$work/$1/$(basename "$3")"
	if [ -n "${4:-}" ]; then
		cp "$4" "$work/$1/$(basename "$4")"
		printf '{"cart":["%s"],"savedata":["%s"]}' "$(basename "$3")" "$(basename "$4")" > "$work/$1/slots"
	else
		printf '{"cart":["%s"]}' "$(basename "$3")" > "$work/$1/slots"
	fi
	printf '%s' "$2" > "$work/$1/settings"
}
nat() { nt_out="$1"; nt_dir="$2"; shift 2; "$native" "$work/$nt_dir" "$@" > "$work/$nt_out.out" 2> "$work/$nt_out.err"; }
box() { bx_out="$1"; bx_dir="$2"; shift 2; "$runwbx" "$core" "$work/$bx_dir" "$@" > "$work/$bx_out.out" 2> "$work/$bx_out.err"; }
# index <folder> <control>: the control's place in the panel
index() { "$native" "$work/$1" --frames 1 --list-panel 2> /dev/null | grep "'$2'" | head -1 | awk '{print $2}'; }
# repeats <file> <first> <second> <count> <step>: do the report lines from
# frame <second> on repeat those from frame <first> on (run-wbx --rewind)
repeats() {
	awk -v a="$2" -v b="$3" -v n="$4" -v step="$5" '
		/^frame/ { f = $2; $1 = ""; $2 = ""; sub(/ lag [0-9]+$/, ""); line[f] = $0 }
		END {
			for (i = step; i < n; i += step) {
				if (!((a + i) in line) || !((b + i) in line) || line[a + i] != line[b + i]) exit 1
				seen++
			}
			exit seen > 0 ? 0 : 1
		}' "$1"
}

if [ ! -x "$native" ] || [ ! -x "$runwbx" ] || [ ! -f "$core" ]; then
	echo "not built: this needs build/meson-native/run-native and run-wbx, and build/meson-guest/core.wbx (docs/BUILDING.md)" >&2
	exit 1
fi

# ------------------------------------------------- the source and the package
patches="$(ls "$root"/patches/*.patch 2> /dev/null | wc -l)"
check "source:patched" "extern/tic80 is the pinned commit with the $patches patches of patches/" \
	sh -c "sh '$here/apply-patches.sh' > '$work/patches.log' 2>&1 && [ \"\$(git -C '$root' rev-parse HEAD:extern/tic80)\" = \"\$(git -C '$root/extern/tic80' rev-parse HEAD)\" ]"

stale=""
for src in "$here"/cinterface.c "$root"/meson.build "$root"/patches/*.patch; do
	[ -e "$src" ] || continue
	[ "$core" -nt "$src" ] || stale="$stale $(basename "$src")"
done
check "package:fresh" "core.wbx is not older than its sources${stale:+ (older than:$stale)}" [ -z "$stale" ]

# ------------------------------------------------- the test cart
mkdir -p "$work/carts"
for v in "" nopad relative error banks; do
	python3 "$root/tests/make-tic80-cart.py" "$work/carts/test${v:+-$v}.tic" $v > /dev/null
done
folder t '{}' "$work/carts/test.tic"
folder q '{}' "$work/carts/test-nopad.tic"

"$native" "$work/t" --frames 1 --list-panel > "$work/panel.out" 2> /dev/null
check "package:controls" "the package declares the core's own $(grep -c '^panel' "$work/panel.out") buttons, in the core's order, and its 6 axes" \
	python3 - "$here/waterbox.config" "$work/panel.out" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
lines = open(sys.argv[2]).read().splitlines()
buttons = [l[l.index("'") + 1:l.rindex("'")] for l in lines if l.startswith("panel ")]
axes = [l for l in lines if l.startswith("axis ")]
i = cfg["input"]
sys.exit(0 if i["buttons"] == buttons and len(buttons) == 129 and len(i["axes"]) == len(axes) == 6 else 1)
PY

if [ -n "$chimera_root" ] && [ -f "$chimera_root/source/gui/Chimera.Input/KeyMouseInput/DistinctKey.cs" ]; then
	check "package:key-names" "every host key the package's default bindings name is a key Chimera knows: $(python3 "$root/tests/check-key-names.py" "$chimera_root" "$here/default_keybinds.json" 2>&1)" \
		sh -c "python3 '$root/tests/check-key-names.py' '$chimera_root' '$here/default_keybinds.json' > /dev/null 2>&1"
else
	report "package:key-names" SKIP "needs CHIMERA_ROOT, whose source names the keys Chimera knows"
fi

nat idle t --frames 300 --report 25 --dump-domain RAM "$work/idle.ram"
check "tic:runs" "the cart this script writes runs: its frame count is $(u32 "$work/idle.ram" 0x8000) after 300 frames, with $(pictures "$work/idle.out") different pictures in 12 reports" \
	sh -c "[ '$(u32 "$work/idle.ram" 0x8000)' = 300 ] && [ $(pictures "$work/idle.out") -ge 10 ]"

# each_bit <folder> <first control> <count> <address> <bytes> <out>: each
# control held alone from frame 60 to the end; what the cart then read
each_bit() {
	: > "$6"
	for ((c = 0; c < $3; c++)); do
		"$native" "$work/$1" --frames 100 --press $(($2 + c)):60:60 --dump-domain RAM "$work/eb.ram" > /dev/null 2>&1
		echo "$c $(hex "$work/eb.ram" "$4" "$5")" >> "$6"
	done
}
# one_bit <file> <count>: there are <count> lines, and line c has bit c set
# and no other
one_bit() {
	python3 - "$1" "$2" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")[:-1]
for line in lines:
    c, h = line.split()
    if int.from_bytes(bytes.fromhex(h), "little") != 1 << int(c):
        sys.exit(1)
sys.exit(0 if len(lines) == int(sys.argv[2]) else 1)
PY
}
each_bit t 0 32 0x8004 4 "$work/pads.txt"
check "tic:gamepads" "each of the 32 gamepad buttons (P1 to P4: Up, Down, Left, Right, A, B, X, Y), held alone, is btn() of its own number to the cart and no other" \
	one_bit "$work/pads.txt" 32
# the keys are listed as they sit on the keyboard (chimera#337), from Escape;
# each is key() of its own code, which is its place in TIC-80's list
key1="$(index t "Key Escape")"
each_bit t "$key1" 94 0x8008 12 "$work/keys-listed.txt"
"$native" "$work/t" --frames 1 --list-panel 2> /dev/null | grep "^panel" > "$work/keys-panel.txt"
python3 - "$work/keys-listed.txt" "$work/keys-panel.txt" "$key1" > "$work/keys.txt" <<'PY'
import re, sys
tic = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U",
       "V", "W", "X", "Y", "Z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
       "-", "=", "[", "]", "\\", ";", "'", "`", ",", ".", "/",
       "Space", "Tab", "Return", "Backspace", "Delete", "Insert", "Page Up", "Page Down", "Home", "End",
       "Up", "Down", "Left", "Right", "Caps Lock", "Ctrl", "Shift", "Alt",
       "Escape"] + ["F%d" % i for i in range(1, 13)] + ["Keypad %d" % i for i in range(10)] + [
       "Keypad +", "Keypad -", "Keypad *", "Keypad /", "Keypad Enter", "Keypad ."]
names = {}
for line in open(sys.argv[2]):
    m = re.match(r"^panel (\d+) '(.*)'", line)
    if m: names[int(m.group(1))] = m.group(2)
first = int(sys.argv[3])
for line in open(sys.argv[1]):
    c, h = line.split()
    # the line of the key's code: what one_bit expects
    print(tic.index(names[first + int(c)][4:]), h)
PY
check "tic:keys" "each of the 94 keys, held alone, is key() of its own code to the cart and no other" \
	one_bit "$work/keys.txt" 94
nat five t --frames 100 --press "$(index t "Key A")":60:60 --press "$(index t "Key B")":60:60 --press "$(index t "Key C")":60:60 --press "$(index t "Key D")":60:60 --press "$(index t "Key E")":60:60 --dump-domain RAM "$work/five.ram"
check "tic:four-keys" "with five keys held (A to E) the cart sees the first four, as TIC-80 holds four at once ($(hex "$work/five.ram" 0x8008 2))" \
	[ "$(hex "$work/five.ram" 0x8008 2)" = 0f00 ]

ml="$(index t "Mouse Left")"
nat mb t --frames 100 --press "$ml":60:60 --press $((ml + 1)):60:60 --press $((ml + 2)):60:60 --dump-domain RAM "$work/mb.ram"
check "tic:mouse-buttons" "Mouse Left, Middle and Right held are mouse()'s three buttons ($(hex "$work/mb.ram" 0x8018 3); none held $(hex "$work/idle.ram" 0x8018 3))" \
	[ "$(hex "$work/mb.ram" 0x8018 3)" = 010101 -a "$(hex "$work/idle.ram" 0x8018 3)" = 000000 ]

# the mouse's place: a fraction of the picture shown
place() { # <folder> <x axis> <y axis> -> "x y" as the cart reads them
	"$native" "$work/$1" --frames 30 --axis 0:"$2":1:60 --axis 1:"$3":1:60 --dump-domain RAM "$work/pl.ram" > /dev/null 2>&1
	echo "$(s16 "$work/pl.ram" 0x8014) $(s16 "$work/pl.ram" 0x8016)"
}
folder ts '{"picture":"screen"}' "$work/carts/test.tic"
full="$(place t 0 0)|$(place t 32768 32768)|$(place t 65535 65535)"
scr="$(place ts 0 0)|$(place ts 32768 32768)|$(place ts 65535 65535)"
check "tic:mouse-place" "Mouse X and Y place the mouse on the picture shown: corner, middle, corner are ($full) on the whole 256x144 picture (with 8 and 4 pixels of border) and ($scr) with Picture 'screen'" \
	[ "$full|$scr" = "-8 -4|120 68|247 139|0 0|120 68|239 135" ]

folder rel '{}' "$work/carts/test-relative.tic"
nat rel rel --frames 30 --axis 2:5:1:60 --axis 3:-7:1:60 --axis 0:1000:1:60 --dump-domain RAM "$work/rel.ram"
check "tic:mouse-move" "a cart in TIC-80's relative mode reads Mouse Move X and Y (5, -7) as the mouse's movement ($(s16 "$work/rel.ram" 0x8014) $(s16 "$work/rel.ram" 0x8016)), and not Mouse X" \
	[ "$(s16 "$work/rel.ram" 0x8014) $(s16 "$work/rel.ram" 0x8016)" = "5 -7" ]
nat sc t --frames 30 --axis 4:3:1:60 --axis 5:-2:1:60 --dump-domain RAM "$work/sc.ram"
check "tic:scroll" "Scroll X and Y (3, -2) are mouse()'s scroll values ($(s8 "$work/sc.ram" 0x801B) $(s8 "$work/sc.ram" 0x801C))" \
	[ "$(s8 "$work/sc.ram" 0x801B) $(s8 "$work/sc.ram" 0x801C)" = "3 -2" ]

# the clock: time() and tstamp() come from the frames run, and tstamp() from
# the Starting Clock
folder clk '{"initialTime":1234567890}' "$work/carts/test.tic"
nat clk clk --frames 300 --dump-domain RAM "$work/clk.ram"
check "tic:clock" "time() is the milliseconds of the frames run ($(u32 "$work/idle.ram" 0x8020) in the 300th frame), tstamp() the Starting Clock plus the seconds run ($(u32 "$work/idle.ram" 0x8024) by default, $(u32 "$work/clk.ram" 0x8024) from 1234567890)" \
	[ "$(u32 "$work/idle.ram" 0x8020) $(u32 "$work/idle.ram" 0x8024) $(u32 "$work/clk.ram" 0x8024)" = "4983 946684804 1234567894" ]

nat q q --frames 300 --report 100
check "tic:lag" "the cart that reads the controls has no lag frame in 300 ($(field "$work/idle.out" lag)); its twin that reads none, 300 ($(field "$work/q.out" lag))" \
	[ "$(field "$work/idle.out" lag)" = 0 -a "$(field "$work/q.out" lag)" = 300 ]

check "tic:sound" "735 pairs of samples a frame (44100 a second at 60 frames: $(field "$work/idle.out" aud)), and the sound changes as the cart's pitch does" \
	sh -c "[ '$(field "$work/idle.out" aud)' = 735 ] && [ \$(grep '^frame' '$work/idle.out' | awk '{print \$10}' | sort -u | wc -l) -gt 3 ]"

# the save memory: exported after a run, and a project begins from it
mkdir -p "$work/sv"
nat sv t --frames 300 --savedata-out "$work/sv"
pm="$work/sv/test.pmem"
folder sv2 '{}' "$work/carts/test.tic" "$pm"
nat sv2 sv2 --frames 100 --dump-domain RAM "$work/sv2.ram"
check "tic:save-data" "Export Save Data writes the cart's pmem as test.pmem ($(wc -c < "$pm" 2> /dev/null) bytes, its count $(u32 "$pm" 0)); a project with it as save data begins from it: 100 frames later the count is $(u32 "$work/sv2.ram" 0x14004)" \
	sh -c "[ '$(wc -c < "$pm" 2> /dev/null)' = 1024 ] && [ '$(u32 "$pm" 0)' = 300 ] && [ '$(u32 "$work/sv2.ram" 0x14004)' = 400 ]"

# the picture: the screen alone is the middle of the whole picture; the
# cursor is drawn on the picture only
nat pf t --frames 120 --report 20 --vid-out "$work/pf.vid"
nat ps ts --frames 120 --vid-out "$work/ps.vid"
folder th '{"mouseCursor":"hide"}' "$work/carts/test.tic"
nat ph th --frames 120 --report 20 --vid-out "$work/ph.vid"
check "tic:picture" "Picture 'full' is 256x144 and 'screen' 240x136, the middle of it; with Mouse Cursor 'hide' the picture differs and the machine's memory does not" \
	python3 - "$work/pf.vid" "$work/ps.vid" "$work/ph.vid" "$work/pf.out" "$work/ph.out" <<'PY'
import sys
def read(p):
    d = open(p, "rb").read(); n = d.index(b"\n"); w, h = map(int, d[:n].split()); return w, h, d[n + 1:]
fw, fh, f = read(sys.argv[1]); sw, sh, s = read(sys.argv[2]); hw, hh, hidden = read(sys.argv[3])
mid = b"".join(f[((y + 4) * fw + 8) * 4:((y + 4) * fw + 8 + 240) * 4] for y in range(136))
ram = lambda p: [l.split()[3] for l in open(p) if l.startswith("frame")]
ok = (fw, fh, sw, sh) == (256, 144, 240, 136) and mid == s and hidden != f and ram(sys.argv[4]) and ram(sys.argv[4]) == ram(sys.argv[5])
sys.exit(0 if ok else 1)
PY

# The cursor on a cart that ends every other frame on its second video bank,
# whose cursor it cleared: the cursor is the first bank's, on every frame.
# It showed on every other frame (Hollow Knight Demake, chimera#318).
folder bk '{}' "$work/carts/test-banks.tic"
folder bkh '{"mouseCursor":"hide"}' "$work/carts/test-banks.tic"
nat bk bk --frames 40 --report 1
nat bkh bkh --frames 40 --report 1
check "tic:cursor-banks" "on a cart that ends every other frame on its second video bank, the cursor is drawn on every frame: each of 40 pictures differs from the same frame with Mouse Cursor 'hide'" \
	python3 - "$work/bk.out" "$work/bkh.out" <<'PY'
import sys
def vids(p):
    out = []
    for l in open(p):
        t = l.split()
        if t and t[0] == "frame" and "vid" in t:
            out.append(t[t.index("vid") + 2])
    return out
a, b = vids(sys.argv[1]), vids(sys.argv[2])
sys.exit(0 if len(a) == 40 and len(b) == 40 and all(x != y for x, y in zip(a, b)) else 1)
PY

# ------------------------------------------------- native and sandbox, states
p1a="$(index t "P1 A")"
allrun="--frames 300 --report 10 --press $p1a:50:40 --press $(index t "Key D"):80:30 --press $ml:100:20 --axis 0:10000:120:60 --axis 1:50000:150:40 --press 10:200:30"
nat all t $allrun
nat idle10 t --frames 300 --report 10
box all-box t $allrun
box all-rerecord t $allrun --rerecord
box all-session t $allrun --session
for n in all all-box all-rerecord all-session idle10; do stream "$work/$n.out" > "$work/$n.stream"; done
check "tic:sandbox" "native and sandbox print the same $(wc -l < "$work/all.stream") digests of memory, picture and sound, with buttons, keys and the mouse used" \
	same "$work/all.stream" "$work/all-box.stream"
check "tic:presses-change-the-run" "the run with presses differs from the idle one" differ "$work/all.stream" "$work/idle10.stream"
check "tic:state-every-frame" "a state saved and loaded every frame changes nothing" same "$work/all-box.stream" "$work/all-rerecord.stream"
check "tic:state-other-box" "a state moved to a new sandbox half way changes nothing" same "$work/all-box.stream" "$work/all-session.stream"
box rewind t --frames 1600 --report 5 --rewind
check "tic:state-rewind" "a state kept at frame 800 and loaded at 1200: the frames after the load repeat those after the save" \
	repeats "$work/rewind.out" 800 1200 400 5

# ------------------------------------------------- the languages
# TIC-80's own demo cart of each language: it runs without an error, its
# picture moves (P1 Right and Down move the demo's figure), and the sandbox
# gives the native build's digests. Most of the demos draw the same scene,
# and those say they gave Lua's digests.
demorun="--frames 300 --report 20 --press 3:20:250 --press 1:100:100"
for l in lua moon fennel yue js squirrel scheme wren wasm janet python miniscript forth; do
	python3 "$root/tests/extract-demo.py" "$assets/${l}demo.tic.dat" "$work/carts/$l.tic"
	folder d-$l '{}' "$work/carts/$l.tic"
	nat d-$l d-$l $demorun
	box d-$l-box d-$l $demorun
	stream "$work/d-$l.out" > "$work/d-$l.stream"; stream "$work/d-$l-box.out" > "$work/d-$l-box.stream"
	err=""; grep -q "stopped with an error" "$work/d-$l.err" "$work/d-$l-box.err" && err=" (with an error)"
	asl=""; [ "$l" != lua ] && cmp -s "$work/d-$l.stream" "$work/d-lua.stream" && asl=", Lua's digests"
	check "lang:$l" "upstream's $l demo runs$err: $(pictures "$work/d-$l.out") different pictures in 15 reports$asl; the sandbox gives the native build's digests" \
		sh -c "[ -z '$err' ] && [ $(pictures "$work/d-$l.out") -ge 5 ] && cmp -s '$work/d-$l.stream' '$work/d-$l-box.stream' && [ -s '$work/d-$l.stream' ]"
done

# ------------------------------------------------- what is refused
python3 "$root/tests/extract-demo.py" "$assets/rubydemo.tic.dat" "$work/carts/ruby.tic"
folder ruby '{}' "$work/carts/ruby.tic"
nat ruby ruby --frames 1
check "refused:ruby" "a cart in Ruby, which this core does not build, is refused, and says so" grep -q "Init failed.*written in ruby" "$work/ruby.out" "$work/ruby.err"
mkdir -p "$work/none"
printf '{"cart":[]}' > "$work/none/slots"; printf '{}' > "$work/none/settings"
nat none none --frames 1
check "refused:no-cart" "a machine with no cart is refused, and says so" grep -q "Init failed.*no cart was given" "$work/none.out" "$work/none.err"
printf 'not a cart' > "$work/carts/junk.tic"
folder junk '{}' "$work/carts/junk.tic"
nat junk junk --frames 1
check "refused:not-a-cart" "a file that is not a cart is refused, and says so" grep -q "Init failed.*not a TIC-80 cart" "$work/junk.out" "$work/junk.err"
folder er '{}' "$work/carts/test-error.tic"
nat er er --frames 60 --report 60
check "cart:error" "a cart whose code stops with an error says so once ($(grep -c 'stopped with an error' "$work/er.err") times in 60 frames), and the machine goes on" \
	sh -c "[ $(grep -c 'stopped with an error' "$work/er.err") = 1 ] && grep -q '^frame    60' '$work/er.out'"

# ------------------------------------------------- Chimera's engine
runner="$chimera_root/build/dll/chimera-run"
package="$chimera_root/build/Cores/tic80.chimeraCore"
if [ -n "$chimera_root" ] && [ -x "$runner" ] && [ -f "$package" ]; then
	mkdir -p "$work/proj"
	cp "$work/carts/test.tic" "$work/proj/"
	python3 "$root/tests/make-project.py" "$package" "$work/proj/test.chimeraProject" 300 \
		"press=P1 A:199:101" "press=P3 Down:149:151" "press=Key Q:99:201" panel="$work/panel.out" -- cart="$work/proj/test.tic" > /dev/null
	"$runner" --project "$work/proj/test.chimeraProject" "$package" --files "$work/proj" --frames 300 \
		--dump "RAM=$work/engine.ram" > "$work/engine.log" 2>&1
	box eng t --frames 300 --press "$p1a":200:101 --press "$(index t "P3 Down")":150:151 --press "$(index t "Key Q")":100:201 --dump-domain RAM "$work/eng.ram"
	check "engine:tic" "a project of the test cart with presses plays in Chimera's headless runner to the sandbox runner's memory ($(wc -c < "$work/eng.ram" 2> /dev/null) bytes; the cart read $(hex "$work/engine.ram" 0x8004 4) on its pads, and Q)" \
		sh -c "cmp -s '$work/engine.ram' '$work/eng.ram' && [ '$(hex "$work/engine.ram" 0x8004 4)' = 10000200 ] && [ '$(hex "$work/engine.ram" 0x800A 1)' = 01 ]"
else
	report "engine:tic" SKIP "needs CHIMERA_ROOT with build/dll/chimera-run and build/Cores/tic80.chimeraCore"
fi

echo
echo "$ok passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
