"""Usage: python capture_android.py DEVICE_SERIAL OUTPUT_PREFIX.

Capture unmodified Android pixels and a fresh accessibility hierarchy.
"""

import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET

serial, prefix = sys.argv[1:]
prefix = Path(prefix).resolve()
png_path = Path(str(prefix) + ".png")
xml_path = Path(str(prefix) + ".xml")
if png_path.exists() or xml_path.exists():
    raise SystemExit("Capture destination already exists; reconcile it before retrying.")
prefix.parent.mkdir(parents=True, exist_ok=True)
adb = ["adb", "-s", serial]


def run(arguments):
    return subprocess.run(adb + arguments, capture_output=True, check=True, timeout=35)


remote = f"/sdcard/lexiquest-figcraft-{uuid.uuid4().hex}.xml"
run(["shell", "-x", "uiautomator", "dump", remote])
run(["pull", remote, str(xml_path)])
tree = ET.parse(xml_path)
assert tree.getroot().tag == "hierarchy", "Invalid Android hierarchy"
png = run(["exec-out", "screencap", "-p"]).stdout
assert png.startswith(b"\x89PNG\r\n\x1a\n"), "Invalid native PNG"
pixels = struct.unpack(">II", png[16:24])
png_path.write_bytes(png)
print(json.dumps({
    "pixels": pixels,
    "files": [{"path": str(p), "bytes": p.stat().st_size,
               "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
              for p in [png_path, xml_path]],
    "nodes": [{"label": n.get("text") or n.get("content-desc"),
               "bounds": n.get("bounds"), "class": n.get("class"),
               "clickable": n.get("clickable")}
              for n in tree.iter("node") if n.get("text") or n.get("content-desc")]
}, ensure_ascii=False))
