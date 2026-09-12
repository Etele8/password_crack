#!/bin/bash
#SBATCH --job-name=pwcrack
#SBATCH --partition=gpu           # <-- set to ITU's GPU partition name (check `sinfo`)
#SBATCH --gres=gpu:1              # request 1 GPU (try :2 or :4 for masks/combinator)
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=08:00:00
#SBATCH --output=crack_%j.log

set -e
# --- Environment: adjust module names to what ITU provides (`module avail`) ---
module load CUDA 2>/dev/null || true
# If hashcat isn't a module, download the release binary (needs NVIDIA driver + CUDA):
#   wget https://github.com/hashcat/hashcat/releases/download/v6.2.6/hashcat-6.2.6.7z && 7z x hashcat-6.2.6.7z
HASHCAT=${HASHCAT:-hashcat}

# --- Inputs (scp these into the job dir) ---
HASHES=remaining_hashes.txt          # the 26 uncracked SHA-256 hashes
POT=--potfile-path=found.pot
M="-m 1400 -w 4 -O"                  # 1400 = SHA-256; -O ok since these are short-ish

# --- Wordlists / rules (fetch on the login node beforehand if no internet on compute nodes) ---
# rockyou.txt, OneRuleToRuleThemStill.rule, danish_privacy_wordlist.txt, prince_elements.txt
ROCKYOU=rockyou.txt
ONERULE=OneRuleToRuleThemStill.rule

echo "GPU visible to hashcat:"; $HASHCAT -I 2>/dev/null | grep -i -E "Name|Type" || true

# 1) rockyou + OneRule to completion (highest yield; was only partial on CPU)
$HASHCAT $POT $M -a 0 $HASHES $ROCKYOU -r $ONERULE

# 2) rockyou + dive (different mutation coverage)
$HASHCAT $POT $M -a 0 $HASHES $ROCKYOU -r /path/to/rules/dive.rule || true

# 3) Danish + privacy custom list, heavy rules
$HASHCAT $POT $M -a 0 $HASHES danish_privacy_wordlist.txt -r $ONERULE || true

# 4) Combinator: two-word passphrases (rockyou x rockyou)
$HASHCAT $POT $M -a 1 $HASHES $ROCKYOU $ROCKYOU || true

# 5) PRINCE: multi-word passphrases from the element pool (needs princeprocessor pp64.bin)
#    ./pp64.bin --pw-min=12 --pw-max=28 --elem-cnt-max=4 < prince_elements.txt | $HASHCAT $POT $M -a 0 $HASHES

# 6) Masks (run on multi-GPU; these are the long ones)
$HASHCAT $POT $M -a 3 $HASHES -1 ?l?d '?1?1?1?1?1?1?1?1'                 # 8x lowercase+digit  (~minutes)
$HASHCAT $POT $M -a 3 $HASHES -1 ?l?u?d '?1?1?1?1?1?1?1?1' || true       # 8x mixed alnum      (~hours)
# $HASHCAT $POT $M -a 3 $HASHES ?a?a?a?a?a?a?a?a                          # 8x full printable   (~days; only if desperate)

echo "=== CRACKED ==="
$HASHCAT $POT -m 1400 $HASHES --show
