#!/usr/bin/env bash
# dev-cleanup: reclaim disk space from dev projects you haven't touched in a while.
#
# Finds JS and PHP projects under the given folders and removes regenerable
# directories (node_modules, build output, framework caches, composer vendor)
# from projects with no file changes in the last N days.
#
# Dry run by default; nothing is deleted without --yes. Run with --help.

VERSION="1.0.0"

DAYS=30
APPLY=false
DROPBOX=false
DOCKER=false
XCODE=false
GRADLE=false
BREW=false
PNPM=false
TARGETS=()

# Always regenerable when they sit next to a package.json.
JS_SAFE=(node_modules .next .nuxt .svelte-kit .angular .turbo .parcel-cache storybook-static)
# Generic names that could be hand-written source: only removed when git says they're ignored.
JS_GENERIC=(dist build out coverage .cache)
# Skipped while checking whether a project has recent changes.
PRUNE_NAMES=(.git node_modules vendor "${JS_SAFE[@]}" "${JS_GENERIC[@]}")

usage() {
  cat <<'EOF'
dev-cleanup: reclaim disk space from dev projects you haven't touched in a while.

Usage:
  dev-cleanup [options] [folder ...]       (default folder: current directory)

By default it only REPORTS what it would remove. Add --yes to delete.

What gets removed, only from projects with no file changes in --days:
  next to package.json     node_modules .next .nuxt .svelte-kit .angular .turbo
                           .parcel-cache storybook-static
                           dist build out coverage .cache  (only if git-ignored)
  next to composer.json    vendor  (only if composer.lock exists)

Options:
  -y, --yes        Actually delete (default is a dry run)
  -d, --days N     Treat projects as stale after N days without changes (default 30, 0 = all)
      --dropbox    Mark heavy folders in active projects as ignored by Dropbox (macOS)
      --docker     docker system prune -af  (unused images, stopped containers, build cache;
                   volumes are never touched)
      --xcode      Clear Xcode DerivedData
      --gradle     Clear ~/.gradle/caches
      --brew       brew cleanup --prune=7
      --pnpm       pnpm store prune
      --system     All of --docker --xcode --gradle --brew --pnpm
  -h, --help       Show this help
  -V, --version    Show version

Examples:
  dev-cleanup ~/code                 # see what would be reclaimed
  dev-cleanup --yes ~/code           # reclaim it
  dev-cleanup --yes --days 90 ~/code ~/projects
EOF
}

die() { echo "dev-cleanup: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes|--apply) APPLY=true ;;
    -d|--days) [ $# -ge 2 ] || die "--days needs a number"; DAYS="$2"; shift ;;
    --days=*) DAYS="${1#*=}" ;;
    --dropbox) DROPBOX=true ;;
    --docker) DOCKER=true ;;
    --xcode) XCODE=true ;;
    --gradle) GRADLE=true ;;
    --brew) BREW=true ;;
    --pnpm) PNPM=true ;;
    --system) DOCKER=true; XCODE=true; GRADLE=true; BREW=true; PNPM=true ;;
    -h|--help) usage; exit 0 ;;
    -V|--version) echo "$VERSION"; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do TARGETS+=("$1"); shift; done; break ;;
    -*) echo "dev-cleanup: unknown option $1" >&2; echo >&2; usage >&2; exit 2 ;;
    *) TARGETS+=("$1") ;;
  esac
  shift
done

case "$DAYS" in ''|*[!0-9]*) die "--days must be a whole number" ;; esac
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(.)

# ── Helpers ──────────────────────────────────────────────────

TOTAL_KB=0
REMOVED=0
ACTIVE=0
SEEN=$'\n'

pretty() { local p="$1"; echo "${p/#$HOME/~}"; }

human() {
  awk -v k="$1" 'BEGIN {
    split("KB MB GB TB", u, " "); i = 1
    while (k >= 1024 && i < 4) { k /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.1f %s"), k, u[i]
  }'
}

size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1 + 0}'; }

reclaim() {
  local path="$1" kb
  kb=$(size_kb "$path")
  TOTAL_KB=$((TOTAL_KB + kb))
  REMOVED=$((REMOVED + 1))
  if $APPLY; then
    rm -rf -- "$path" && printf '  removed       %9s  %s\n' "$(human "$kb")" "$(pretty "$path")"
  else
    printf '  would remove  %9s  %s\n' "$(human "$kb")" "$(pretty "$path")"
  fi
}

git_ignored() { git -C "$1" check-ignore -q -- "$2" 2>/dev/null; }

# Build the find expression that skips heavy dirs: \( -name a -o -name b ... \)
PRUNE_EXPR=()
for n in "${PRUNE_NAMES[@]}"; do
  PRUNE_EXPR+=(-name "${n##*/}" -o)
done
unset 'PRUNE_EXPR[${#PRUNE_EXPR[@]}-1]'

has_recent_changes() {
  [ "$DAYS" -eq 0 ] && return 1
  [ -n "$(find "$1" -mindepth 1 \( "${PRUNE_EXPR[@]}" \) -prune -o -type f -mtime "-$DAYS" -print 2>/dev/null | head -n 1)" ]
}

dropbox_ignore() {
  local dir="$1"
  xattr -p com.dropbox.ignored "$dir" >/dev/null 2>&1 && return
  if $APPLY; then
    xattr -w com.dropbox.ignored 1 "$dir" 2>/dev/null
    xattr -w 'com.apple.fileprovider.ignore#P' 1 "$dir" 2>/dev/null
    echo "  dropbox-ignored         $(pretty "$dir")"
  else
    echo "  would dropbox-ignore    $(pretty "$dir")"
  fi
}

process_project() {
  local proj="$1" found=() n
  if [ -f "$proj/package.json" ]; then
    for n in "${JS_SAFE[@]}"; do
      [ -d "$proj/$n" ] && found+=("$proj/$n")
    done
    for n in "${JS_GENERIC[@]}"; do
      [ -d "$proj/$n" ] && git_ignored "$proj" "$n" && found+=("$proj/$n")
    done
  fi
  if [ -f "$proj/composer.json" ] && [ -f "$proj/composer.lock" ] && [ -d "$proj/vendor" ]; then
    found+=("$proj/vendor")
  fi
  [ ${#found[@]} -eq 0 ] && return

  if has_recent_changes "$proj"; then
    ACTIVE=$((ACTIVE + 1))
    if $DROPBOX; then
      for n in "${found[@]}"; do dropbox_ignore "$n"; done
    fi
    return
  fi

  echo "$(pretty "$proj")"
  for n in "${found[@]}"; do reclaim "$n"; done
}

scan() {
  local target="$1" manifest proj
  while IFS= read -r -d '' manifest; do
    proj="$(dirname "$manifest")"
    case "$SEEN" in *$'\n'"$proj"$'\n'*) continue ;; esac
    SEEN="$SEEN$proj"$'\n'
    process_project "$proj"
  done < <(find "$target" \
    \( -name node_modules -o -name .git -o -name vendor -o -path "$HOME/Library" -o -path "$HOME/.Trash" \) -prune \
    -o \( -name package.json -o -name composer.json \) -type f -print0 2>/dev/null)
}

clear_dir_contents() {
  local dir="$1" label="$2" kb
  if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
    echo "  $label: nothing to clear"
    return
  fi
  kb=$(size_kb "$dir")
  TOTAL_KB=$((TOTAL_KB + kb))
  if $APPLY; then
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null
    echo "  $label: cleared $(human "$kb")"
  else
    echo "  $label: would clear $(human "$kb")"
  fi
}

# ── Run ──────────────────────────────────────────────────────

if $APPLY; then MODE="deleting"; else MODE="dry run, nothing will be deleted"; fi
echo "dev-cleanup $VERSION  ($(date '+%Y-%m-%d %H:%M'), $MODE)"
if [ "$DAYS" -eq 0 ]; then echo "Stale after: any age"; else echo "Stale after: $DAYS days without changes"; fi
echo

for t in "${TARGETS[@]}"; do
  [ -d "$t" ] || die "not a folder: $t"
  t="$(cd "$t" && pwd -P)"
  [ "$t" = "/" ] && die "refusing to scan the whole disk; pick a folder like ~/code"
  echo "Scanning $(pretty "$t")"
  scan "$t"
  echo
done

if $DOCKER || $XCODE || $GRADLE || $BREW || $PNPM; then
  echo "System caches"
  $XCODE && clear_dir_contents "$HOME/Library/Developer/Xcode/DerivedData" "Xcode DerivedData"
  $GRADLE && clear_dir_contents "$HOME/.gradle/caches" "Gradle caches"
  if $DOCKER; then
    if ! command -v docker >/dev/null 2>&1; then
      echo "  Docker: not installed"
    elif ! docker info >/dev/null 2>&1; then
      echo "  Docker: not running, skipped"
    elif $APPLY; then
      docker system prune -af 2>&1 | tail -n 1 | sed 's/^/  Docker: /'
    else
      echo "  Docker: would run 'docker system prune -af'. Reclaimable now:"
      docker system df 2>/dev/null | sed 's/^/    /'
    fi
  fi
  if $BREW; then
    if ! command -v brew >/dev/null 2>&1; then
      echo "  Homebrew: not installed"
    elif $APPLY; then
      brew cleanup --prune=7 >/dev/null 2>&1; echo "  Homebrew: cleaned"
    else
      echo "  Homebrew: would run 'brew cleanup --prune=7'"
    fi
  fi
  if $PNPM; then
    if ! command -v pnpm >/dev/null 2>&1; then
      echo "  pnpm: not installed"
    elif $APPLY; then
      pnpm store prune >/dev/null 2>&1; echo "  pnpm: store pruned"
    else
      echo "  pnpm: would run 'pnpm store prune'"
    fi
  fi
  echo
fi

if $APPLY; then
  echo "Reclaimed about $(human "$TOTAL_KB") ($REMOVED folders)."
else
  echo "Would reclaim about $(human "$TOTAL_KB") ($REMOVED folders)."
fi
[ "$ACTIVE" -gt 0 ] && echo "Left alone $ACTIVE active project(s) changed in the last $DAYS days."
$APPLY || { [ "$REMOVED" -gt 0 ] && echo "Run again with --yes to delete."; }
$APPLY && [ "$REMOVED" -gt 0 ] && echo "To restore a project later: npm/pnpm/yarn install, or composer install."
exit 0
