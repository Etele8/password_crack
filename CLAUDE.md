# CLAUDE.md — Password-cracking challenge (ITU HPC continuation)

Context for continuing this task with Claude Code inside **Slurm jobs on hpc.itu.dk**.
Read this fully before running anything — it records what already worked, what
already failed, and how to not burn GPU hours repeating dead ends.

---

## 1. Goal

University challenge: given `passwords.enc` (1003 accounts as `<id>:<sha256>`,
unsalted SHA-256), crack as many as possible. Submit a `.txt` of
`<id>:<plaintext>` pairs. Prize goes to whoever cracks the most.

Submission filename: **`etko-<count>-dark_orange.txt`** (initials `etko`,
Rittersport `dark_orange`). `<count>` = number of **account lines** in the file.

---

## 2. Current status (start here)

- **1003 accounts**, but only **1001 unique hashes** — 2 passwords are reused,
  so a cracked hash can map to more than one id. Always map hash → *list* of ids.
- **975 / 1001 unique hashes cracked → 977 / 1003 accounts.**
- **26 unique hashes remain.** They are in `remaining_hashes.txt`.
- Best submission so far: `etko-977-dark_orange.txt` (already valid, `$HEX[]`
  decoded). Only regenerate it upward.

The 26 survivors resisted: full rockyou, best64, rockyou-30000, d3ad0ne, dive,
OneRule, a Danish+privacy custom list, hybrid word+digit, numeric/phone masks,
and a PRINCE passphrase run (210M candidates). They are NOT simple
dictionary words or 2-word concatenations of common words.

---

## 3. Why HPC matters (hardware, not method)

The previous run was **1 CPU core, ~1 MH/s, no GPU**. Every large rule pass over
rockyou only ever covered its front portion before timing out. That is the whole
reason work stalled.

A single datacenter GPU (V100/A100-class) does unsalted SHA-256 at **~13–22 GH/s**
— roughly **15,000–20,000×** faster. This makes previously-infeasible passes finish
in seconds to hours. It does **not** change the method, and it does **not** make
high-entropy random passwords crackable (see §7 stop criteria).

---

## 4. Files in this directory

| File | What it is |
|------|-----------|
| `passwords.enc` | full target set, 1003 `id:sha256` lines (bring this) |
| `remaining_hashes.txt` | the 26 uncracked hashes, one per line (hashcat input) |
| `found.pot` | hashcat potfile — `hash:plain`, grows as you crack; persist across jobs |
| `found.json` | merged map `hash -> plain` (our reconciled truth) |
| `danish_privacy_wordlist.txt` | bespoke Danish + security/privacy wordlist (~51k) |
| `prince_elements.txt` | frequency-ordered element pool for PRINCE (~7k) |
| `crack_lib.py` | parsing + hex-decode helpers |
| `reconcile.py` | fold hashcat potfile/`--show` output into `found.json` |
| `make_submission.py` | write `etko-<N>-dark_orange.txt` from `found.json` |
| `crack.slurm` | Slurm job with the attack ladder |

You still need to fetch (not included, too big / external):
`rockyou.txt`, `OneRuleToRuleThemStill.rule`, hashcat's `dive.rule` /
`generated2.rule`, and `pp64.bin` (princeprocessor).

---

## 5. Environment setup on ITU HPC

**Compute nodes usually have no internet.** Download wordlists/rules on the
**login node** first, into the job directory, then submit.

```bash
# login node, one-time
wget https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt
wget https://raw.githubusercontent.com/stealthsploit/OneRuleToRuleThemStill/main/OneRuleToRuleThemStill.rule
# princeprocessor (build once):
git clone --depth 1 https://github.com/hashcat/princeprocessor.git && make -C princeprocessor/src
# hashcat: prefer a module; else the release binary works with CUDA loaded
module avail 2>&1 | grep -i -E "cuda|hashcat"
sinfo   # find the GPU partition name and put it in crack.slurm
```

Confirm the GPU is visible before a long run: `hashcat -I` and `hashcat -b -m 1400`.

**AUP note:** password-cracking is a monitored workload on shared clusters.
Confirm the acceptable-use policy allows it / give HPC admins or the instructor a
heads-up that this is sanctioned coursework, before queueing big jobs.

---

## 6. Attack ladder (ordered by yield-per-cost)

Run in this order. hashcat auto-skips hashes already in the potfile, so re-runs
are cheap. Mode is `-m 1400`. Use `--potfile-path=found.pot` on every call.

> **`-O` caveat:** the optimized kernel caps candidate length (~31 chars). One
> already-cracked password was 27 chars, so long passphrases exist. Use `-O` for
> the rule/mask passes (fast, short candidates) but **drop `-O`** for PRINCE and
> combinator so long passphrases aren't silently skipped.

1. **rockyou × OneRule** — to completion. Was only partial on CPU; this is the
   single most likely to catch survivors. `-a 0 remaining_hashes.txt rockyou.txt -r OneRuleToRuleThemStill.rule`
2. **rockyou × dive.rule**, then **generated2.rule**, **d3ad0ne.rule** — different
   mutation coverage, all previously partial.
3. **Danish/privacy custom × OneRule** — `danish_privacy_wordlist.txt` with heavy rules.
4. **Combinator (2-word passphrases)** — `-a 1 remaining_hashes.txt rockyou.txt rockyou.txt` (no `-O`).
5. **PRINCE (multi-word passphrases)** — bigger pool, longer length, no `-O`:
   `./pp64.bin --pw-min=12 --pw-max=28 --elem-cnt-max=4 < prince_elements.txt | hashcat -a 0 -m 1400 remaining_hashes.txt`
   Consider a larger element pool than the 7k provided if steps 1–4 leave many.
6. **Masks** (expensive; multi-GPU): 8× lowercase+digit (`-1 ?l?d ?1?1?1?1?1?1?1?1`,
   minutes) → 8× mixed alnum (`-1 ?l?u?d ...`, hours). Full printable `?a×8` is
   ~days on one GPU — only as a last resort.

**Resuming across Slurm wall-time:** long jobs get killed at `--time`. Use
`--session=NAME` and re-submit with `--restore` to continue the same pass instead
of restarting it. The potfile also makes any re-run skip solved hashes.

---

## 7. Stop criteria (don't waste the allocation)

After steps 1–5, whatever remains is almost certainly **random / high-entropy**
(password-manager output or long random passphrases). Reality check:

- 8-char full printable (95⁸ ≈ 6.6×10¹⁵): ~4–6 days, one GPU.
- 9-char full printable: >1 year, one GPU. **Infeasible.**

If a handful survive the wordlist/rule/PRINCE passes, **stop** — they're not worth
GPU-days. 977 + whatever steps 1–6 recover is the final number.

---

## 8. Producing the submission

hashcat gives `hash:plain`, not `id:plain`. Workflow after any job:

```bash
python3 reconcile.py found.pot        # merge new cracks into found.json
python3 make_submission.py            # writes etko-<N>-dark_orange.txt
```

Format rules baked into `make_submission.py` (keep them):
- One line per **account id**, sorted by id. Reused-password hashes emit one line
  per id.
- Decode hashcat `$HEX[...]` wrappers to real text (e.g. `$HEX[47697474653a]`
  → `Gitte:` — a password containing a colon; the line is still `id:Gitte:`,
  which is fine, the parser splits on the first colon only).
- `<N>` in the filename = total account lines written.

---

## 9. Reusable scripts (recreate if missing)

### `crack_lib.py`
```python
import re, os, binascii

TARGET_FILE = os.environ.get("PW_TARGET", "passwords.enc")

def load_targets(path=TARGET_FILE):
    """hash(lower) -> sorted list of int ids. Handles reused passwords."""
    h2ids = {}
    with open(path, "r", newline="") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            m = re.match(r"^(\d+):([0-9a-fA-F]{64})$", line)
            if m:
                h2ids.setdefault(m.group(2).lower(), []).append(int(m.group(1)))
    for h in h2ids:
        h2ids[h].sort()
    return h2ids

def decode_plain(pw):
    """Decode hashcat $HEX[...] wrappers; leave normal plaintext untouched."""
    if pw.startswith("$HEX[") and pw.endswith("]"):
        try:
            b = binascii.unhexlify(pw[5:-1])
            try:
                return b.decode("utf-8")
            except UnicodeDecodeError:
                return b.decode("latin-1")
        except binascii.Error:
            return pw
    return pw
```

### `reconcile.py`
```python
import sys, json, os
import crack_lib as C

pot = sys.argv[1] if len(sys.argv) > 1 else "found.pot"
found = {}
if os.path.exists("found.json"):
    found = json.load(open("found.json"))

targets = C.load_targets()
n0 = len(found)
for line in open(pot, "r", errors="replace"):
    line = line.rstrip("\n")
    if ":" not in line:
        continue
    h, plain = line.split(":", 1)          # hash is 64 hex chars, no colon
    h = h.lower()
    if h in targets:
        found[h] = plain                   # store raw (may be $HEX[...]); decode at output
json.dump(found, open("found.json", "w"))
print(f"added {len(found)-n0}, total {len(found)}/{len(targets)}, "
      f"remaining {len(targets)-len(found)}")

# refresh remaining_hashes.txt for the next job
rem = [h for h in targets if h not in found]
open("remaining_hashes.txt", "w").write("\n".join(rem) + ("\n" if rem else ""))
```

### `make_submission.py`
```python
import json, os
import crack_lib as C

INITIALS = "etko"
RITTER   = "dark_orange"

targets = C.load_targets()                 # hash -> [ids]
found   = json.load(open("found.json")) if os.path.exists("found.json") else {}

rows = []
for h, ids in targets.items():
    if h in found:
        plain = C.decode_plain(found[h])
        for i in ids:
            rows.append((i, plain))
rows.sort(key=lambda x: x[0])

out = f"{INITIALS}-{len(rows)}-{RITTER}.txt"
with open(out, "w", encoding="utf-8") as f:
    for i, plain in rows:
        f.write(f"{i}:{plain}\n")
print(f"wrote {out}: {len(rows)}/{sum(len(v) for v in targets.values())} accounts, "
      f"{len(found)}/{len(targets)} unique hashes")
```

---

## 10. Housekeeping

- `passwords.enc` is just a name — contents are plain `id:sha256`, not encrypted.
- Ignore any `hacktivist_messages.csv` — that was an unrelated wrong-file upload,
  not part of this challenge. Do not put it in the submission.
- Never regenerate the submission with a *lower* count than 977.
