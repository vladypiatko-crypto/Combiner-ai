#!/usr/bin/env python3
"""Bundle the shared Luau modules + a test script into one file runnable by a plain Luau VM.
`require(script.Parent.X)` becomes `__req("X")` so the exact Roblox source is what gets tested."""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
shared = root / "src" / "shared"
test = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])

req = re.compile(r"require\(script\.Parent\.(\w+)\)")
parts = ["local __mods, __cache = {}, {}\nlocal function __req(n) if __cache[n] == nil then __cache[n] = __mods[n]() end return __cache[n] end\n"]
for f in sorted(shared.glob("*.luau")):
    src = f.read_text()
    src = req.sub(lambda m: f'__req("{m.group(1)}")', src)
    src = re.sub(r"^export type", "type", src, flags=re.M)
    src = src.replace("--!strict", "")
    parts.append(f'__mods["{f.stem}"] = function()\n{src}\nend\n')
parts.append(test.read_text())
out.write_text("\n".join(parts))
