"""
Builds plugin/MobaModelKit.rbxmx, the MOBA Model Kit Studio plugin, without needing Rojo.

Run:  python3 tools/build_plugin.py
Install: in Studio, open the Plugins folder (Plugins tab > Plugins Folder) and copy the file there,
then restart Studio. (With Rojo: rojo build plugin.project.json --plugin MobaModelKit.rbxmx)
"""
import json
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "plugin", "MobaModelKit.rbxmx")


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def lua_value(v, indent=""):
    """Converts decoded JSON into a Luau table literal (what Rojo does for .json files)."""
    if isinstance(v, dict):
        if not v:
            return "{}"
        inner = indent + "\t"
        items = []
        for k, val in v.items():
            key = k if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k) else "[%s]" % json.dumps(k)
            items.append("%s%s = %s" % (inner, key, lua_value(val, inner)))
        return "{\n" + ",\n".join(items) + ",\n" + indent + "}"
    if isinstance(v, list):
        return "{" + ", ".join(lua_value(x, indent) for x in v) + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return repr(v)


_ref = [0]


def item(cls, name, source, children=()):
    _ref[0] += 1
    assert "]]>" not in source, "source contains a CDATA terminator"
    kids = "".join(children)
    return (
        '<Item class="%s" referent="RBX%d"><Properties>'
        '<string name="Name">%s</string>'
        '<ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>'
        "</Properties>%s</Item>" % (cls, _ref[0], name, source, kids)
    )


def main():
    specs = json.loads(read("src/shared/ModelSpecs.json"))
    specs_src = "-- Generated from src/shared/ModelSpecs.json by tools/build_plugin.py\nreturn " + lua_value(specs) + "\n"
    children = [
        item("ModuleScript", "Config", read("src/shared/Config.lua")),
        item("ModuleScript", "ModelSpecs", specs_src),
        item("ModuleScript", "ModelBuilder", read("src/shared/ModelBuilder.lua")),
    ]
    xml = '<roblox version="4">' + item("Script", "MobaModelKit", read("plugin/src/init.server.lua"), children) + "</roblox>\n"
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(xml)
    print("wrote", os.path.normpath(OUT), "(%d KB)" % (len(xml) // 1024))


if __name__ == "__main__":
    main()
