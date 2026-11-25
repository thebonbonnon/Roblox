"""
Builds build/Moba.rbxlx, a Roblox place file you can open straight in Studio (no Rojo needed).

Run:  python3 tools/build_place.py

Follows the same rules as Rojo and default.project.json:
  src/shared  -> ReplicatedStorage.Shared
  src/server  -> ServerScriptService.Server
  src/client  -> StarterPlayer.StarterPlayerScripts.Client
  *.server.lua -> Script, *.client.lua -> LocalScript, *.lua -> ModuleScript,
  *.json -> ModuleScript returning the data as a table
"""
import json
import os
import sys
from xml.sax.saxutils import escape

sys.path.insert(0, os.path.dirname(__file__))
from build_plugin import lua_value  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "build", "Moba.rbxlx")

_ref = [0]


def ref():
    _ref[0] += 1
    return "RBX%d" % _ref[0]


def props_xml(name, source=None, extra=""):
    s = '<string name="Name">%s</string>' % escape(name)
    if source is not None:
        assert "]]>" not in source, name
        s += '<ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>' % source
    return "<Properties>%s%s</Properties>" % (s, extra)


def item(cls, name, source=None, children=(), extra=""):
    return '<Item class="%s" referent="%s">%s%s</Item>' % (cls, ref(), props_xml(name, source, extra), "".join(children))


def script_item(path):
    base = os.path.basename(path)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if base.endswith(".server.lua"):
        return item("Script", base[: -len(".server.lua")], text)
    if base.endswith(".client.lua"):
        return item("LocalScript", base[: -len(".client.lua")], text)
    if base.endswith(".lua"):
        return item("ModuleScript", base[: -len(".lua")], text)
    if base.endswith(".json"):
        src = "-- Generated from %s\nreturn %s\n" % (os.path.relpath(path, ROOT), lua_value(json.loads(text)))
        return item("ModuleScript", base[: -len(".json")], src)
    return None


def folder_item(path, name):
    children = []
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            children.append(folder_item(full, entry))
        else:
            it = script_item(full)
            if it:
                children.append(it)
    return item("Folder", name, children=children)


def main():
    src = os.path.join(ROOT, "src")
    xml = "".join([
        '<roblox version="4">',
        item("ReplicatedStorage", "ReplicatedStorage", children=[folder_item(os.path.join(src, "shared"), "Shared")]),
        item("ServerScriptService", "ServerScriptService", children=[folder_item(os.path.join(src, "server"), "Server")]),
        item("StarterPlayer", "StarterPlayer", children=[
            item("StarterPlayerScripts", "StarterPlayerScripts", children=[folder_item(os.path.join(src, "client"), "Client")]),
        ]),
        item("Players", "Players", extra='<bool name="CharacterAutoLoads">false</bool>'),
        # Future lighting: realistic shadows and light from neon parts and lamps.
        item("Lighting", "Lighting", extra='<token name="Technology">4</token>'),
        "</roblox>\n",
    ])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(xml)
    print("wrote %s (%d KB)" % (os.path.relpath(OUT, ROOT), len(xml) // 1024))


if __name__ == "__main__":
    main()
