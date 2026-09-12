import sys, json, os
import crack_lib as C
pot = sys.argv[1] if len(sys.argv) > 1 else "found.pot"
found = json.load(open("found.json")) if os.path.exists("found.json") else {}
targets = C.load_targets(); n0 = len(found)
for line in open(pot, "r", errors="replace"):
    line = line.rstrip("\n")
    if ":" not in line: continue
    h, plain = line.split(":", 1); h = h.lower()
    if h in targets: found[h] = plain
json.dump(found, open("found.json", "w"))
print(f"added {len(found)-n0}, total {len(found)}/{len(targets)}, remaining {len(targets)-len(found)}")
rem = [h for h in targets if h not in found]
open("remaining_hashes.txt", "w").write("\n".join(rem) + ("\n" if rem else ""))
