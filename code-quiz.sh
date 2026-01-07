#!/usr/bin/env sh
set -eu

# Usage examples:
#   ./code-quiz.sh
#   ./code-quiz.sh frontend/src -c 2
#   ./code-quiz.sh . --context 1 --reveal 20

ROOT="."
CONTEXT=1   # lines above/below shown before reveal
REVEAL=10   # lines above/below shown on reveal

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
    -h|--help)
      echo "Usage: $0 [path] [-c|--context N] [-r|--reveal N]"
      echo "  path            root folder (default: .)"
      echo "  -c, --context N show ±N lines before reveal (default: 1)"
      echo "  -r, --reveal N  show ±N lines on reveal (default: 10)"
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

FILE="$(printf "%s\n" "$FILES" | awk 'BEGIN{srand()} {a[NR]=$0} END{print a[int(rand()*NR)+1]}')"

TOTAL_LINES="$(awk 'END{print NR}' "$FILE" 2>/dev/null || echo 0)"
if [ "$TOTAL_LINES" -le 0 ]; then
  echo "Could not read file: $FILE"
  exit 1
fi

LINE_NO="$(awk -v n="$TOTAL_LINES" 'BEGIN{srand(); print int(rand()*n)+1}')"
LINE="$(awk -v n="$LINE_NO" 'NR==n{print; exit}' "$FILE")"

# Avoid empty/whitespace-only lines (retry)
i=0
while [ -z "$(printf "%s" "$LINE" | tr -d '[:space:]')" ] && [ $i -lt 15 ]; do
  LINE_NO="$(awk -v n="$TOTAL_LINES" 'BEGIN{srand(); print int(rand()*n)+1}')"
  LINE="$(awk -v n="$LINE_NO" 'NR==n{print; exit}' "$FILE")"
  i=$((i+1))
done

RED="$(printf '\033[31m')"
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

# --- show pre-context (before reveal) ---
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

# --- reveal solution + bigger context ---
REV_FROM=$((LINE_NO - REVEAL))
REV_TO=$((LINE_NO + REVEAL))
[ "$REV_FROM" -lt 1 ] && REV_FROM=1
[ "$REV_TO" -gt "$TOTAL_LINES" ] && REV_TO="$TOTAL_LINES"


GREEN="$(printf '\033[32m')"

echo "File: ${GREEN}${FILE}${RESET}"
echo "Line: $LINE_NO"
echo
echo "Context (±$REVEAL):"
print_range "$REV_FROM" "$REV_TO" "$REV_FROM"
