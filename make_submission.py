import json, os
import crack_lib as C
INITIALS = "etko"; RITTER = "dark_orange"
targets = C.load_targets()
found = json.load(open("found.json")) if os.path.exists("found.json") else {}
rows = []
for h, ids in targets.items():
    if h in found:
        plain = C.decode_plain(found[h])
        for i in ids: rows.append((i, plain))
rows.sort(key=lambda x: x[0])
out = f"{INITIALS}-{len(rows)}-{RITTER}.txt"
with open(out, "w", encoding="utf-8") as f:
    for i, plain in rows: f.write(f"{i}:{plain}\n")
print(f"wrote {out}: {len(rows)}/{sum(len(v) for v in targets.values())} accounts, {len(found)}/{len(targets)} unique hashes")
