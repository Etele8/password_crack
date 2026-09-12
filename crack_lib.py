import re, os, binascii
TARGET_FILE = os.environ.get("PW_TARGET", "passwords.enc")
def load_targets(path=TARGET_FILE):
    h2ids = {}
    with open(path, "r", newline="") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            m = re.match(r"^(\d+):([0-9a-fA-F]{64})$", line)
            if m:
                h2ids.setdefault(m.group(2).lower(), []).append(int(m.group(1)))
    for h in h2ids: h2ids[h].sort()
    return h2ids
def decode_plain(pw):
    if pw.startswith("$HEX[") and pw.endswith("]"):
        try:
            b = binascii.unhexlify(pw[5:-1])
            try: return b.decode("utf-8")
            except UnicodeDecodeError: return b.decode("latin-1")
        except binascii.Error: return pw
    return pw
