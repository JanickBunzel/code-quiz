#!/usr/bin/env sh
set -eu

# Usage examples:
#   ./code-quiz.sh
#   ./code-quiz.sh frontend/src -c 2
#   ./code-quiz.sh . --context 1 --reveal 20
#   ./code-quiz.sh . --linecount
#   ./code-quiz.sh -l

ROOT="."
CONTEXT=1   # lines above/below shown before reveal
REVEAL=10   # lines above/below shown on reveal
LINECOUNT=0 # 1 => print total eligible line count and exit

# --- arg parsing (POSIX sh) ---
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--context)
      [ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
      CONTEXT="$2"
      shift 2
      ;;
    -r|--reveal)
      [ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
      REVEAL="$2"
      shift 2
      ;;
    -l|--linecount)
      LINECOUNT=1
      shift 1
      ;;
    -h|--help)
      echo "Usage: $0 [path] [-c|--context N] [-r|--reveal N] [-l|--linecount]"
      echo "  path              root folder (default: .)"
      echo "  -c, --context N   show ±N lines before reveal (default: 1)"
      echo "  -r, --reveal N    show ±N lines on reveal (default: 10)"
      echo "  -l, --linecount   print total eligible line count and exit"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      # first positional arg is root (only once)
      if [ "$ROOT" = "." ] && [ -n "${1:-}" ]; then
        ROOT="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

# validate numeric args
case "$CONTEXT" in (""|*[!0-9]*) echo "context must be a non-negative integer" >&2; exit 2;; esac
case "$REVEAL"  in (""|*[!0-9]*) echo "reveal must be a non-negative integer"  >&2; exit 2;; esac

# --- file selection ---
FILES="$(find "$ROOT" \
  -type f \
  ! -path '*/node_modules/*' \
  ! -path '*/dist/*' \
  ! -path '*/build/*' \
  ! -path '*/.git/*' \
  ! -path '*/.next/*' \
  ! -path '*/.turbo/*' \
  ! -path '*/coverage/*' \
  ! -path '*/.cache/*' \
  ! -name '*.lock' \
  ! -name '*.min.*' \
  ! -name '*.map' \
  ! -name '*.png' \
  ! -name '*.jpg' \
  ! -name '*.jpeg' \
  ! -name '*.gif' \
  ! -name '*.webp' \
  ! -name '*.ico' \
  ! -name '*.pdf' \
  ! -name '*.zip' \
  ! -name '*.gz' \
  ! -name '*.tar' \
  ! -name '*.DS_Store' \
  -print 2>/dev/null
)"

if [ -z "${FILES:-}" ]; then
  echo "No files found under: $ROOT"
  exit 1
fi

# --- linecount arc ---
if [ "$LINECOUNT" -eq 1 ]; then
  total_lines=0
  total_files=0

  # Read newline-separated file list
  printf "%s\n" "$FILES" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    total_files=$((total_files + 1))
    n="$(awk 'END{print NR}' "$f" 2>/dev/null || printf "0")"
    case "$n" in (""|*[!0-9]*) n=0;; esac
    total_lines=$((total_lines + n))
    # POSIX sh: variables in a pipeline subshell won't survive outside.
    # So we print intermediate totals and recompute below without relying on these.
    printf "%s\t%s\n" "$n" "$f"
  done | awk '
    { sum += $1; files += 1 }
    END {
      printf "Eligible files: %d\nEligible lines: %d\n", files, sum
    }
  '
  exit 0
fi

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
RESET="$(printf '\033[0m')"

# Helper to print context with line numbers
print_range() {
  _from="$1"
  _to="$2"
  _v="$3" # nl starting line number
  _color="${4:-}" # optional color, default to empty string
  if [ -n "$_color" ]; then
    awk -v from="$_from" -v to="$_to" -v v="$_v" -v COLOR="$_color" -v RESET="$RESET" '{
      if (NR >= from && NR <= to) {
        num = v + NR - from
        printf "%s%d: %s%s\n", COLOR, num, $0, RESET
      }
    }' "$FILE"
  else
    awk -v from="$_from" -v to="$_to" -v v="$_v" '{
      if (NR >= from && NR <= to) {
        num = v + NR - from
        printf "%d: %s\n", num, $0
      }
    }' "$FILE"
  fi
}

# --- main game loop ---
while :; do

  # Better per-round seed (avoids repeats when looping fast)
  # date +%s%N might not exist everywhere; fall back to seconds.
  NOW_NS="$(date +%s%N 2>/dev/null || date +%s)"
  SEED_STR="$$-$NOW_NS"
  SEED_NUM="$(printf "%s" "$SEED_STR" | cksum | awk '{print $1}')"

  FILE="$(printf "%s\n" "$FILES" | awk -v seed="$SEED_NUM" '
    BEGIN { srand(seed) }
    { a[NR] = $0 }
    END { print a[int(rand() * NR) + 1] }
  ')"

  TOTAL_LINES="$(awk 'END{print NR}' "$FILE" 2>/dev/null || echo 0)"
  if [ "$TOTAL_LINES" -le 0 ]; then
    echo "Could not read file: $FILE" >&2
    continue
  fi

  LINE_NO="$(awk -v n="$TOTAL_LINES" -v seed="$SEED_NUM" '
    BEGIN { srand(seed + 1); print int(rand() * n) + 1 }
  ')"
  LINE="$(awk -v n="$LINE_NO" 'NR==n{print; exit}' "$FILE")"

  # Avoid empty/whitespace-only lines (retry)
  i=0
  while [ -z "$(printf "%s" "$LINE" | tr -d '[:space:]')" ] && [ $i -lt 15 ]; do
    LINE_NO="$(awk -v n="$TOTAL_LINES" -v seed="$SEED_NUM" -v i="$i" '
      BEGIN { srand(seed + 2 + i); print int(rand() * n) + 1 }
    ')"
    LINE="$(awk -v n="$LINE_NO" 'NR==n{print; exit}' "$FILE")"
    i=$((i+1))
  done

  PRE_FROM=$((LINE_NO - CONTEXT))
  PRE_TO=$((LINE_NO + CONTEXT))
  [ "$PRE_FROM" -lt 1 ] && PRE_FROM=1
  [ "$PRE_TO" -gt "$TOTAL_LINES" ] && PRE_TO="$TOTAL_LINES"

  echo ""
  echo "🎯 RANDOM LINE (showing context ±$CONTEXT)"
  echo "------------------------------------------------------------"
  print_range "$PRE_FROM" "$PRE_TO" "$PRE_FROM" "$RED"
  echo "------------------------------------------------------------"
  echo
  echo "Think: where is this? Press Enter to reveal…"
  read -r _

  REV_FROM=$((LINE_NO - REVEAL))
  REV_TO=$((LINE_NO + REVEAL))
  [ "$REV_FROM" -lt 1 ] && REV_FROM=1
  [ "$REV_TO" -gt "$TOTAL_LINES" ] && REV_TO="$TOTAL_LINES"

  echo "File: ${GREEN}${FILE}${RESET}"
  echo "Line: $LINE_NO"
  echo
  echo "Context (±$REVEAL):"
  print_range "$REV_FROM" "$REV_TO" "$REV_FROM"

  echo
  echo "Press Enter to go again"
  read -r _
done
