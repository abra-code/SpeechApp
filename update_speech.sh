#!/bin/bash
# update_speech.sh
# Assemble the git-excluded runtime pieces of Speech.app from the sibling `speech` and `replay`
# repositories, then thin, deep-sign and verify the bundle.
#
# The SpeechApp repository keeps no copy of anything the speech repository owns. Everything the
# bundle needs from it is copied here, on every run:
#   Contents/Support/speech                   the command-line tool
#   Contents/Support/CTranscribe.framework    transcribe.cpp, a dynamic framework `speech` loads
#                                             from its own directory - it must sit beside it
#   Contents/Support/speech-catalog/          the built-in model catalog, read at startup
#   Contents/Support/speech-mlx               optional MLX helper (--without-mlx leaves it out)
#   Contents/Support/*.LICENSE, *NOTICES*     the notices that must travel with those binaries
#   Contents/Resources/Reference/             the published measurements and the model family
#                                             pages, shown before this Mac has measured anything
#   Contents/Support/speech-tools/            tools/fetch-fleurs.sh and tools/fetch-librispeech.sh,
#                                             which the Benchmark tab runs to download a corpus
# and from the replay repository:
#   Contents/Support/fingerprint              the file fingerprint tool, which tells a transcript
#                                             Speech saved and nobody touched from one it must not
#                                             replace
#
# Steps: (1) build speech with its own build.sh (--skip-build reuses what is already built),
# (2) deploy the pieces above, (3) refuse to sign a bundle whose binaries lack their notices,
# (4) thin every Mach-O to arm64, (5) deep-sign with codesign_applet.sh, (6) verify the deployed
# tools launch and speech finds its catalog. fingerprint is never built here: its universal
# release build comes from replay's own build.
#
# Building speech runs SwiftPM, which fails under a command sandbox with an error that blames
# Package.swift. Run this script with the sandbox off.
#
# No `set -e`: every fallible step is checked where it happens and says what to do about it.

GREEN=$(printf '\033[92m'); RED=$(printf '\033[91m'); YELLOW=$(printf '\033[93m'); RESET=$(printf '\033[0m')

SIGNING_IDENTITY="-"
DO_BUILD="yes"
DO_CODESIGN="yes"
WITH_MLX="yes"
SPEECH_REPO="${SPEECH_REPO:-}"
REPLAY_REPO="${REPLAY_REPO:-}"

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "$0")" >/dev/null 2>&1 && pwd)"

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build) DO_BUILD="no" ;;
        --without-mlx) WITH_MLX="no" ;;
        --speech-repo=*) SPEECH_REPO="${1#*=}" ;;
        --replay-repo=*) REPLAY_REPO="${1#*=}" ;;
        --identity=*) SIGNING_IDENTITY="${1#*=}" ;;
        --no-codesign) DO_CODESIGN="no" ;;
        --help)
            echo "Usage: $0 [--skip-build] [--without-mlx] [--speech-repo=PATH] [--replay-repo=PATH] [--identity=CERT] [--no-codesign]"
            echo "  --skip-build     deploy what ../speech/build already holds instead of building it"
            echo "  --without-mlx    leave speech-mlx out of the bundle (the mlx.* rows then report unavailable)"
            echo "  --speech-repo    the speech repository (default: \$SPEECH_REPO, then ../speech)"
            echo "  --replay-repo    the replay repository, for fingerprint (default: \$REPLAY_REPO, then ../replay)"
            echo "  --identity       codesign identity (default: ad-hoc)"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

fail() { printf '%s%s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
warn() { printf '%s  WARNING: %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }

APP_BUNDLE="$SCRIPT_DIR/Speech.app"
[ -d "$APP_BUNDLE/Contents" ] || fail "No Speech.app beside this script (looked in $SCRIPT_DIR)"
SUPPORT_DIR="$APP_BUNDLE/Contents/Support"
REFERENCE_DIR="$APP_BUNDLE/Contents/Resources/Reference"

# Locate the speech repository: --speech-repo, then $SPEECH_REPO, then the sibling checkout.
[ -n "$SPEECH_REPO" ] || SPEECH_REPO="$SCRIPT_DIR/../speech"
if [ ! -f "$SPEECH_REPO/build.sh" ] || [ ! -f "$SPEECH_REPO/Package.swift" ]; then
    fail "speech repository not found at $SPEECH_REPO (looked for build.sh and Package.swift). Clone it beside SpeechApp or pass --speech-repo=PATH."
fi
SPEECH_REPO="$(cd "$SPEECH_REPO" && pwd)"
BUILD_DIR="$SPEECH_REPO/build"

# Locate the replay repository the same way. Its fingerprint build is checked before anything is
# built or copied, so a missing tool stops the run while the bundle is still untouched.
[ -n "$REPLAY_REPO" ] || REPLAY_REPO="$SCRIPT_DIR/../replay"
[ -d "$REPLAY_REPO" ] || fail "replay repository not found at $REPLAY_REPO. Clone it beside SpeechApp or pass --replay-repo=PATH."
REPLAY_REPO="$(cd "$REPLAY_REPO" && pwd)"
FINGERPRINT_SRC="$REPLAY_REPO/build/Release/fingerprint"
FINGERPRINT_LICENSE_SRC="$REPLAY_REPO/LICENSE"
[ -x "$FINGERPRINT_SRC" ] || fail "No fingerprint at $FINGERPRINT_SRC - build it in the replay repository first."
[ -s "$FINGERPRINT_LICENSE_SRC" ] || fail "No $FINGERPRINT_LICENSE_SRC - fingerprint's notice has to ship with it."

echo
echo "==== Updating Speech.app ===="
echo "  speech repo : $SPEECH_REPO"
echo "  replay repo : $REPLAY_REPO"
echo "  deploy to   : $SUPPORT_DIR"
echo

# -- 1. Build ----------------------------------------------------------------------------------
if [ "$DO_BUILD" = "yes" ]; then
    echo "  Building speech (release, arm64)..."
    /bin/sh "$SPEECH_REPO/build.sh" arm64
    build_status=$?
    if [ "$build_status" -ne 0 ]; then
        fail "speech build.sh failed (exit $build_status). If the log blames Package.swift, the command sandbox is the cause - run this script with it off."
    fi
    echo "  ${GREEN}Build OK${RESET}"
fi

SPEECH_SRC="$BUILD_DIR/speech"
FRAMEWORK_SRC="$BUILD_DIR/CTranscribe.framework"
CATALOG_SRC="$BUILD_DIR/speech-catalog"
MLX_SRC="$BUILD_DIR/speech-mlx"
MLX_NOTICES_SRC="$BUILD_DIR/speech-mlx-THIRD-PARTY-NOTICES.txt"
[ -x "$SPEECH_SRC" ] || fail "No built speech at $SPEECH_SRC (build first, or drop --skip-build)"
[ -d "$FRAMEWORK_SRC" ] || fail "No CTranscribe.framework at $FRAMEWORK_SRC - speech does not launch without it; rebuild with the speech repo's build.sh"
[ -d "$CATALOG_SRC" ] || fail "No speech-catalog at $CATALOG_SRC - speech refuses to run without it; rebuild with the speech repo's build.sh"

# The notices. FluidAudio is linked statically into speech, so its Apache 2.0 notice comes from
# the package checkout SwiftPM made while building; transcribe.cpp's MIT notice and the notices
# of what it vendors (ggml, miniz) are kept in the speech repository beside its wrapper.
SPEECH_LICENSE_SRC="$SPEECH_REPO/LICENSE"
FLUIDAUDIO_LICENSE_SRC="$BUILD_DIR/checkouts/FluidAudio/LICENSE"
TRANSCRIBE_LICENSE_SRC="$SPEECH_REPO/Sources/TranscribeCpp/LICENSE"
TRANSCRIBE_NOTICES_SRC="$SPEECH_REPO/Sources/TranscribeCpp/THIRD-PARTY-LICENSES.md"
MEASUREMENTS_SRC="$SPEECH_REPO/docs/benchmarks/measurements.tsv"
# Live figures are published separately because they are a separate measurement; the Models
# window suggests a live model from them.
LIVE_MEASUREMENTS_SRC="$SPEECH_REPO/docs/benchmarks/live-measurements.tsv"
FAMILY_PAGES_SRC="$SPEECH_REPO/docs/models-user"

# -- 2. Deploy ---------------------------------------------------------------------------------
# Every copy lands beside its destination under a temporary name and is renamed into place, so
# an interrupted run leaves the previous version rather than half of the new one.

# $1 = source file, $2 = destination file
replace_file() {
    /bin/rm -f "$2.new"
    /bin/cp -f "$1" "$2.new"
    local _cp_status=$?
    if [ "$_cp_status" -ne 0 ]; then
        /bin/rm -f "$2.new"
        fail "Could not copy $1 to $2.new"
    fi
    /bin/mv -f "$2.new" "$2"
    local _mv_status=$?
    [ "$_mv_status" -eq 0 ] || fail "Could not move $2.new into place"
}

# $1 = source directory, $2 = destination directory. cp -R copies symlinks as symlinks, which a
# framework's Versions/Current layout depends on.
replace_dir() {
    /bin/rm -rf "$2.new" "$2.old"
    /bin/cp -R "$1" "$2.new"
    local _cp_status=$?
    if [ "$_cp_status" -ne 0 ]; then
        /bin/rm -rf "$2.new"
        fail "Could not copy $1 to $2.new"
    fi
    if [ -e "$2" ]; then
        /bin/mv "$2" "$2.old"
        local _aside_status=$?
        [ "$_aside_status" -eq 0 ] || fail "Could not move the previous $2 aside"
    fi
    /bin/mv "$2.new" "$2"
    local _mv_status=$?
    [ "$_mv_status" -eq 0 ] || fail "Could not move $2.new into place (the previous copy is at $2.old)"
    /bin/rm -rf "$2.old"
}

/bin/mkdir -p "$SUPPORT_DIR"
mkdir_status=$?
[ "$mkdir_status" -eq 0 ] || fail "Could not create $SUPPORT_DIR"

replace_file "$SPEECH_SRC" "$SUPPORT_DIR/speech"
/bin/chmod +x "$SUPPORT_DIR/speech"
replace_dir "$FRAMEWORK_SRC" "$SUPPORT_DIR/CTranscribe.framework"
replace_dir "$CATALOG_SRC" "$SUPPORT_DIR/speech-catalog"
echo "  ${GREEN}Deployed${RESET} speech + CTranscribe.framework + speech-catalog"

for notice in "$SPEECH_LICENSE_SRC" "$FLUIDAUDIO_LICENSE_SRC" "$TRANSCRIBE_LICENSE_SRC" "$TRANSCRIBE_NOTICES_SRC"; do
    [ -s "$notice" ] || fail "Missing $notice - its notice has to ship with the binaries. A missing FluidAudio checkout means the SwiftPM build directory was cleaned; rebuild without --skip-build."
done
replace_file "$SPEECH_LICENSE_SRC" "$SUPPORT_DIR/speech.LICENSE"
replace_file "$FLUIDAUDIO_LICENSE_SRC" "$SUPPORT_DIR/FluidAudio.LICENSE"
replace_file "$TRANSCRIBE_LICENSE_SRC" "$SUPPORT_DIR/transcribe.cpp.LICENSE"
replace_file "$TRANSCRIBE_NOTICES_SRC" "$SUPPORT_DIR/transcribe.cpp.THIRD-PARTY-LICENSES.md"

replace_file "$FINGERPRINT_SRC" "$SUPPORT_DIR/fingerprint"
/bin/chmod +x "$SUPPORT_DIR/fingerprint"
replace_file "$FINGERPRINT_LICENSE_SRC" "$SUPPORT_DIR/fingerprint.LICENSE"
echo "  ${GREEN}Deployed${RESET} fingerprint"

# The MLX helper is optional in the speech repository too (its own build script, its own
# toolchain), so a missing one is a warning. --without-mlx removes a previously deployed copy,
# so the flag means what it says rather than "leave whatever an earlier run put there".
if [ "$WITH_MLX" = "yes" ]; then
    if [ -x "$MLX_SRC" ]; then
        [ -s "$MLX_NOTICES_SRC" ] || fail "speech-mlx is built but $MLX_NOTICES_SRC is missing - rebuild it with the speech repo's build-speech-mlx.sh"
        replace_file "$MLX_SRC" "$SUPPORT_DIR/speech-mlx"
        /bin/chmod +x "$SUPPORT_DIR/speech-mlx"
        replace_file "$MLX_NOTICES_SRC" "$SUPPORT_DIR/speech-mlx-THIRD-PARTY-NOTICES.txt"
        echo "  ${GREEN}Deployed${RESET} speech-mlx"
    else
        warn "no speech-mlx in $BUILD_DIR (build it with the speech repo's build-speech-mlx.sh); the mlx.* rows will report unavailable"
    fi
else
    /bin/rm -f "$SUPPORT_DIR/speech-mlx" "$SUPPORT_DIR/speech-mlx-THIRD-PARTY-NOTICES.txt"
fi

# Reference data: assembled in a scratch copy, then swapped in whole.
[ -s "$MEASUREMENTS_SRC" ] || fail "No $MEASUREMENTS_SRC - the published battery is missing from the speech repo"
REFERENCE_STAGE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/update-speech-reference.XXXXXX")"
mktemp_status=$?
[ "$mktemp_status" -eq 0 ] || fail "mktemp failed"
trap '/bin/rm -rf "$REFERENCE_STAGE"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
/bin/mkdir -p "$REFERENCE_STAGE/Reference/models"
/bin/cp -f "$MEASUREMENTS_SRC" "$REFERENCE_STAGE/Reference/measurements.tsv"
copy_status=$?
[ "$copy_status" -eq 0 ] || fail "Could not stage measurements.tsv"
[ -s "$LIVE_MEASUREMENTS_SRC" ] || fail "No $LIVE_MEASUREMENTS_SRC - run tools/live-report.py in the speech repo"
/bin/cp -f "$LIVE_MEASUREMENTS_SRC" "$REFERENCE_STAGE/Reference/live-measurements.tsv"
copy_status=$?
[ "$copy_status" -eq 0 ] || fail "Could not stage live-measurements.tsv"
page_count=0
for page in "$FAMILY_PAGES_SRC"/*.md; do
    [ -f "$page" ] || continue
    /bin/cp -f "$page" "$REFERENCE_STAGE/Reference/models/"
    page_status=$?
    [ "$page_status" -eq 0 ] || fail "Could not stage $page"
    page_count=$((page_count + 1))
done
[ "$page_count" -gt 0 ] || fail "No model family pages in $FAMILY_PAGES_SRC"
replace_dir "$REFERENCE_STAGE/Reference" "$REFERENCE_DIR"
echo "  ${GREEN}Deployed${RESET} reference measurements + $page_count family pages"

# speech's corpus fetch tools. The app runs them with /bin/sh, so they are copied as plain files
# without the execute bit, and checked for syntax here rather than at the user's first Download.
/bin/mkdir -p "$REFERENCE_STAGE/speech-tools"
for tool in fetch-fleurs.sh fetch-librispeech.sh; do
    [ -s "$SPEECH_REPO/tools/$tool" ] || fail "No $SPEECH_REPO/tools/$tool - the Benchmark tab downloads corpora with it"
    /bin/sh -n "$SPEECH_REPO/tools/$tool"
    syntax_status=$?
    [ "$syntax_status" -eq 0 ] || fail "$SPEECH_REPO/tools/$tool does not parse with /bin/sh -n"
    /bin/cp -f "$SPEECH_REPO/tools/$tool" "$REFERENCE_STAGE/speech-tools/$tool"
    copy_status=$?
    [ "$copy_status" -eq 0 ] || fail "Could not stage $tool"
    /bin/chmod 644 "$REFERENCE_STAGE/speech-tools/$tool"
done
replace_dir "$REFERENCE_STAGE/speech-tools" "$SUPPORT_DIR/speech-tools"
echo "  ${GREEN}Deployed${RESET} corpus fetch tools"

# Finder droppings are unsealed content as far as codesign is concerned.
/usr/bin/find "$SUPPORT_DIR" "$REFERENCE_DIR" -name ".DS_Store" -delete

# -- 3. License gate ---------------------------------------------------------------------------
# Checked against what is in the bundle, on every run, right before signing: a --skip-build run
# inherits whatever an earlier run left there. $1 = payload, $2 = notice that must accompany it.
require_license() {
    [ -e "$1" ] || return 0
    [ -s "$2" ] && return 0
    fail "$(/usr/bin/basename "$1") is in the bundle but $(/usr/bin/basename "$2") is missing or empty - its notice must ship with it."
}
require_license "$SUPPORT_DIR/speech" "$SUPPORT_DIR/speech.LICENSE"
require_license "$SUPPORT_DIR/speech" "$SUPPORT_DIR/FluidAudio.LICENSE"
require_license "$SUPPORT_DIR/CTranscribe.framework" "$SUPPORT_DIR/transcribe.cpp.LICENSE"
require_license "$SUPPORT_DIR/CTranscribe.framework" "$SUPPORT_DIR/transcribe.cpp.THIRD-PARTY-LICENSES.md"
require_license "$SUPPORT_DIR/speech-mlx" "$SUPPORT_DIR/speech-mlx-THIRD-PARTY-NOTICES.txt"
require_license "$SUPPORT_DIR/fingerprint" "$SUPPORT_DIR/fingerprint.LICENSE"

# -- 4. Thin to arm64 --------------------------------------------------------------------------
# speech is arm64 only (FluidAudio does not build for x86_64), so the OMC executable,
# Abracode.framework and fingerprint, which arrive universal, are thinned to match. Already-thin
# files are left alone, so a re-run is a no-op.
THIN_LIST="$REFERENCE_STAGE/thin.list"
/usr/bin/find "$APP_BUNDLE" -type f > "$THIN_LIST"
find_status=$?
[ "$find_status" -eq 0 ] || fail "Could not list the bundle for thinning"
while IFS= read -r macho; do
    archs="$(/usr/bin/lipo -archs "$macho" 2>/dev/null)"
    lipo_status=$?
    [ "$lipo_status" -eq 0 ] || continue
    case "$archs" in *" "*) ;; *) continue ;; esac
    case " $archs " in
        *" arm64 "*) ;;
        *) warn "cannot thin (no arm64 slice): ${macho#$APP_BUNDLE/}"; continue ;;
    esac
    thin_tmp="$REFERENCE_STAGE/thin.$(/usr/bin/basename "$macho")"
    /usr/bin/lipo -thin arm64 "$macho" -output "$thin_tmp" 2>/dev/null
    thin_status=$?
    if [ "$thin_status" -ne 0 ]; then
        warn "lipo could not thin ${macho#$APP_BUNDLE/}"
        continue
    fi
    # cat into the existing file keeps its inode and permissions.
    /bin/cat "$thin_tmp" > "$macho"
    write_status=$?
    [ "$write_status" -eq 0 ] || fail "Could not write the thinned ${macho#$APP_BUNDLE/}"
    /bin/rm -f "$thin_tmp"
    echo "  thinned ${macho#$APP_BUNDLE/} -> arm64"
done < "$THIN_LIST"

# -- 5. Codesign -------------------------------------------------------------------------------
if [ "$DO_CODESIGN" = "yes" ]; then
    [ -x "$SCRIPT_DIR/codesign_applet.sh" ] || fail "codesign_applet.sh not found beside this script"
    "$SCRIPT_DIR/codesign_applet.sh" --brief "$APP_BUNDLE" "$SIGNING_IDENTITY"
    sign_status=$?
    [ "$sign_status" -eq 0 ] || fail "codesign_applet.sh failed (exit $sign_status)"
fi

# -- 6. Verify ---------------------------------------------------------------------------------
version="$("$SUPPORT_DIR/speech" --version 2>&1)"
version_status=$?
case "$version" in
    "speech "*) ;;
    *) fail "The deployed speech did not report its version (exit $version_status): $version" ;;
esac
# The catalog query proves the binary found speech-catalog beside it, which a bare --version
# does not touch.
catalog_json="$("$SUPPORT_DIR/speech" --json catalog 2>/dev/null)"
catalog_status=$?
[ "$catalog_status" -eq 0 ] || fail "The deployed speech could not read its catalog (exit $catalog_status)"
first_row="$(printf '%s' "$catalog_json" | /usr/bin/plutil -extract rows.0.id raw -o - - 2>/dev/null)"
[ -n "$first_row" ] || fail "The deployed speech reported a catalog with no rows"
fingerprint_version="$("$SUPPORT_DIR/fingerprint" -V 2>&1)"
fingerprint_status=$?
case "$fingerprint_version" in
    "fingerprint "*) ;;
    *) fail "The deployed fingerprint did not report its version (exit $fingerprint_status): $fingerprint_version" ;;
esac
echo "  ${GREEN}Verify OK${RESET}: $version, $fingerprint_version, catalog readable"

echo
echo "  ${GREEN}Done.${RESET} Speech.app is ready."
echo
