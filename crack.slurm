#!/bin/bash
#SBATCH --job-name=pwcrack
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=08:00:00
#SBATCH --output=crack_%j.log
# ------------------------------------------------------------
# SUBMIT WITH A REAL GPU PARTITION (find it: sinfo | grep -i gpu):
#     sbatch -p <GPU_PARTITION> crack.slurm
#
# Downloads are attempted INSIDE the job (see FETCH section). BUT compute nodes
# on most clusters have no internet. If the fetch fails, use the offline route:
#   - scp these over instead of downloading:
#       OneRuleToRuleThemStill.rule , dive.rule   (provided as files)
#       rockyou.txt.gz  ->  gunzip rockyou.txt.gz  (on the HPC)
#   - then this job skips the download (files already present) and just runs.
# If your cluster uses an HTTP proxy for outbound traffic, set it below.
# ------------------------------------------------------------
set -uo pipefail
# export https_proxy=http://PROXY_HOST:PORT ; export http_proxy=$https_proxy   # <-- uncomment/set if ITU requires a proxy

module load CUDA 2>/dev/null || module load cuda 2>/dev/null || module load CUDA/12.0.0 2>/dev/null || true

# ================= FETCH (download if missing; harmless if files already scp'd) =========
fetch(){ # fetch URL DEST
  local url="$1" dest="$2"
  [ -f "$dest" ] && { echo "have $dest"; return 0; }
  echo "downloading $dest ..."
  if   command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$dest" "$url"
  else echo "no curl/wget available"; return 1; fi
}
# rockyou (accept a pre-scp'd .gz too)
if [ ! -f rockyou.txt ]; then
  if [ -f rockyou.txt.gz ]; then gunzip -k rockyou.txt.gz
  else fetch https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt rockyou.txt || true; fi
fi
fetch https://raw.githubusercontent.com/stealthsploit/OneRuleToRuleThemStill/main/OneRuleToRuleThemStill.rule OneRuleToRuleThemStill.rule || true
# princeprocessor (optional; needs git+make+gcc)
if [ ! -x princeprocessor/src/pp64.bin ]; then
  git clone --depth 1 https://github.com/hashcat/princeprocessor.git >/dev/null 2>&1 && make -C princeprocessor/src >/dev/null 2>&1 || echo "prince build skipped"
fi

# ================= LOCATE HASHCAT =================
cd "${SLURM_SUBMIT_DIR:-$(pwd)}"          # run from where you submitted
if ! [ -x hashcat/hashcat ] && ! command -v hashcat >/dev/null 2>&1; then
  echo "building hashcat from source..."
  [ -d hashcat ] || git clone --depth 1 --branch v6.2.6 https://github.com/hashcat/hashcat.git
  make -j"$(nproc)" -C hashcat || { echo "ERROR: hashcat build failed (need git/make/gcc)"; exit 1; }
fi
if   [ -x hashcat/hashcat ];              then HC="$(pwd)/hashcat/hashcat"
elif command -v hashcat >/dev/null 2>&1;  then HC=hashcat
else echo "ERROR: hashcat not found after build"; exit 1; fi
echo "hashcat: $HC"; "$HC" --version

# ================= VERIFY INPUTS =================
HASHES=remaining_hashes.txt; ROCKYOU=rockyou.txt; ONERULE=OneRuleToRuleThemStill.rule
[ -s "$HASHES" ]  || { echo "ERROR: $HASHES missing/empty"; exit 1; }
[ -f "$ROCKYOU" ] || { echo "ERROR: rockyou.txt missing. Compute node has no internet — scp rockyou.txt.gz and gunzip it."; exit 1; }
[ -f "$ONERULE" ] || { echo "ERROR: $ONERULE missing — scp it over."; exit 1; }

POT="--potfile-path=found.pot"; COMMON="-m 1400 -w 4"
DIVE=$(ls dive.rule 2>/dev/null || find /usr /opt /apps "$(dirname "$HC")" -name dive.rule 2>/dev/null | head -1)
run(){ local label="$1"; shift; echo "=== $label ==="; $HC $POT $COMMON "$@" || echo "(pass failed/skipped, continuing)"; }

# ================= ATTACK LADDER (cheap/high-yield first) =================
run "rockyou x OneRule"       -a 0 -O "$HASHES" "$ROCKYOU" -r "$ONERULE"
[ -n "$DIVE" ] && run "rockyou x dive" -a 0 -O "$HASHES" "$ROCKYOU" -r "$DIVE"
run "custom x OneRule"        -a 0 -O "$HASHES" danish_privacy_wordlist.txt -r "$ONERULE"
run "combinator rockyou^2"    -a 1 "$HASHES" "$ROCKYOU" "$ROCKYOU"       # no -O: allow long passphrases
if [ -x princeprocessor/src/pp64.bin ]; then
  echo "=== PRINCE (passphrases) ==="
  ./princeprocessor/src/pp64.bin --pw-min=12 --pw-max=28 --elem-cnt-max=4 < prince_elements.txt \
    | $HC $POT $COMMON -a 0 "$HASHES" || echo "(prince skipped)"
fi
run "mask 8 lower+digit"      -a 3 -O "$HASHES" -1 '?l?d'   '?1?1?1?1?1?1?1?1'
# run "mask 8 mixed alnum"    -a 3 -O "$HASHES" -1 '?l?u?d' '?1?1?1?1?1?1?1?1'   # ~hours; uncomment if needed

# ================= RESULTS + SUBMISSION =================
echo "=== CRACKED (hash:plain) ==="; $HC $POT -m 1400 "$HASHES" --show
python3 reconcile.py found.pot
python3 make_submission.py
echo "Done -> submission file: etko-<N>-dark_orange.txt"
