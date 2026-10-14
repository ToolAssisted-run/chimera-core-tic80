#!/usr/bin/env python3
"""Checks that every key the package's default bindings name is a key
Chimera knows, so that none ships unbound by a misspelling. Chimera's names
are read from its source: the keyboard's (source/gui/Chimera.Input/
KeyMouseInput/DistinctKey.cs, with the names DistinctKeyNameOverrides.cs
gives some of them) and the mouse's.

usage: check-key-names.py <chimera checkout> <default_keybinds.json>"""
import json
import re
import sys

chimera, binds = sys.argv[1], sys.argv[2]
gui = chimera + "/source/gui"
enum = open(gui + "/Chimera.Input/KeyMouseInput/DistinctKey.cs").read()
enum = re.sub(r"///.*", "", enum)
body = enum[enum.index("enum DistinctKey"):]
body = body[body.index("{") + 1:body.index("}")]
# a member written "PageUp = Prior" is another name of the same key
alias = {}
for m in (m.strip() for m in body.split(",")):
    if m:
        name, _, of = (x.strip() for x in m.partition("="))
        alias[name] = alias.get(of, of) if of else name
over = open(gui + "/Chimera.Client.Common/input/DistinctKeyNameOverrides.cs").read()
renamed = dict(re.findall(r"DistinctKey\.(\w+)\s*=>\s*\"([^\"]+)\"", over))
# a key Chimera renames is known by that name alone, whichever of its names
# the rename is written with; another key by any of its names
renamed_keys = {alias[m]: n for m, n in renamed.items() if m in alias}
known = {renamed_keys.get(k, m) for m, k in alias.items()}
known |= {"WMouse L", "WMouse R", "WMouse M", "WMouse 1", "WMouse 2", "WMouse X", "WMouse Y", "RMouse X", "RMouse Y"}
cfg = json.load(open(binds))
bad = []
for panel in cfg.get("AllTrollers", {}).values():
    for control, value in panel.items():
        for key in filter(None, (v.strip() for v in value.split(","))):
            # a chord is keys joined by +
            for part in key.split("+"):
                if part not in known:
                    bad.append(f"{control}: {part}")
for panel in cfg.get("AllTrollersAnalog", {}).values():
    for control, value in panel.items():
        if value.get("Value") and value["Value"] not in known:
            bad.append(f"{control}: {value['Value']}")
if bad:
    sys.exit("keys Chimera does not know: " + ", ".join(bad))
print(f"every key the bindings name is one of Chimera's ({len(known)} names)")
