#!/usr/bin/env bash
# Build and install Macadam (beta) at a specific app version for local Maestro tests.
#
# Two separate things happen:
#   1. CODE  — git checkout of tag vX.Y.Z or branch release/X.Y.Z
#   2. LABEL — app.json "version" patched locally (never committed) + prebuild
#
# Changing app.json alone does NOT pull in that version's code. The checkout does.
#
# Usage:
#   ./scripts/build-app-at-version.sh 8.3.1 android
#   ./scripts/build-app-at-version.sh 8.3.1 ios
#   SIM_NAME="iPhone 15 Pro" ./scripts/build-app-at-version.sh 8.3.1 ios
#   ALLOW_DEV_FALLBACK=1 ./scripts/build-app-at-version.sh 8.4.0 android
#
# Options / env:
#   MACADAM_APP_ROOT   path to macadam-app repo (default: ~/macadam-app)
#   PREBUILD_CLEAN=1   expo prebuild --clean (slower; use if native project looks stale)
#   STAY_ON_VERSION=1  do not return to the original git ref after the build
#   SKIP_GIT=1         skip checkout — patch app.json on current branch (label only)
#   GIT_REF=origin/dev force checkout this ref (overrides auto-resolve)
#   ALLOW_DEV_FALLBACK=1  if no tag/release branch, use origin/dev (how CI builds 8.4.0)
#   SIM_NAME="iPhone 15"  iOS simulator name (ios only)
#   ANDROID_DEVICE=emulator-5554  Android device id (auto-detected if omitted)
#
# The script never commits. On exit it restores app.json and returns to your
# previous git ref (unless STAY_ON_VERSION=1).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="${MACADAM_APP_ROOT:-$HOME/macadam-app}"
VERSION="${1:-}"
PLATFORM="${2:-}"
PREBUILD_CLEAN="${PREBUILD_CLEAN:-0}"
STAY_ON_VERSION="${STAY_ON_VERSION:-0}"
SKIP_GIT="${SKIP_GIT:-0}"
GIT_REF="${GIT_REF:-}"
ALLOW_DEV_FALLBACK="${ALLOW_DEV_FALLBACK:-0}"
SIM_NAME="${SIM_NAME:-}"

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [ -z "$VERSION" ] || [ -z "$PLATFORM" ]; then
  usage 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Invalid version '$VERSION'. Expected format: X.Y.Z (e.g. 8.3.1)"
  exit 1
fi

case "$PLATFORM" in
  android|ios) ;;
  *)
    echo "❌ Unknown platform '$PLATFORM'. Use: android | ios"
    exit 1
    ;;
esac

if [ ! -d "$APP_ROOT/.git" ]; then
  echo "❌ macadam-app not found at: $APP_ROOT"
  echo "   Clone it or set MACADAM_APP_ROOT=/path/to/macadam-app"
  exit 1
fi

ORIG_GIT_REF=""
TARGET_GIT_REF=""
CLEANUP_DONE=0

cleanup() {
  if [ "$CLEANUP_DONE" -eq 1 ]; then
    return
  fi
  CLEANUP_DONE=1

  echo ""
  echo "→ Restoring macadam-app (no commits — discarding local app.json patch)..."
  cd "$APP_ROOT"

  git checkout -- app.json 2>/dev/null || true

  if [ "$STAY_ON_VERSION" != "1" ] && [ -n "$ORIG_GIT_REF" ] && [ "$SKIP_GIT" != "1" ]; then
    git checkout "$ORIG_GIT_REF" 2>/dev/null || true
    echo "   Back on: $(git branch --show-current 2>/dev/null || git rev-parse --short HEAD)"
  fi
}

trap cleanup EXIT INT TERM

resolve_git_ref() {
  local ver="$1"
  if git rev-parse "refs/tags/v${ver}" >/dev/null 2>&1; then
    echo "v${ver}"
    return 0
  fi
  if git rev-parse "refs/remotes/origin/release/${ver}" >/dev/null 2>&1; then
    echo "origin/release/${ver}"
    return 0
  fi
  if git rev-parse "refs/heads/release/${ver}" >/dev/null 2>&1; then
    echo "release/${ver}"
    return 0
  fi
  return 1
}

patch_app_json_version() {
  local ver="$1"
  local file="$APP_ROOT/app.json"
  if ! grep -q '"version"' "$file"; then
    echo "❌ Could not find \"version\" in $file"
    exit 1
  fi
  # macOS sed requires '' after -i; GNU sed does not.
  if sed --version >/dev/null 2>&1; then
    sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"${ver}\"/" "$file"
  else
    sed -i '' "s/\"version\": \"[^\"]*\"/\"version\": \"${ver}\"/" "$file"
  fi
  echo "   app.json version → ${ver} (local only, not committed)"
}

cd "$APP_ROOT"

echo "=== Build Macadam ${VERSION} (${PLATFORM}) for Maestro ==="
echo "   Repo: $APP_ROOT"
echo ""

if [ -n "$(git status --porcelain)" ]; then
  echo "❌ macadam-app has uncommitted changes."
  echo "   Commit or stash them first, then re-run."
  git status --short
  exit 1
fi

ORIG_GIT_REF="$(git rev-parse HEAD)"
echo "→ Saved current ref: $(git branch --show-current 2>/dev/null || echo detached) (${ORIG_GIT_REF:0:8})"

if [ "$SKIP_GIT" != "1" ]; then
  echo "→ Fetching tags and release branches..."
  git fetch --tags origin 2>/dev/null || git fetch --tags 2>/dev/null || true
  git fetch origin 'refs/heads/release/*:refs/remotes/origin/release/*' 2>/dev/null || true
  git fetch origin dev 2>/dev/null || true

  if [ -n "$GIT_REF" ]; then
    TARGET_GIT_REF="$GIT_REF"
    echo "→ Using GIT_REF: ${TARGET_GIT_REF}"
  elif TARGET_GIT_REF="$(resolve_git_ref "$VERSION")"; then
    echo "→ Resolved ref: ${TARGET_GIT_REF}"
  elif [ "$ALLOW_DEV_FALLBACK" = "1" ] && git rev-parse "refs/remotes/origin/dev" >/dev/null 2>&1; then
    TARGET_GIT_REF="origin/dev"
    echo ""
    echo "⚠️  No tag v${VERSION} or release/${VERSION} branch."
    echo "   Falling back to origin/dev (same as CI workflow_dispatch with VERSION=${VERSION})."
    echo "   The version number is a label; code = latest dev."
  else
    echo ""
    echo "❌ No git ref found for version ${VERSION}."
    echo "   Looked for: tag v${VERSION}, branch release/${VERSION}"
    echo ""
    echo "   Available v8.* tags:"
    git tag -l 'v8.*' --sort=-v:refname | head -8 | sed 's/^/     /'
    echo ""
    echo "   If the team built ${VERSION} from dev (CI manual build), re-run with:"
    echo "     ALLOW_DEV_FALLBACK=1 ./scripts/build-app-at-version.sh ${VERSION} ${PLATFORM}"
    echo "   Or pin a specific ref:"
    echo "     GIT_REF=origin/dev ./scripts/build-app-at-version.sh ${VERSION} ${PLATFORM}"
    echo ""
    echo "   Tip: SKIP_GIT=1 only changes the version label on your current branch."
    exit 1
  fi

  if ! git rev-parse "$TARGET_GIT_REF" >/dev/null 2>&1; then
    echo "❌ Git ref not found: ${TARGET_GIT_REF}"
    exit 1
  fi

  echo "→ Checking out code at: ${TARGET_GIT_REF}"
  git checkout "$TARGET_GIT_REF"
  echo "   Commit: $(git log -1 --oneline)"
else
  echo "→ SKIP_GIT=1 — keeping current code at $(git log -1 --oneline)"
fi

echo ""
echo "→ Patching app.json version (temporary, not committed)..."
patch_app_json_version "$VERSION"

echo ""
echo "→ Regenerating native project (expo prebuild)..."
PREBUILD_ARGS=(-p "$PLATFORM")
if [ "$PREBUILD_CLEAN" = "1" ]; then
  PREBUILD_ARGS=(--clean "${PREBUILD_ARGS[@]}")
fi
APP_VARIANT=beta npx expo prebuild "${PREBUILD_ARGS[@]}"

echo ""
echo "→ Building and installing (${PLATFORM}, beta)..."
if [ "$PLATFORM" = "android" ]; then
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
  export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
  ANDROID_DEVICE="${ANDROID_DEVICE:-}"
  if [ -z "$ANDROID_DEVICE" ]; then
    ANDROID_SERIAL="$("$ANDROID_HOME/platform-tools/adb" devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ { print $1; exit }')"
    if [ -n "$ANDROID_SERIAL" ]; then
      ANDROID_DEVICE="$("$ANDROID_HOME/platform-tools/adb" -s "$ANDROID_SERIAL" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
    fi
  fi
  if [ -z "$ANDROID_DEVICE" ]; then
    echo "❌ No Android emulator/device found. Start one first, or set ANDROID_DEVICE=Pixel_7"
    exit 1
  fi
  echo "   Device: $ANDROID_DEVICE"
  APP_VARIANT=beta npx expo run:android --device "$ANDROID_DEVICE"
else
  if [ -z "${DEVELOPER_DIR:-}" ]; then
    for _xc in \
      /Applications/Xcode-26.2.0.app \
      /Applications/Xcode-26.2.app; do
      if [ -d "$_xc/Contents/Developer" ]; then
        export DEVELOPER_DIR="$_xc/Contents/Developer"
        break
      fi
    done
  fi
  IOS_ARGS=(--device)
  if [ -n "$SIM_NAME" ]; then
    IOS_ARGS=("${IOS_ARGS[@]}" "$SIM_NAME")
  fi
  ENVFILE=.env.development APP_VARIANT=beta npx expo run:ios "${IOS_ARGS[@]}"
fi

echo ""
echo "✅ Installed Macadam beta ${VERSION} on ${PLATFORM}."
echo "   Code from: ${TARGET_GIT_REF:-current branch}"
echo "   Version label from: app.json (patched locally)"
echo ""
echo "   Run Maestro from: $REPO_ROOT"
echo "   Example: ./scripts/run-android-tests.sh"

if [ "$STAY_ON_VERSION" = "1" ]; then
  echo ""
  echo "   STAY_ON_VERSION=1 — leaving macadam-app on ${TARGET_GIT_REF:-current branch}."
  echo "   app.json patch will still be reverted on exit."
  # Prevent checkout-back in cleanup but still restore app.json
  ORIG_GIT_REF=""
fi
