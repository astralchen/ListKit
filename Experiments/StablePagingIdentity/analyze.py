#!/usr/bin/env python3
"""保存真实 UI 观察，不过滤失败，也不从 RTL offset 猜测页面位置。"""
import argparse
import json
import re
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("attachments", type=Path)
p.add_argument("log", type=Path)
p.add_argument("output", type=Path)
a = p.parse_args()
snapshots = {}
for test in json.loads((a.attachments / "manifest.json").read_text()):
    if not test.get("testIdentifier", "").startswith("StablePagingIdentityUITests/"):
        continue
    for attachment in test.get("attachments", []):
        file = a.attachments / attachment["exportedFileName"]
        if file.suffix not in (".txt", ".json"):
            continue
        try:
            data = json.loads(file.read_text())
        except (ValueError, UnicodeDecodeError):
            continue
        if isinstance(data, dict) and "ids" in data and "pageExtent" in data:
            name = attachment["suggestedHumanReadableName"].split("_0_")[0].removesuffix(".json")
            snapshots[name] = data
log = a.log.read_text()
edges = [{"stage": name, "error": float(error), "page": int(page)}
         for name, error, page in re.findall(r"IDENTITY_EDGE (\S+) error=(\S+) page=(\S+)", log)]
gestures = [{"stage": name, "from": int(old), "target": int(target), "actual": int(actual)}
            for name, old, target, actual in re.findall(
                r"IDENTITY_GESTURE (\S+) from=(\d+) target=(\d+) actual=(\d+)", log)]
result = {"snapshots": snapshots, "edges": edges, "gestures": gestures,
          "updates": [line for line in log.splitlines() if line.startswith("IDENTITY_UPDATE ")],
          "assertionFailures": [line for line in log.splitlines() if "error:" in line and "XCT" in line]}
result["summary"] = {"snapshots": len(snapshots), "edges": len(edges), "gestures": len(gestures),
                     "updates": len(result["updates"]), "failures": len(result["assertionFailures"]),
                     "maxAbsoluteEdgeError": max((abs(v["error"]) for v in edges), default=None)}
a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(result["summary"], ensure_ascii=False))
