# lib.speech.sh - shared library for the Speech applet. Sourced by every handler, by the window
# poller (speech.poll.sh) and by the stdin holder (speech.live.stdin.sh). POSIX /bin/sh
# (macOS bash 3.2): validate with `sh -n`, never `bash -n`.

[ -n "${__SPEECH_LIB:-}" ] && return 0
__SPEECH_LIB=1

# OMC runtime tools, resolved from the support directory OMC exports.
dialog="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_command="$OMC_OMC_SUPPORT_PATH/omc_next_command"
pasteboard="$OMC_OMC_SUPPORT_PATH/pasteboard"

# JSON is read with the system jq, which ships with macOS 15 - this applet's minimum, set by the
# speech binary it bundles. Programs longer than a filter live in Scripts/*.jq.
jq="/usr/bin/jq"

window_uuid="${OMC_ACTIONUI_WINDOW_UUID:-}"
RESOURCES_DIR="$OMC_APP_BUNDLE_PATH/Contents/Resources"
SCRIPTS_DIR="$RESOURCES_DIR/Scripts"

TAB="$(printf '\t')"
US="$(printf '\037')"
NL="
"
# U+F8FF, the Apple logo, as UTF-8 bytes: the marker of Apple's own engines in a model label.
APPLE_LOGO="$(printf '\357\243\277')"

# --- Substitutable outside world ---------------------------------------------------------------
# Everything below names something a test must not reach for real: the speech binary, which
# loads gigabytes of weights and opens the microphone; the background poller, which would keep
# writing into the window while a test reads it back; and the user's real model store, settings,
# session state and recordings folder. omctest intercepts the OMC support tools but cannot
# redirect an absolute or bundle-relative path, so a variable is the only seam. Nothing sets these
# in normal use.
#
# Two environment namespaces share the SPEECH_ prefix and must not be treated as one set. The
# ones read here (SPEECH_BIN, SPEECH_FINGERPRINT_BIN, SPEECH_POLL_SCRIPT,
# SPEECH_MODELS_POLL_SCRIPT, SPEECH_LIVE_STDIN_SCRIPT, SPEECH_APP_SUPPORT, SPEECH_RECORDINGS_DIR)
# are this applet's test hooks. SPEECH_MODELS_DIR and SPEECH_CATALOG_DIR, exported below, are the
# speech binary's own production configuration.
SPEECH_BIN="${SPEECH_BIN:-$OMC_APP_BUNDLE_PATH/Contents/Support/speech}"
FINGERPRINT_BIN="${SPEECH_FINGERPRINT_BIN:-$OMC_APP_BUNDLE_PATH/Contents/Support/fingerprint}"
POLL_SCRIPT="${SPEECH_POLL_SCRIPT:-$SCRIPTS_DIR/speech.poll.sh}"
MODELS_POLL_SCRIPT="${SPEECH_MODELS_POLL_SCRIPT:-$SCRIPTS_DIR/speech.models.poll.sh}"
LIVE_STDIN_SCRIPT="${SPEECH_LIVE_STDIN_SCRIPT:-$SCRIPTS_DIR/speech.live.stdin.sh}"
APP_SUPPORT="${SPEECH_APP_SUPPORT:-$HOME/Library/Application Support/Speech}"
RECORDINGS_DIR="${SPEECH_RECORDINGS_DIR:-$HOME/Documents/Speech Recordings}"
SESSIONS_DIR="$APP_SUPPORT/Sessions"
SETTINGS_DIR="$APP_SUPPORT/Settings"
# A download runs speech under a worker of its own, which a test runs for real with the fake speech.
DOWNLOAD_WORKER_SCRIPT="$SCRIPTS_DIR/speech.download.worker.sh"
DOWNLOADS_DIR="$APP_SUPPORT/Downloads"
# A new value here means a model was downloaded or deleted; every window reads the catalog again.
MODELS_STAMP="$APP_SUPPORT/models.changed"

# The speech binary's model store and user catalog, exported so every speech process this applet
# starts lands in the applet's store without each call site passing --models-dir. The CLI's own
# defaults are the same two paths today, but only by construction: computing them in one place
# is what keeps a test that redirects SPEECH_APP_SUPPORT from reading the user's real models.
SPEECH_MODELS_DIR="$APP_SUPPORT/Models"
SPEECH_CATALOG_DIR="$APP_SUPPORT/Catalog"
export SPEECH_MODELS_DIR SPEECH_CATALOG_DIR

# ActionUI control ids (must match speech.window.json).
TAB_VIEW=5

# The Live tab.
LIVE_MODEL_PICKER=25
LIVE_LANGUAGE_PICKER=26
LIVE_STOP_BTN=41
LIVE_BTN=42
LIVE_EXPORT_MENU=50
LIVE_COPY_BTN=55
LIVE_TRANSCRIPT=200
LIVE_STATUS=300

# The Recordings tab.
REC_MODEL_PICKER=125
REC_LANGUAGE_PICKER=126
REC_TRANSCRIBE_BTN=140
REC_STOP_BTN=141
REC_RECORD_BTN=142
REC_EXPORT_MENU=150
REC_COPY_BTN=155
REC_TABLE=160
REC_ADD_BTN=161
REC_REMOVE_BTN=162
REC_LEVEL=170
REC_TRANSCRIPT=210
REC_STATUS=310

# The Models window (speech.models.json) and its information sheet (speech.model.info.json).
MODELS_STATUS=910
MODELS_DONE_BTN=920
MODELS_BUILTIN_BOX=1100
MODELS_BUILTIN_LIST=1102
MODELS_INSTALLED_BOX=1200
MODELS_INSTALLED_LIST=1202
MODELS_AVAILABLE_BOX=1300
MODELS_AVAILABLE_LIST=1302
MODEL_INFO_TEXT=4010

# A model's card, inserted at run time: its id is MODEL_CARD_BASE + row * 10, and its parts sit at
# these offsets from it (speech.models.jq builds the card).
MODEL_CARD_BASE=2000
CARD_TITLE=1
CARD_DETAIL=2
CARD_STATE=3
CARD_DOWNLOAD=4
CARD_DELETE=5
CARD_INFO=6

# The tabs, by their 0-based position in the TabView.
TAB_INDEX_RECORDINGS=1

# The last option of both Model pickers, which opens the Models window.
DOWNLOAD_MODELS_OPTION="Download Models..."

# The one global handoff key: recordings opened from Finder, the Dock, File > Open or the Services
# menu are stashed here, one path per line, and consumed by the window that opens for them.
PB_OPEN_PATH="SPEECH_OPEN_PATH"

# The extended attribute Speech writes on every transcript it saves beside a recording:
#   speech-transcript-v1 <recording fingerprint> <transcript fingerprint>
# It is what lets a later run tell its own untouched transcript, which it may replace, from a file
# the user wrote or edited, which it must not.
TRANSCRIPT_XATTR="com.abracode.speech.transcript"

# --- panes ---------------------------------------------------------------------------------------
# The Live and Recordings tabs each have a model picker, a language picker, a transcript and a
# status line of their own, and keep their state in a directory of their own inside the window's
# spool. use_pane points the generic functions below at one of them: they write to MODEL_PICKER,
# STATUS_TEXT and the rest, and read the saved model and language under the pane's own keys.

use_pane() {   # $1 = live | recordings
    PANE="$1"
    case "$1" in
        live)
            MODEL_PICKER=$LIVE_MODEL_PICKER
            LANGUAGE_PICKER=$LIVE_LANGUAGE_PICKER
            STOP_BTN=$LIVE_STOP_BTN
            EXPORT_MENU=$LIVE_EXPORT_MENU
            COPY_BTN=$LIVE_COPY_BTN
            TRANSCRIPT_EDITOR=$LIVE_TRANSCRIPT
            STATUS_TEXT=$LIVE_STATUS
            ;;
        *)
            PANE="recordings"
            MODEL_PICKER=$REC_MODEL_PICKER
            LANGUAGE_PICKER=$REC_LANGUAGE_PICKER
            STOP_BTN=$REC_STOP_BTN
            EXPORT_MENU=$REC_EXPORT_MENU
            COPY_BTN=$REC_COPY_BTN
            TRANSCRIPT_EDITOR=$REC_TRANSCRIPT
            STATUS_TEXT=$REC_STATUS
            ;;
    esac
}

spool_dir_for() { printf '%s' "$SESSIONS_DIR/$1"; }
pane_dir_for() { printf '%s' "$SESSIONS_DIR/$1/$2"; }   # $1 = window uuid, $2 = pane

# --- small helpers -----------------------------------------------------------------------------

pb_set() { "$pasteboard" "$1" set "$2"; }
pb_get() { "$pasteboard" "$1" get 2>/dev/null; }

# Open a new window for recordings: stash the paths for speech.window.init, then chain to the
# window.
route_files() {   # $1 = file paths, one per line
    pb_set "$PB_OPEN_PATH" "$1"
    "$next_command" "$OMC_CURRENT_COMMAND_GUID" "speech.new"
}

set_status()    { "$dialog" "$window_uuid" "$STATUS_TEXT" "$1"; }
enable_ctrl()   { "$dialog" "$window_uuid" "$1" omc_enable; }
disable_ctrl()  { "$dialog" "$window_uuid" "$1" omc_disable; }
present_alert() { "$dialog" "$window_uuid" omc_window omc_present_alert "$1" "$2" "OK::"; }

set_enabled() {   # $1 = view id, $2 = 1 to enable, anything else to disable
    if [ "$2" = 1 ]; then
        enable_ctrl "$1"
    else
        disable_ctrl "$1"
    fi
}

show_transcript_file() {   # $1 = file; empty or absent clears the transcript
    if [ -n "$1" ] && [ -f "$1" ]; then
        /bin/cat "$1" | "$dialog" "$window_uuid" "$TRANSCRIPT_EDITOR" omc_set_value_from_stdin plain
    else
        printf '' | "$dialog" "$window_uuid" "$TRANSCRIPT_EDITOR" omc_set_value_from_stdin plain
    fi
}

# Write a small state file atomically, so a reader never sees half of it.
write_state() {   # $1 = path, $2 = value
    printf '%s' "$2" > "$1.tmp.$$"
    local _write_status=$?
    if [ "$_write_status" -ne 0 ]; then
        /bin/rm -f "$1.tmp.$$"
        return 1
    fi
    /bin/mv -f "$1.tmp.$$" "$1"
}

read_state() { /bin/cat "$1" 2>/dev/null; }   # $1 = path; empty when absent

# Returns 0 when the pid is a live process.
pid_alive() {   # $1 = pid
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    /bin/kill -0 "$1" 2>/dev/null
}

# Returns 0 when the pid is a speech process this bundle started, judged by its argv. A recorded
# pid can be recycled by the time anyone acts on it, so nothing is signaled without this check.
speech_pid_is_ours() {   # $1 = pid
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    local _args="$(/bin/ps -p "$1" -o args= 2>/dev/null)"
    case "$_args" in
        "$SPEECH_BIN"|"$SPEECH_BIN "*) return 0 ;;
    esac
    return 1
}

signal_speech_pid() {   # $1 = pid, $2 = signal name (TERM, KILL)
    speech_pid_is_ours "$1"
    local _ours=$?
    [ "$_ours" -eq 0 ] || return 1
    /bin/kill -"$2" "$1" 2>/dev/null
}

# Settings: one small file per key under Settings/. A file the applet owns is isolated by the
# test harness's $HOME redirection, which a `defaults` domain is not.
setting_get() { read_state "$SETTINGS_DIR/$1"; }   # $1 = key
setting_set() {   # $1 = key, $2 = value
    /bin/mkdir -p "$SETTINGS_DIR" 2>/dev/null
    write_state "$SETTINGS_DIR/$1" "$2"
}

# A JSON string literal body: backslashes and quotes escaped, control characters dropped.
json_escape() {   # $1 = text
    printf '%s' "$1" | /usr/bin/tr -d '\000-\037' | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g'
}

# The 1-based line of a TSV file whose first column equals a value; empty when absent.
tsv_line_of() {   # $1 = file, $2 = first-column value
    /usr/bin/awk -F'\t' -v key="$2" '$1 == key { print NR; exit }' "$1" 2>/dev/null
}

# One column of the line of a TSV file whose first column equals a value.
tsv_field() {   # $1 = file, $2 = first-column value, $3 = column number
    /usr/bin/awk -F'\t' -v key="$2" -v col="$3" '$1 == key { print $col; exit }' "$1" 2>/dev/null
}

# Returns 0 when a model in a pane's models.tsv can transcribe live (its modes include live).
model_is_live() {   # $1 = pane dir, $2 = model id
    local _modes="$(tsv_field "$1/models.tsv" "$2" 4)"
    case ",$_modes," in *,live,*) return 0 ;; esac
    return 1
}

# The fingerprint of one file's contents, from the bundled `fingerprint` tool. --xattr=off keeps
# the tool from caching its hash in an attribute on the user's recording. Prints nothing and
# returns non-zero when the tool fails.
fingerprint_of() {   # $1 = file
    local _out
    _out="$("$FINGERPRINT_BIN" --xattr=off "$1" 2>/dev/null)"
    local _fp_status=$?
    [ "$_fp_status" -eq 0 ] || return 1
    local _fp="$(printf '%s\n' "$_out" | /usr/bin/awk '$1 == "Fingerprint:" { print $2; exit }')"
    [ -n "$_fp" ] || return 1
    printf '%s' "$_fp"
}

# --- quiet windows -------------------------------------------------------------------------------
# Programmatic option and selection updates can fire a control's actionID with a transitional
# value. Every programmatic update opens a two-second window in which the change handlers do
# nothing, so an echo can neither switch the model nor overwrite a saved preference. The pickers
# and the recordings table each have a window of their own: replacing the table's rows must not
# silence a model the user picks right after adding a recording.

quiet_begin() {   # $1 = pane dir, $2 = picker (default) | table
    local _now="$(/bin/date +%s)"
    write_state "$1/${2:-picker}_quiet" "$((_now + 2))"
}

# Returns 0 while the quiet window is open.
quiet_active() {   # $1 = pane dir, $2 = picker (default) | table
    local _until="$(read_state "$1/${2:-picker}_quiet")"
    case "$_until" in ''|*[!0-9]*) return 1 ;; esac
    local _now="$(/bin/date +%s)"
    [ "$_now" -lt "$_until" ]
}

# --- the model list ----------------------------------------------------------------------------
# models.tsv holds the rows a window can transcribe with, in picker order:
#   id <TAB> label <TAB> languages <TAB> modes <TAB> capabilities <TAB> engine
# speech.catalog.jq decides which rows qualify. The spool's copy is every runnable row; each pane
# keeps its own: Recordings all of them, Live only those that can stream. Returns non-zero, with
# the reason in the spool's catalog.err, when the catalog cannot be read.

load_models() {   # $1 = spool
    read_catalog "$1"
    local _read_status=$?
    [ "$_read_status" -eq 0 ] || return 1
    pane_models "$1" live
    pane_models "$1" recordings
}

# The spool's models.tsv, from the catalog.
read_catalog() {   # $1 = spool
    local _spool="$1"
    "$SPEECH_BIN" --json catalog > "$_spool/catalog.json" 2> "$_spool/catalog.err"
    local _catalog_status=$?
    [ "$_catalog_status" -eq 0 ] || return 1
    "$jq" -r -f "$SCRIPTS_DIR/speech.catalog.jq" "$_spool/catalog.json" > "$_spool/models.tsv.tmp" 2>> "$_spool/catalog.err"
    local _jq_status=$?
    if [ "$_jq_status" -ne 0 ]; then
        /bin/rm -f "$_spool/models.tsv.tmp"
        return 1
    fi
    /bin/mv -f "$_spool/models.tsv.tmp" "$_spool/models.tsv"
}

# A pane's own models.tsv, from the spool's: Recordings all of it, Live the rows that can stream.
pane_models() {   # $1 = spool, $2 = live | recordings
    /bin/mkdir -p "$1/$2"
    if [ "$2" = live ]; then
        /usr/bin/awk -F'\t' '("," $4 ",") ~ /,live,/' "$1/models.tsv" > "$1/live/models.tsv"
    else
        /bin/cp -f "$1/models.tsv" "$1/recordings/models.tsv"
    fi
}

# --- models downloaded or deleted --------------------------------------------------------------
# Downloading or deleting a model in the Models window writes a new value into models.changed
# (bump_models_stamp). Each window's poller compares it with the value it last read the catalog
# at, and reads the catalog again when they differ. A busy tab keeps its list and picker as they
# are - its handlers map a picker position to a line of that list, and its run was started with a
# model from it - and takes the new list once the run, batch or recording has ended.

models_stamp() { read_state "$MODELS_STAMP"; }

bump_models_stamp() {
    /bin/mkdir -p "$APP_SUPPORT" 2>/dev/null
    local _now="$(/bin/date +%s)"
    write_state "$MODELS_STAMP" "$_now $$ $RANDOM"
}

reload_models_if_changed() {   # $1 = spool
    local _stamp="$(models_stamp)"
    local _seen="$(read_state "$1/models.seen")"
    if [ "$_stamp" != "$_seen" ]; then
        read_catalog "$1"
        local _read_status=$?
        [ "$_read_status" -eq 0 ] || return 1
        write_state "$1/models.seen" "$_stamp"
        : > "$1/live/models.pending"
        : > "$1/recordings/models.pending"
    fi
    local _pane
    for _pane in live recordings; do
        [ -f "$1/$_pane/models.pending" ] || continue
        pane_is_busy "$1/$_pane"
        local _busy=$?
        [ "$_busy" -eq 0 ] && continue
        /bin/rm -f "$1/$_pane/models.pending"
        use_pane "$_pane"
        pane_models "$1" "$_pane"
        populate_model_picker "$1/$_pane"
        /bin/rm -f "$1/$_pane/actions.sig"
    done
}

# The label a picker shows: the catalog's label with the engine's marker after it - [M] MLX,
# [G] ggml, [F] FluidAudio, the Apple logo for Apple's own engines. Picker options are text only,
# so the marker is a suffix. The status line uses the plain label.
model_display_label() {   # $1 = label, $2 = engine
    case "$2" in
        apple) printf '%s %s' "$1" "$APPLE_LOGO" ;;
        mlx)   printf '%s [M]' "$1" ;;
        ggml)  printf '%s [G]' "$1" ;;
        fluid) printf '%s [F]' "$1" ;;
        *)     printf '%s' "$1" ;;
    esac
}

# Fill the pane's Model picker from its models.tsv and settle the selection: the saved model if
# it is still offered, else apple.transcriber when present, else the first row. The selection is
# recorded in the pane's model.id, which every handler reads rather than trusting a picker index.
# The last option is always "Download Models...", which opens the Models window
# (handle_model_changed), so a tab with no model to offer still has a way to get one.
populate_model_picker() {   # $1 = pane dir
    local _pane="$1"
    local _options="["
    local _first=1
    local _id _label _languages _modes _caps _engine
    while IFS="$TAB" read -r _id _label _languages _modes _caps _engine; do
        [ -n "$_id" ] || continue
        if [ "$_first" = 1 ]; then _first=0; else _options="$_options,"; fi
        _options="$_options\"$(json_escape "$(model_display_label "$_label" "$_engine")")\""
    done < "$_pane/models.tsv"

    if [ "$_first" = 1 ]; then
        /bin/rm -f "$_pane/model.id" "$_pane/languages.tsv" "$_pane/language.tag"
        quiet_begin "$_pane"
        if [ "$PANE" = live ]; then
            "$dialog" "$window_uuid" "$MODEL_PICKER" omc_set_property "options" "[\"No live models available\",\"$DOWNLOAD_MODELS_OPTION\"]"
        else
            "$dialog" "$window_uuid" "$MODEL_PICKER" omc_set_property "options" "[\"No models available\",\"$DOWNLOAD_MODELS_OPTION\"]"
        fi
        "$dialog" "$window_uuid" "$MODEL_PICKER" 1
        "$dialog" "$window_uuid" "$LANGUAGE_PICKER" omc_set_property "options" '["-"]'
        return 0
    fi
    _options="$_options,\"$DOWNLOAD_MODELS_OPTION\"]"

    local _selected=""
    local _saved="$(setting_get "$PANE.model")"
    local _line
    if [ -n "$_saved" ]; then
        _line="$(tsv_line_of "$_pane/models.tsv" "$_saved")"
        [ -n "$_line" ] && _selected="$_saved"
    fi
    if [ -z "$_selected" ]; then
        _line="$(tsv_line_of "$_pane/models.tsv" apple.transcriber)"
        [ -n "$_line" ] && _selected="apple.transcriber"
    fi
    if [ -z "$_selected" ]; then
        _selected="$(/usr/bin/head -1 "$_pane/models.tsv" | /usr/bin/cut -f1)"
    fi
    _line="$(tsv_line_of "$_pane/models.tsv" "$_selected")"
    write_state "$_pane/model.id" "$_selected"

    quiet_begin "$_pane"
    "$dialog" "$window_uuid" "$MODEL_PICKER" omc_set_property "options" "$_options"
    "$dialog" "$window_uuid" "$MODEL_PICKER" "$_line"
    populate_language_picker "$_pane"
}

# The display name of a language tag: the English name of its primary subtag from
# Resources/languages.tsv (code <TAB> name), with the full tag appended when it carries a region,
# since a model that wants "pl-PL" rather than "pl" is worth showing as such. The bare tag when
# the table does not know the language.
language_display_name() {   # $1 = tag
    local _primary="$(printf '%s' "${1%%[-_]*}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    local _name="$(/usr/bin/awk -F'\t' -v code="$_primary" '$1 == code { print $2; exit }' "$RESOURCES_DIR/languages.tsv" 2>/dev/null)"
    if [ -z "$_name" ]; then
        printf '%s' "$1"
    elif [ "$_primary" = "$1" ]; then
        printf '%s' "$_name"
    else
        printf '%s (%s)' "$_name" "$1"
    fi
}

# Fill the pane's Language picker for its selected model. languages.tsv in the pane holds the
# options in picker order: tag <TAB> display name. The tags are the model's own spelling, which is
# what speech has to be given back.
#
# "Automatic" is offered only to a model that identifies languages itself (lang_id). The others
# need a language: Apple's engines refuse to run without one, and Canary given none silently
# translates into English rather than failing.
populate_language_picker() {   # $1 = pane dir
    local _pane="$1"
    local _model="$(read_state "$_pane/model.id")"
    local _languages="$(tsv_field "$_pane/models.tsv" "$_model" 3)"
    local _caps="$(tsv_field "$_pane/models.tsv" "$_model" 5)"
    local _engine="$(tsv_field "$_pane/models.tsv" "$_model" 6)"

    : > "$_pane/languages.unsorted"
    local _tag
    if [ "$_languages" = "*" ]; then
        # The engine reports no list of its own: offer every language the name table knows.
        /usr/bin/awk -F'\t' '!/^#/ && NF >= 2 { printf "%s\t%s\n", $1, $2 }' "$RESOURCES_DIR/languages.tsv" > "$_pane/languages.unsorted" 2>/dev/null
    else
        for _tag in $(printf '%s' "$_languages" | /usr/bin/tr ',' ' '); do
            # Apple ships Spanish for Spain and for the Americas, and a bare "es" reaches Apple as
            # Spain's. Most Spanish speakers live in Latin America, so it is offered first and by
            # name, as es-MX, Apple's Latin American locale; Spain stays one choice away.
            if [ "$_engine" = apple ] && [ "$_tag" = es ]; then
                printf 'es-MX\tSpanish (Latin America)\nes-ES\tSpanish (Spain)\n' >> "$_pane/languages.unsorted"
                continue
            fi
            printf '%s\t%s\n' "$_tag" "$(language_display_name "$_tag")" >> "$_pane/languages.unsorted"
        done
    fi

    : > "$_pane/languages.tsv.tmp"
    case ",$_caps," in
        *,lang_id,*) printf 'auto\tAutomatic\n' >> "$_pane/languages.tsv.tmp" ;;
    esac
    LC_ALL=C /usr/bin/sort -t "$TAB" -k2,2f "$_pane/languages.unsorted" >> "$_pane/languages.tsv.tmp"
    /bin/mv -f "$_pane/languages.tsv.tmp" "$_pane/languages.tsv"
    /bin/rm -f "$_pane/languages.unsorted"

    local _options="["
    local _first=1
    local _name
    while IFS="$TAB" read -r _tag _name; do
        [ -n "$_tag" ] || continue
        if [ "$_first" = 1 ]; then _first=0; else _options="$_options,"; fi
        _options="$_options\"$(json_escape "$_name")\""
    done < "$_pane/languages.tsv"
    _options="$_options]"

    # The selection: the saved language when this model offers it, else Automatic when offered,
    # else the language of the user's locale, else English, else the first entry. Matching falls
    # back to the primary subtag either way: a saved "pl" still finds a model's "pl-PL", and a saved
    # "es-MX" (what Apple's Spanish saves) still finds a model's bare "es", or another region of the
    # same language. Among Spanish variants, a Latin American one (es-419, es-MX, es-US) wins over
    # the first one listed.
    local _selected=""
    local _want
    local _saved="$(setting_get "$PANE.language")"
    local _locale_language="$(printf '%s' "${LANG%%[_.]*}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    for _want in "$_saved" auto "$_locale_language" en; do
        [ -n "$_want" ] || continue
        _selected="$(/usr/bin/awk -F'\t' -v want="$_want" '
            BEGIN { want = tolower(want); want_primary = want; sub(/[-_].*/, "", want_primary) }
            { tag = tolower($1); primary = tag; sub(/[-_].*/, "", primary) }
            tag == want { print $1; found = 1; exit }
            tag == want_primary && bare == "" { bare = $1 }
            primary == want_primary && first == "" { first = $1 }
            primary == want_primary && primary == "es" && latin == "" && tag ~ /^es[-_](419|mx|us)$/ { latin = $1 }
            END { if (!found) { if (bare != "") print bare; else if (latin != "") print latin; else if (first != "") print first } }
        ' "$_pane/languages.tsv")"
        [ -n "$_selected" ] && break
    done
    [ -n "$_selected" ] || _selected="$(/usr/bin/head -1 "$_pane/languages.tsv" | /usr/bin/cut -f1)"
    write_state "$_pane/language.tag" "$_selected"
    local _line="$(tsv_line_of "$_pane/languages.tsv" "$_selected")"

    quiet_begin "$_pane"
    "$dialog" "$window_uuid" "$LANGUAGE_PICKER" omc_set_property "options" "$_options"
    [ -n "$_line" ] && "$dialog" "$window_uuid" "$LANGUAGE_PICKER" "$_line"
    return 0
}

# The Model picker changed: the body of both panes' change handlers. The picker delivers a 1-based
# index, resolved against the pane's models.tsv, which is in picker order. A change inside the
# quiet window is the echo of a programmatic update and is ignored, as is an index that resolves
# to nothing, and a change while the pane is busy.
handle_model_changed() {   # $1 = pane dir, $2 = picker value
    quiet_active "$1"
    local _quiet=$?
    [ "$_quiet" -eq 0 ] && return 0
    case "$2" in ''|*[!0-9]*) return 0 ;; esac
    # "Download Models..." follows the rows, or the one placeholder option when there are none.
    local _rows="$(/usr/bin/awk 'NF { n++ } END { print n + 0 }' "$1/models.tsv" 2>/dev/null)"
    local _download_option=$((${_rows:-0} + 1))
    [ "${_rows:-0}" -eq 0 ] && _download_option=2
    if [ "$2" -eq "$_download_option" ]; then
        route_to_models_window "$1"
        return 0
    fi
    local _model="$(/usr/bin/sed -n "${2}p" "$1/models.tsv" 2>/dev/null | /usr/bin/cut -f1)"
    [ -n "$_model" ] || return 0
    [ "$_model" = "$(read_state "$1/model.id")" ] && return 0
    pane_is_busy "$1"
    local _busy=$?
    [ "$_busy" -eq 0 ] && return 0

    write_state "$1/model.id" "$_model"
    setting_set "$PANE.model" "$_model"
    /bin/rm -f "$1/status.note"
    populate_language_picker "$1"
    /bin/rm -f "$1/actions.sig"
}

# "Download Models..." was picked: open the Models window, and put the picker back on the tab's
# model, which the pick did not change. A model that finishes downloading reaches the picker
# through reload_models_if_changed.
route_to_models_window() {   # $1 = pane dir
    quiet_begin "$1"
    local _model="$(read_state "$1/model.id")"
    local _line=""
    [ -n "$_model" ] && _line="$(tsv_line_of "$1/models.tsv" "$_model")"
    "$dialog" "$window_uuid" "$MODEL_PICKER" "${_line:-1}"
    "$next_command" "$OMC_CURRENT_COMMAND_GUID" "speech.models"
}

# A Mac with no model this app can run gets one offer per app run to open the Models window. The
# marker is a directory under Sessions, made atomically so two windows opening together offer once,
# and removed with Sessions when the app quits.
offer_models_window() {   # $1 = spool
    [ -s "$1/recordings/models.tsv" ] && return 0
    /bin/mkdir -p "$SESSIONS_DIR" 2>/dev/null
    /bin/mkdir "$SESSIONS_DIR/models-offered" 2>/dev/null
    local _first=$?
    [ "$_first" -eq 0 ] || return 0
    "$dialog" "$window_uuid" omc_window omc_present_alert "No speech models yet" \
        "Speech needs a model to transcribe with. Download one in the Models window; every model runs entirely on this Mac." \
        "Not Now:cancel:" "Open Models::speech.models"
}

# The Language picker changed. The saved preference is a language tag, never an index, because
# the list differs from one model to the next.
handle_language_changed() {   # $1 = pane dir, $2 = picker value
    quiet_active "$1"
    local _quiet=$?
    [ "$_quiet" -eq 0 ] && return 0
    case "$2" in ''|*[!0-9]*) return 0 ;; esac
    local _tag="$(/usr/bin/sed -n "${2}p" "$1/languages.tsv" 2>/dev/null | /usr/bin/cut -f1)"
    [ -n "$_tag" ] || return 0
    [ "$_tag" = "$(read_state "$1/language.tag")" ] && return 0
    write_state "$1/language.tag" "$_tag"
    setting_set "$PANE.language" "$_tag"
}

# --- runs ----------------------------------------------------------------------------------------
# A run is one speech process and the files it leaves, in a directory the pane's `current` file
# names. A live session lives in <pane>/run-<epoch>-<pid>, and starting a run writes a fresh
# directory before repointing `current`, so a poller in the middle of reading the previous run's
# events can never write into the new one. A recording's transcription lives in
# <pane>/items/<key>, where the key is the recording path's md5, so each recording in the list
# keeps its last transcript for as long as the window is open. A new recording being made lives in
# <pane>/capture-<epoch>-<pid>, named by the pane's `capture` file.
#
# Files in a run directory:
#   kind           file (speech transcribe) | live (speech stream) | record (speech record)
#   model, language the model id and language tag the run was started with
#   source.path    the recording (file runs); position, "2 of 5" in a batch
#   output.path    the file a record run writes
#   state          running | stopping | done | failed | stopped
#   speech.pid     the speech process
#   events.jsonl   its stdout, one JSON event per line; stderr.log, its stderr
#   events.lines   how many complete event lines the poller has consumed
#   segments.tsv   id <TAB> kind <TAB> text, sorted by id - the transcript's source of truth
#   transcript.txt the rendered transcript; result.json, the finished transcript as JSON
#   stdin.fifo     a live or record run's stdin; stop.request, written by Stop for the stdin holder
#   recording.fp   the recording's fingerprint when its transcription started
#   saved.name, not_saved.txt  what became of the transcript beside the recording
#   level, audio_seconds  a record run's last input level and the length of what it wrote
#   summary.txt, error.txt, warnings.txt, reflected, settled

current_run_dir() {   # $1 = pane dir; prints the run directory, empty when there is none
    local _name="$(read_state "$1/current")"
    [ -n "$_name" ] || return 1
    [ -d "$1/$_name" ] || return 1
    printf '%s' "$1/$_name"
}

run_state() {   # $1 = pane dir
    local _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 0
    read_state "$_run/state"
}

# Returns 0 while the pane's current run is running or stopping.
run_is_active() {   # $1 = pane dir
    local _state="$(run_state "$1")"
    case "$_state" in running|stopping) return 0 ;; esac
    return 1
}

# Returns 0 while the pane is doing something: a run in progress, a batch still going, or a new
# recording being made.
pane_is_busy() {   # $1 = pane dir
    [ -n "$(read_state "$1/batch")" ] && return 0
    capture_is_active "$1"
    local _capturing=$?
    [ "$_capturing" -eq 0 ] && return 0
    run_is_active "$1"
}

# Returns 0 while the window's other pane is busy. One thing at a time per window: two models
# would compete for the same memory, the GPU and the Neural Engine, and two captures for the same
# microphone.
other_pane_is_busy() {   # $1 = pane dir
    local _spool="$(/usr/bin/dirname "$1")"
    if [ "$PANE" = live ]; then
        pane_is_busy "$_spool/recordings"
    else
        pane_is_busy "$_spool/live"
    fi
}

new_run_dir() {   # $1 = pane dir; prints the new run directory
    local _now="$(/bin/date +%s)"
    local _name="run-$_now-$$"
    /bin/mkdir -p "$1/$_name"
    local _mkdir_status=$?
    [ "$_mkdir_status" -eq 0 ] || return 1
    printf '%s' "$1/$_name"
}

# Make a live run directory current and remove every other one.
activate_run_dir() {   # $1 = pane dir, $2 = run directory
    local _name="$(/usr/bin/basename "$2")"
    write_state "$1/current" "$_name"
    local _old
    for _old in "$1"/run-*; do
        [ -d "$_old" ] || continue
        [ "$_old" = "$2" ] && continue
        /bin/rm -rf "$_old"
    done
}

# Start `speech transcribe` for a file, in the background, writing its events into the run
# directory. The transcript is also written as JSON when the run finishes, which is what Export
# converts with `speech export` rather than transcribing again. Prints the pid.
spawn_transcribe() {   # $1 = run dir, $2 = file, $3 = model id, $4 = language tag or auto
    if [ "$4" = auto ] || [ -z "$4" ]; then
        "$SPEECH_BIN" --json transcribe "$2" --model "$3" --format json --output "$1/result.json" \
            < /dev/null > "$1/events.jsonl" 2> "$1/stderr.log" &
    else
        "$SPEECH_BIN" --json transcribe "$2" --model "$3" --language "$4" --format json --output "$1/result.json" \
            < /dev/null > "$1/events.jsonl" 2> "$1/stderr.log" &
    fi
    printf '%s' "$!"
}

# Start the process that holds a microphone run's stdin (speech.live.stdin.sh) beside it.
#
# `speech stream` and `speech record` both stop tidily on "q" and Return, or at end of input.
# Their stdin is a FIFO in the run directory whose only writer is the holder, which sends "q" when
# Stop asks and closes the FIFO when the window or the app goes away - so the run ends even when
# nothing is left to say so. --parent-pid cannot serve: speech's parent is the handler that
# started it, which exits at once.
#
# The background shell opens the FIFO for reading before it becomes speech, and that open waits
# for the holder's write end, so neither side can run ahead of the other.
start_stdin_holder() {   # $1 = run dir, $2 = speech pid
    /bin/sh "$LIVE_STDIN_SCRIPT" "$1" "$2" "${OMC_APP_PROCESS_ID:-}" < /dev/null > /dev/null 2>&1 &
}

# Start `speech stream` on the default microphone, in the background, with its stdin holder.
# Prints the speech pid; prints nothing when the FIFO cannot be made.
spawn_stream() {   # $1 = run dir, $2 = model id, $3 = language tag or auto
    /usr/bin/mkfifo "$1/stdin.fifo"
    local _fifo_status=$?
    [ "$_fifo_status" -eq 0 ] || return 1
    if [ "$3" = auto ] || [ -z "$3" ]; then
        "$SPEECH_BIN" --json stream --model "$2" \
            < "$1/stdin.fifo" > "$1/events.jsonl" 2> "$1/stderr.log" &
    else
        "$SPEECH_BIN" --json stream --model "$2" --language "$3" \
            < "$1/stdin.fifo" > "$1/events.jsonl" 2> "$1/stderr.log" &
    fi
    local _pid=$!
    start_stdin_holder "$1" "$_pid"
    printf '%s' "$_pid"
}

# Start `speech record` into a new file, in the background, with its stdin holder. Prints the
# speech pid; prints nothing when the FIFO cannot be made.
spawn_record() {   # $1 = run dir, $2 = output file
    /usr/bin/mkfifo "$1/stdin.fifo"
    local _fifo_status=$?
    [ "$_fifo_status" -eq 0 ] || return 1
    "$SPEECH_BIN" --json record "$2" \
        < "$1/stdin.fifo" > "$1/events.jsonl" 2> "$1/stderr.log" &
    local _pid=$!
    start_stdin_holder "$1" "$_pid"
    printf '%s' "$_pid"
}

# Write a live session's transcript as result.json, in the shape `speech transcribe --format json`
# writes, so Export treats a live session like any other. Built from the session's own events by
# speech.live-result.jq.
build_live_result() {   # $1 = run dir
    local _language="$(read_state "$1/language")"
    [ "$_language" = auto ] && _language=""
    "$jq" -s --arg model "$(read_state "$1/model")" --arg language "$_language" \
        -f "$SCRIPTS_DIR/speech.live-result.jq" "$1/events.jsonl" > "$1/result.json.tmp" 2>/dev/null
    local _jq_status=$?
    if [ "$_jq_status" -ne 0 ]; then
        /bin/rm -f "$1/result.json.tmp"
        return 1
    fi
    /bin/mv -f "$1/result.json.tmp" "$1/result.json"
}

# --- reading a run's events --------------------------------------------------------------------

# A duration in seconds as "4.4 s" or "2 min 05 s".
format_seconds() {   # $1 = seconds
    /usr/bin/awk -v s="$1" 'BEGIN {
        if (s == "" || s < 0) s = 0
        if (s < 60) printf "%.1f s", s
        else printf "%d min %02d s", int(s / 60), int(s) % 60
    }'
}

# A duration in seconds as a clock, "0:07" or "12:40".
format_clock() {   # $1 = seconds
    /usr/bin/awk -v s="$1" 'BEGIN {
        if (s == "" || s < 0) s = 0
        printf "%d:%02d", int(s / 60), int(s) % 60
    }'
}

# Consume the event lines of a run the poller has not seen yet, as one record per event in the
# run's events.records, flattened by a jq program. Returns 0 when there was at least one line.
#
# Only complete lines are consumed. The line speech is in the middle of writing has no newline
# yet; `wc -l` counts newlines, so taking that many lines leaves it for the next tick, and it is
# read whole then.
consume_new_events() {   # $1 = run dir, $2 = jq program
    [ -f "$1/events.jsonl" ] || return 1
    local _consumed="$(read_state "$1/events.lines")"
    case "$_consumed" in ''|*[!0-9]*) _consumed=0 ;; esac

    /usr/bin/tail -n "+$((_consumed + 1))" "$1/events.jsonl" > "$1/events.new" 2>/dev/null
    local _complete="$(/usr/bin/wc -l < "$1/events.new" | /usr/bin/tr -d ' ')"
    case "$_complete" in ''|*[!0-9]*) _complete=0 ;; esac
    if [ "$_complete" -eq 0 ]; then
        /bin/rm -f "$1/events.new"
        return 1
    fi
    /usr/bin/head -n "$_complete" "$1/events.new" > "$1/events.batch"
    /bin/rm -f "$1/events.new"

    "$jq" -r -f "$2" "$1/events.batch" > "$1/events.records" 2> "$1/events.err"
    local _jq_status=$?
    if [ "$_jq_status" -ne 0 ]; then
        # One unreadable line fails the whole batch. Go line by line instead, so it costs only
        # itself, and keep the line for whoever has to find out why.
        : > "$1/events.records"
        local _raw
        while IFS= read -r _raw; do
            printf '%s\n' "$_raw" | "$jq" -r -f "$2" >> "$1/events.records" 2>/dev/null
            local _line_status=$?
            [ "$_line_status" -eq 0 ] || printf '%s\n' "$_raw" >> "$1/events.unreadable"
        done < "$1/events.batch"
    fi
    /bin/rm -f "$1/events.batch"
    write_state "$1/events.lines" "$((_consumed + _complete))"
    return 0
}

# Consume the current run's new events, and fold their segments into the segment table. Returns 0
# when the segment table changed. speech.events.jq turns each event into one record.
process_events() {   # $1 = pane dir
    local _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 1
    consume_new_events "$_run" "$SCRIPTS_DIR/speech.events.jq"
    local _consumed_status=$?
    [ "$_consumed_status" -eq 0 ] || return 1

    local _kind="$(read_state "$_run/kind")"
    local _name="$(/usr/bin/basename "$(read_state "$_run/source.path")")"
    local _position="$(read_state "$_run/position")"
    [ -n "$_position" ] && _name="$_name ($_position)"
    local _status=""
    : > "$_run/segments.new"
    local _type _id _text _percent _phase _message _segments _audio _wall _rtfx _file _event_model
    while IFS="$US" read -r _type _id _text _percent _phase _message _segments _audio _wall _rtfx _file _event_model; do
        case "$_type" in
            segment.partial) printf '%s\tpartial\t%s\n' "$_id" "$_text" >> "$_run/segments.new" ;;
            segment.final)   printf '%s\tfinal\t%s\n' "$_id" "$_text" >> "$_run/segments.new" ;;
            segment.refined) printf '%s\trefined\t%s\n' "$_id" "$_text" >> "$_run/segments.new" ;;
            progress)
                _status="Transcribing $_name... ${_percent:-0}%"
                ;;
            model.progress)
                if [ "${_event_model%%.*}" = apple ] && [ -n "$_file" ]; then
                    note_apple_language_files "$_run" "$_phase" "$_file" "$_percent"
                    _status="$(apple_language_files_status "$_run")"
                    # Pushed below, so this tick's refresh has nothing to push again.
                    write_state "$_run/language_files.shown" "$_status"
                else
                    case "$_phase" in
                        downloading) _status="Downloading the model... ${_percent:-0}%" ;;
                        compiling)   _status="Preparing the model (the first run of a model is the slow one)..." ;;
                        installing)  _status="Installing the model... ${_percent:-0}%" ;;
                        *)           _status="Checking the model..." ;;
                    esac
                fi
                ;;
            engine.ready)
                /bin/rm -f "$_run/language_files.phase" "$_run/language_files.since" "$_run/language_files.moved" "$_run/language_files.shown"
                if [ "$_kind" = live ]; then
                    _status="Listening. Speak now."
                else
                    _status="Transcribing $_name..."
                fi
                ;;
            warning)
                printf '%s\n' "$_message" >> "$_run/warnings.txt"
                ;;
            error)
                [ -s "$_run/error.txt" ] || write_state "$_run/error.txt" "$_message"
                write_state "$_run/state" failed
                ;;
            done)
                if [ "$_kind" = live ]; then
                    # A live session runs at the speaker's pace, so a speed figure means nothing.
                    write_state "$_run/summary.txt" "$_segments segments, $(format_seconds "$_audio") of audio"
                else
                    write_state "$_run/summary.txt" "$_segments segments, $(format_seconds "$_audio") of audio in $(format_seconds "$_wall") (${_rtfx}x real time)"
                fi
                # A stop that arrives after the work finished still leaves a finished transcript.
                [ -s "$_run/error.txt" ] || write_state "$_run/state" done
                ;;
        esac
    done < "$_run/events.records"
    /bin/rm -f "$_run/events.records"

    # Only the last status of the batch is worth showing.
    [ -n "$_status" ] && set_status "$_status"

    local _merged=1
    if [ -s "$_run/segments.new" ]; then
        # The last row seen for an id wins, so a final replaces its partial and a refinement
        # replaces its final, whether they arrived in this batch or an earlier one.
        /bin/cat "$_run/segments.tsv" "$_run/segments.new" 2>/dev/null \
            | /usr/bin/awk -F'\t' '$1 ~ /^[0-9]+$/ { row[$1] = $0 } END { for (id in row) print row[id] }' \
            | LC_ALL=C /usr/bin/sort -t "$TAB" -k1,1n > "$_run/segments.tsv.tmp"
        /bin/mv -f "$_run/segments.tsv.tmp" "$_run/segments.tsv"
        _merged=0
    fi
    /bin/rm -f "$_run/segments.new"

    # A live session has no --output of its own; its JSON transcript is built once it is done.
    if [ "$_kind" = live ] && [ "$(read_state "$_run/state")" = done ] && [ ! -f "$_run/result.json" ]; then
        build_live_result "$_run"
    fi
    return "$_merged"
}

# --- Apple's language files --------------------------------------------------------------------
# Before Apple's engines transcribe in a language, macOS may have to download that language's
# files, and speech reports it as model.progress with the locale in `file`. The download can take
# minutes or not move at all: on a metered connection one sat at 0% for 13 minutes with no error.
# So the run keeps what it was last told, and every poller tick rewrites the status with the time
# spent, rather than leaving a frozen percentage on screen until the next event.
#   language_files.phase     listing | installing <US> language name <US> percent
#   language_files.since     epoch seconds of the first installing event
#   language_files.moved     epoch seconds of the last installing event whose percent changed
#   language_files.shown     the status text last pushed, so an unchanged tick writes nothing

note_apple_language_files() {   # $1 = run dir, $2 = phase, $3 = locale, $4 = percent
    local _name="$(language_display_name "${3%%[-_]*}")"
    local _previous="$(read_state "$1/language_files.phase")"
    write_state "$1/language_files.phase" "$2$US$_name$US$4"
    [ "$2" = installing ] || return 0
    local _now="$(/bin/date +%s)"
    [ -f "$1/language_files.since" ] || write_state "$1/language_files.since" "$_now"
    if [ "$_previous" != "$2$US$_name$US$4" ] || [ ! -f "$1/language_files.moved" ]; then
        write_state "$1/language_files.moved" "$_now"
    fi
}

apple_language_files_status() {   # $1 = run dir
    local _record="$(read_state "$1/language_files.phase")"
    [ -n "$_record" ] || return 0
    local _phase="${_record%%"$US"*}"
    local _rest="${_record#*"$US"}"
    local _name="${_rest%%"$US"*}"
    local _percent="${_rest#*"$US"}"
    if [ "$_phase" != installing ]; then
        printf "Checking Apple's %s speech files..." "$_name"
        return 0
    fi
    local _since="$(read_state "$1/language_files.since")"
    local _moved="$(read_state "$1/language_files.moved")"
    local _now="$(/bin/date +%s)"
    local _elapsed=0
    case "$_since" in ''|*[!0-9]*) ;; *) _elapsed=$((_now - _since)) ;; esac
    local _still=0
    case "$_moved" in ''|*[!0-9]*) ;; *) _still=$((_now - _moved)) ;; esac
    local _advice="A slow or metered connection can hold the download back; press Stop to try again later."
    if [ "$_still" -ge 60 ] && [ "${_percent:-0}" = 0 ]; then
        printf "Downloading Apple's %s speech files: nothing has arrived after %s. %s" \
            "$_name" "$(format_clock "$_elapsed")" "$_advice"
    elif [ "$_still" -ge 60 ]; then
        printf "Downloading Apple's %s speech files... %s%%, and nothing more for %s. %s" \
            "$_name" "$_percent" "$(format_clock "$_still")" "$_advice"
    elif [ "$_elapsed" -ge 10 ]; then
        printf "Downloading Apple's %s speech files... %s%% (%s)" "$_name" "${_percent:-0}" "$(format_clock "$_elapsed")"
    else
        printf "Downloading Apple's %s speech files... %s%%" "$_name" "${_percent:-0}"
    fi
}

# Each tick: the status of a run still waiting for Apple's language files, with the time spent.
refresh_language_files_status() {   # $1 = pane dir
    local _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 0
    [ -f "$_run/language_files.since" ] || return 0
    [ "$(read_state "$_run/state")" = running ] || return 0
    local _status="$(apple_language_files_status "$_run")"
    [ -n "$_status" ] || return 0
    [ "$_status" = "$(read_state "$_run/language_files.shown")" ] && return 0
    write_state "$_run/language_files.shown" "$_status"
    set_status "$_status"
}

# The run whose transcript the pane shows. Live shows its current session. Recordings shows the
# selected recording's, or with nothing selected, the one being transcribed.
shown_run_dir() {   # $1 = pane dir
    if [ "$PANE" = recordings ]; then
        local _selected="$(read_state "$1/selected.key")"
        if [ -n "$_selected" ]; then
            printf '%s' "$1/items/$_selected"
            return 0
        fi
    fi
    current_run_dir "$1"
}

# Rebuild the current run's transcript from its segment table, and push it into the window when
# that run is the one shown: one segment per line, in id order, with the leading space some
# engines put before a segment trimmed. A partial segment - words a live session may still
# revise - ends in " ...".
render_transcript() {   # $1 = pane dir
    local _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 0
    /usr/bin/awk -F'\t' '{
        text = $3; sub(/^ +/, "", text); sub(/ +$/, "", text)
        if (text == "") next
        if ($2 == "partial") text = text " ..."
        print text
    }' "$_run/segments.tsv" > "$_run/transcript.txt" 2>/dev/null
    [ "$(shown_run_dir "$1")" = "$_run" ] || return 0
    show_transcript_file "$_run/transcript.txt"
}

# Settle a run whose process has exited: read whatever it wrote last, then decide how it ended.
# A process that exited without a `done` or an `error` event was stopped (if Stop was pressed)
# or died, and its stderr is the only account of why.
finish_if_exited() {   # $1 = pane dir
    local _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 0
    local _state="$(read_state "$_run/state")"
    case "$_state" in running|stopping) ;; *) return 0 ;; esac
    local _pid="$(read_state "$_run/speech.pid")"
    pid_alive "$_pid"
    local _alive=$?
    [ "$_alive" -ne 0 ] || return 0

    process_events "$1"
    local _changed=$?
    [ "$_changed" -eq 0 ] && render_transcript "$1"
    _state="$(read_state "$_run/state")"
    case "$_state" in
        running)
            local _tail="$(/usr/bin/tail -3 "$_run/stderr.log" 2>/dev/null)"
            write_state "$_run/error.txt" "${_tail:-speech exited without reporting a result.}"
            write_state "$_run/state" failed
            ;;
        stopping)
            write_state "$_run/state" stopped
            ;;
    esac
}

# Say once how a live session ended.
reflect_run_end() {   # $1 = pane dir
    local _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 0
    [ -f "$_run/reflected" ] && return 0
    local _state="$(read_state "$_run/state")"
    local _warnings=""
    [ -s "$_run/warnings.txt" ] && _warnings=" $(/usr/bin/head -1 "$_run/warnings.txt")"
    case "$_state" in
        done)
            set_status "Done: $(read_state "$_run/summary.txt").$_warnings"
            ;;
        failed)
            local _message="$(read_state "$_run/error.txt")"
            set_status "Transcription failed: $_message"
            present_alert "Transcription failed" "$_message"
            ;;
        stopped)
            set_status "Stopped. The transcript so far is kept."
            ;;
        *)
            return 0
            ;;
    esac
    : > "$_run/reflected"
    /bin/rm -f "$1/actions.sig"
}

# --- the recordings list -------------------------------------------------------------------------
# <pane>/list.tsv holds the recordings in the order they were added, one path per line. A path
# with a tab or a line break in it cannot be kept in that file, or shown in the table, and is
# refused. Pane state:
#   queue          the paths still to transcribe, one per line
#   batch          running | stopping; absent when no batch is going
#   batch.model, batch.language, batch.total, batch.done   the batch's model, language and count
#   status.note    how the last batch or recording ended, shown until something changes
#   selected.key   the item key of the selected recording
#   capture        the name of the directory of the recording being made, or last made

item_key() { /sbin/md5 -q -s "$1"; }   # $1 = recording path

recording_count() {   # $1 = pane dir
    local _count="$(/usr/bin/awk 'NF { n++ } END { print n + 0 }' "$1/list.tsv" 2>/dev/null)"
    printf '%s' "${_count:-0}"
}

# Add paths to the list. Files only, each once. Prints how many were added.
add_recordings() {   # $1 = pane dir, $2 = paths, one per line
    : >> "$1/list.tsv"
    local _added=0
    local _path
    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        [ -f "$_path" ] || continue
        case "$_path" in *"$TAB"*) continue ;; esac
        /usr/bin/grep -Fxq -- "$_path" "$1/list.tsv"
        local _known=$?
        [ "$_known" -eq 0 ] && continue
        printf '%s\n' "$_path" >> "$1/list.tsv"
        _added=$((_added + 1))
    done <<EOF
$2
EOF
    [ "$_added" -gt 0 ] && /bin/rm -f "$1/status.note"
    printf '%s' "$_added"
}

remove_recording() {   # $1 = pane dir, $2 = path
    # Matched literally: awk -v would read a backslash in the path as an escape and miss the row.
    /usr/bin/grep -Fxv -- "$2" "$1/list.tsv" > "$1/list.tsv.tmp" 2>/dev/null
    /bin/mv -f "$1/list.tsv.tmp" "$1/list.tsv"
    local _key="$(item_key "$2")"
    /bin/rm -rf "$1/items/$_key"
    [ "$(read_state "$1/selected.key")" = "$_key" ] && /bin/rm -f "$1/selected.key"
    /bin/rm -f "$1/status.note"
}

# A dropped item is either a path or a file URL. Prints the path.
path_from_drop_item() {   # $1 = item
    case "$1" in
        file://*)
            # Drop the scheme and an optional localhost host, then decode %XX escapes. Backslashes
            # are doubled first so printf %b cannot read one in the name as an escape.
            local _path="${1#file://}"
            _path="${_path#localhost}"
            _path="$(printf '%s' "$_path" | /usr/bin/sed 's/\\/\\\\/g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
            printf '%b' "$_path"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}

# What the Status column says about a recording.
recording_status() {   # $1 = pane dir, $2 = path
    if [ -f "$1/queue" ]; then
        /usr/bin/grep -Fxq -- "$2" "$1/queue"
        local _queued=$?
        if [ "$_queued" -eq 0 ]; then
            printf 'Waiting'
            return 0
        fi
    fi
    local _item="$1/items/$(item_key "$2")"
    [ -d "$_item" ] || return 0
    local _state="$(read_state "$_item/state")"
    case "$_state" in
        running)  printf 'Transcribing...' ;;
        stopping) printf 'Stopping...' ;;
        stopped)  printf 'Stopped' ;;
        failed)   printf 'Failed: %s' "$(/usr/bin/head -1 "$_item/error.txt" 2>/dev/null)" ;;
        done)
            if [ -s "$_item/saved.name" ]; then
                printf 'Saved as %s' "$(read_state "$_item/saved.name")"
            elif [ -s "$_item/not_saved.txt" ]; then
                printf 'Not saved: %s' "$(read_state "$_item/not_saved.txt")"
            else
                printf 'Transcribed'
            fi
            ;;
    esac
}

# Push the list into the table when a row changed, then put the selection back: a table whose
# rows are replaced cannot be trusted to keep it. Each row is name, status and the path, which
# the table keeps as a hidden third column. The rows are built under a name of this process's
# own: a handler and the poller can render at the same time.
render_recordings_table() {   # $1 = pane dir
    local _rows="$1/rows.tsv.tmp.$$"
    : > "$_rows"
    local _path
    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        printf '%s\t%s\t%s\n' "$(/usr/bin/basename "$_path")" "$(recording_status "$1" "$_path")" "$_path" >> "$_rows"
    done < "$1/list.tsv"
    /usr/bin/cmp -s "$_rows" "$1/rows.tsv"
    local _same=$?
    if [ "$_same" -eq 0 ]; then
        /bin/rm -f "$_rows"
        return 0
    fi
    /bin/mv -f "$_rows" "$1/rows.tsv"
    quiet_begin "$1" table
    "$dialog" "$window_uuid" "$REC_TABLE" omc_table_set_rows_from_stdin < "$1/rows.tsv"
    local _selected="$(read_state "$1/selected.key")"
    [ -n "$_selected" ] || return 0
    _path="$(read_state "$1/items/$_selected/source.path")"
    [ -n "$_path" ] || _path="$(selected_recording_path "$1")"
    [ -n "$_path" ] && "$dialog" "$window_uuid" "$REC_TABLE" omc_select_row_with_content "$_path" 3
    return 0
}

# The path of the selected recording, found by its key in the list; empty when none.
selected_recording_path() {   # $1 = pane dir
    local _selected="$(read_state "$1/selected.key")"
    [ -n "$_selected" ] || return 0
    local _path
    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        if [ "$(item_key "$_path")" = "$_selected" ]; then
            printf '%s' "$_path"
            return 0
        fi
    done < "$1/list.tsv"
}

# --- a batch of recordings ---------------------------------------------------------------------
# Transcribe queues every recording in the list with the pane's model and language. The poller
# does the rest, one recording at a time: advance_batch settles the recording that finished,
# starts the next, and says how the batch ended.

start_batch() {   # $1 = pane dir
    # A new batch supersedes what the last one left: every recording in the list is transcribed
    # again, and a row still showing the previous result would read as this batch's.
    /bin/rm -rf "$1/items"
    /usr/bin/awk 'NF' "$1/list.tsv" > "$1/queue" 2>/dev/null
    write_state "$1/batch.model" "$(read_state "$1/model.id")"
    write_state "$1/batch.language" "$(read_state "$1/language.tag")"
    write_state "$1/batch.total" "$(recording_count "$1")"
    write_state "$1/batch.done" 0
    /bin/rm -f "$1/status.note" "$1/current"
    write_state "$1/batch" running
}

# Start transcribing one recording. A recording that is gone, or cannot be fingerprinted, fails
# here without starting speech; the next tick settles it like any other.
start_item() {   # $1 = pane dir, $2 = path
    local _key="$(item_key "$2")"
    local _item="$1/items/$_key"
    /bin/rm -rf "$_item"
    /bin/mkdir -p "$_item"
    local _mkdir_status=$?
    [ "$_mkdir_status" -eq 0 ] || return 1
    local _model="$(read_state "$1/batch.model")"
    local _language="$(read_state "$1/batch.language")"
    local _done="$(read_state "$1/batch.done")"
    case "$_done" in ''|*[!0-9]*) _done=0 ;; esac
    _done=$((_done + 1))
    write_state "$1/batch.done" "$_done"

    : > "$_item/segments.tsv"
    write_state "$_item/kind" file
    write_state "$_item/source.path" "$2"
    write_state "$_item/model" "$_model"
    write_state "$_item/language" "$_language"
    local _total="$(read_state "$1/batch.total")"
    [ "${_total:-1}" -gt 1 ] && write_state "$_item/position" "$_done of $_total"

    if [ ! -f "$2" ]; then
        write_state "$_item/error.txt" "The recording is no longer there."
        write_state "$_item/state" failed
        write_state "$1/current" "items/$_key"
        return 0
    fi
    local _fp
    _fp="$(fingerprint_of "$2")"
    local _fp_status=$?
    if [ "$_fp_status" -ne 0 ]; then
        write_state "$_item/error.txt" "The recording could not be read."
        write_state "$_item/state" failed
        write_state "$1/current" "items/$_key"
        return 0
    fi
    write_state "$_item/recording.fp" "$_fp"
    write_state "$_item/state" running
    local _pid="$(spawn_transcribe "$_item" "$2" "$_model" "$_language")"
    write_state "$_item/speech.pid" "$_pid"
    # The item becomes current only once its pid is on disk: the poller settles a running run
    # whose process it cannot find as failed.
    write_state "$1/current" "items/$_key"
    [ -n "$(read_state "$1/selected.key")" ] || show_transcript_file ""
}

# The name a transcript gets beside its recording: the recording's name without its extension,
# then the model, so transcripts from different models sit side by side.
transcript_name_for() {   # $1 = recording path, $2 = model id
    local _stem="$(/usr/bin/basename "$1")"
    case "$_stem" in
        ?*.*) _stem="${_stem%.*}" ;;
    esac
    local _model="$(printf '%s' "$2" | /usr/bin/tr '/:' '--')"
    printf '%s - %s.txt' "$_stem" "$_model"
}

# Write a finished item's transcript beside its recording, as plain text through `speech export`.
# An existing file of that name is replaced only when Speech wrote it and neither it nor the
# recording has changed since; anything else is left alone and the reason recorded, and the
# transcript stays in the window, where Export and Copy still reach it.
save_transcript() {   # $1 = item dir
    local _source="$(read_state "$1/source.path")"
    local _name="$(transcript_name_for "$_source" "$(read_state "$1/model")")"
    local _dir="$(/usr/bin/dirname "$_source")"
    local _dest="$_dir/$_name"

    "$SPEECH_BIN" export "$1/result.json" --format txt --output "$1/transcript.export.txt" > /dev/null 2> "$1/export.err"
    local _export_status=$?
    if [ "$_export_status" -ne 0 ] || [ ! -f "$1/transcript.export.txt" ]; then
        write_state "$1/not_saved.txt" "the transcript could not be converted to text ($(/usr/bin/head -1 "$1/export.err" 2>/dev/null))."
        return 0
    fi

    local _recording_fp
    _recording_fp="$(fingerprint_of "$_source")"
    local _fp_status=$?
    if [ "$_fp_status" -ne 0 ] || [ "$_recording_fp" != "$(read_state "$1/recording.fp")" ]; then
        write_state "$1/not_saved.txt" "the recording changed while it was being transcribed."
        return 0
    fi

    if [ -e "$_dest" ] || [ -L "$_dest" ]; then
        if [ -L "$_dest" ] || [ ! -f "$_dest" ]; then
            write_state "$1/not_saved.txt" "$_name exists and is not a plain file."
            return 0
        fi
        local _record="$(/usr/bin/xattr -p "$TRANSCRIPT_XATTR" "$_dest" 2>/dev/null)"
        local _tag _recorded_recording _recorded_transcript _extra
        read -r _tag _recorded_recording _recorded_transcript _extra <<EOF
$_record
EOF
        if [ "$_tag" != speech-transcript-v1 ] || [ -z "$_recorded_transcript" ]; then
            write_state "$1/not_saved.txt" "$_name already exists and was not written by Speech."
            return 0
        fi
        local _existing_fp
        _existing_fp="$(fingerprint_of "$_dest")"
        _fp_status=$?
        if [ "$_fp_status" -ne 0 ] || [ "$_existing_fp" != "$_recorded_transcript" ]; then
            write_state "$1/not_saved.txt" "$_name was edited after Speech wrote it."
            return 0
        fi
        if [ "$_recorded_recording" != "$_recording_fp" ]; then
            write_state "$1/not_saved.txt" "$_name was written from a different version of the recording."
            return 0
        fi
    fi

    # Written under a hidden name in the same folder, stamped, then renamed over the destination,
    # so the name never holds half a transcript or one without its record.
    local _tmp="$_dir/.$_name.speech-$$"
    /bin/cp -f "$1/transcript.export.txt" "$_tmp" 2>/dev/null
    local _cp_status=$?
    if [ "$_cp_status" -ne 0 ]; then
        /bin/rm -f "$_tmp"
        write_state "$1/not_saved.txt" "Speech cannot write into $_dir."
        return 0
    fi
    local _transcript_fp
    _transcript_fp="$(fingerprint_of "$_tmp")"
    _fp_status=$?
    if [ "$_fp_status" -ne 0 ]; then
        /bin/rm -f "$_tmp"
        write_state "$1/not_saved.txt" "the transcript could not be fingerprinted."
        return 0
    fi
    /usr/bin/xattr -w "$TRANSCRIPT_XATTR" "speech-transcript-v1 $_recording_fp $_transcript_fp" "$_tmp" 2>/dev/null
    local _xattr_status=$?
    if [ "$_xattr_status" -ne 0 ]; then
        /bin/rm -f "$_tmp"
        write_state "$1/not_saved.txt" "the file system in $_dir does not keep the record Speech needs to replace it safely later."
        return 0
    fi
    /bin/mv -f "$_tmp" "$_dest"
    local _mv_status=$?
    if [ "$_mv_status" -ne 0 ]; then
        /bin/rm -f "$_tmp"
        write_state "$1/not_saved.txt" "Speech could not put $_name in place."
        return 0
    fi
    write_state "$1/saved.name" "$_name"
}

# Settle the recording that finished, start the next one, or say how the batch ended. Called by
# the poller after finish_if_exited, so a current item that is no longer active has exited and
# been read to the end.
advance_batch() {   # $1 = pane dir
    local _batch="$(read_state "$1/batch")"
    [ -n "$_batch" ] || return 0
    local _run="$(current_run_dir "$1")"
    if [ -n "$_run" ]; then
        case "$(read_state "$_run/state")" in running|stopping) return 0 ;; esac
        if [ ! -f "$_run/settled" ]; then
            [ "$(read_state "$_run/state")" = done ] && save_transcript "$_run"
            : > "$_run/settled"
        fi
        /bin/rm -f "$1/current"
    fi

    local _next=""
    [ "$_batch" = running ] && _next="$(/usr/bin/head -1 "$1/queue" 2>/dev/null)"
    if [ -z "$_next" ]; then
        /bin/rm -f "$1/queue" "$1/batch"
        write_state "$1/status.note" "$(batch_summary "$1" "$_batch")"
        set_status "$(read_state "$1/status.note")"
        /bin/rm -f "$1/actions.sig"
        return 0
    fi
    /usr/bin/tail -n +2 "$1/queue" > "$1/queue.tmp"
    /bin/mv -f "$1/queue.tmp" "$1/queue"
    start_item "$1" "$_next"
    set_status "Transcribing $(/usr/bin/basename "$_next")..."
    /bin/rm -f "$1/actions.sig"

    # Stop can land between the batch being read as running above and the recording starting, and
    # then finds no process to signal. Catch it here, or the recording would run to its end.
    [ "$(read_state "$1/batch")" = stopping ] || return 0
    _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 0
    [ "$(read_state "$_run/state")" = running ] || return 0
    write_state "$_run/state" stopping
    signal_speech_pid "$(read_state "$_run/speech.pid")" TERM
}

# How a batch ended, counted over the list.
batch_summary() {   # $1 = pane dir, $2 = running | stopping
    local _saved=0 _not_saved=0 _failed=0
    local _path _item
    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        _item="$1/items/$(item_key "$_path")"
        [ -d "$_item" ] || continue
        case "$(read_state "$_item/state")" in
            done)
                if [ -s "$_item/saved.name" ]; then _saved=$((_saved + 1)); else _not_saved=$((_not_saved + 1)); fi
                ;;
            failed) _failed=$((_failed + 1)) ;;
        esac
    done < "$1/list.tsv"
    local _text
    if [ "$2" = stopping ]; then
        _text="Stopped."
    else
        _text="Done."
    fi
    _text="$_text $_saved saved beside the recording"
    [ "$_saved" = 1 ] || _text="$_text""s"
    [ "$_not_saved" -gt 0 ] && _text="$_text, $_not_saved not saved"
    [ "$_failed" -gt 0 ] && _text="$_text, $_failed failed"
    [ "$_not_saved" -gt 0 ] || [ "$_failed" -gt 0 ] && _text="$_text - the Status column says why"
    printf '%s.' "$_text"
}

# --- recording a new file ------------------------------------------------------------------------
# Record runs `speech record` into a new file in the recordings folder, with the same stdin holder
# as a live session, so Stop is "q" and a closed window or a vanished app is end of input: every
# ending goes through speech's tidy path, which keeps what was recorded. The poller shows the
# input level while it runs and, once it has ended, adds the file to the list and selects it.

capture_dir() {   # $1 = pane dir; prints the directory of the recording being made, or last made
    local _name="$(read_state "$1/capture")"
    [ -n "$_name" ] || return 1
    [ -d "$1/$_name" ] || return 1
    printf '%s' "$1/$_name"
}

# Returns 0 while a new recording is being made.
capture_is_active() {   # $1 = pane dir
    local _dir="$(capture_dir "$1")"
    [ -n "$_dir" ] || return 1
    case "$(read_state "$_dir/state")" in running|stopping) return 0 ;; esac
    return 1
}

# A path for a new recording that does not exist yet: "Recording <stamp>.m4a", then "... 2.m4a"
# and on. `speech record` refuses to replace a file, so a name already taken would only fail later.
recording_path_for() {   # $1 = directory, $2 = time stamp
    local _base="$1/Recording $2"
    local _path="$_base.m4a"
    local _n=2
    while [ -e "$_path" ] || [ -L "$_path" ]; do
        _path="$_base $_n.m4a"
        _n=$((_n + 1))
    done
    printf '%s' "$_path"
}

# An input level in dBFS as a gauge value from 0 to 1: -60 dB and below is empty, 0 dB is full.
# Anything that is not a number reads as silence.
level_from_db() {   # $1 = dB
    /usr/bin/awk -v db="$1" 'BEGIN {
        if (db !~ /^-?[0-9.]+$/) { print "0.00"; exit }
        v = (db + 60) / 60
        if (v < 0) v = 0
        if (v > 1) v = 1
        printf "%.2f", v
    }'
}

# Consume the recording's new events: the elapsed time and level go to the status line and the
# gauge, a warning is kept, an error or `done` settles the state. speech.record-events.jq turns
# each event into one record.
process_capture_events() {   # $1 = pane dir
    local _dir="$(capture_dir "$1")"
    [ -n "$_dir" ] || return 1
    consume_new_events "$_dir" "$SCRIPTS_DIR/speech.record-events.jq"
    local _consumed_status=$?
    [ "$_consumed_status" -eq 0 ] || return 1

    local _seconds=""
    local _level=""
    local _type _event_seconds _rms _message _audio
    while IFS="$US" read -r _type _event_seconds _rms _message _audio; do
        case "$_type" in
            recording.started)
                _seconds=0
                _level="0.00"
                ;;
            recording.level)
                _seconds="$_event_seconds"
                _level="$(level_from_db "$_rms")"
                ;;
            warning)
                printf '%s\n' "$_message" >> "$_dir/warnings.txt"
                ;;
            error)
                [ -s "$_dir/error.txt" ] || write_state "$_dir/error.txt" "$_message"
                write_state "$_dir/state" failed
                ;;
            done)
                write_state "$_dir/audio_seconds" "$_audio"
                [ -s "$_dir/error.txt" ] || write_state "$_dir/state" done
                ;;
        esac
    done < "$_dir/events.records"
    /bin/rm -f "$_dir/events.records"

    [ "$(read_state "$_dir/state")" = running ] || return 0
    if [ -n "$_seconds" ]; then
        set_status "Recording $(/usr/bin/basename "$(read_state "$_dir/output.path")")... $(format_clock "$_seconds")"
    fi
    if [ -n "$_level" ] && [ "$_level" != "$(read_state "$_dir/level")" ]; then
        write_state "$_dir/level" "$_level"
        "$dialog" "$window_uuid" "$REC_LEVEL" "$_level"
    fi
    return 0
}

# Settle a recording whose process has exited, the way finish_if_exited settles a transcription.
finish_capture_if_exited() {   # $1 = pane dir
    local _dir="$(capture_dir "$1")"
    [ -n "$_dir" ] || return 0
    case "$(read_state "$_dir/state")" in running|stopping) ;; *) return 0 ;; esac
    pid_alive "$(read_state "$_dir/speech.pid")"
    local _alive=$?
    [ "$_alive" -ne 0 ] || return 0

    process_capture_events "$1"
    case "$(read_state "$_dir/state")" in
        running)
            local _tail="$(/usr/bin/tail -3 "$_dir/stderr.log" 2>/dev/null)"
            write_state "$_dir/error.txt" "${_tail:-speech exited without finishing the recording.}"
            write_state "$_dir/state" failed
            ;;
        stopping)
            write_state "$_dir/state" stopped
            ;;
    esac
}

# Say once how a recording ended. A file that exists joins the list and is selected, whatever
# ended the recording, because `speech record` keeps what it captured before a failure; only a
# recording that left no file raises an alert.
settle_capture() {   # $1 = pane dir
    local _dir="$(capture_dir "$1")"
    [ -n "$_dir" ] || return 0
    [ -f "$_dir/settled" ] && return 0
    local _state="$(read_state "$_dir/state")"
    case "$_state" in running|stopping|'') return 0 ;; esac
    : > "$_dir/settled"

    local _output="$(read_state "$_dir/output.path")"
    local _name="$(/usr/bin/basename "$_output")"
    local _message="$(read_state "$_dir/error.txt")"
    if [ -n "$_output" ] && [ -f "$_output" ]; then
        add_recordings "$1" "$_output" > /dev/null
        write_state "$1/selected.key" "$(item_key "$_output")"
        render_recordings_table "$1"
        show_transcript_file ""
        local _note
        if [ "$_state" = failed ]; then
            _note="The recording stopped early: $_message What was recorded is in $_name, now in the list."
        else
            _note="Recorded $_name"
            local _audio="$(read_state "$_dir/audio_seconds")"
            [ -n "$_audio" ] && _note="$_note ($(format_seconds "$_audio"))"
            _note="$_note. It is in the list, ready to transcribe."
            [ -s "$_dir/warnings.txt" ] && _note="$_note $(/usr/bin/head -1 "$_dir/warnings.txt")"
        fi
        write_state "$1/status.note" "$_note"
        set_status "$_note"
    else
        [ -n "$_message" ] || _message="speech exited without writing a recording."
        write_state "$1/status.note" "Recording failed: $_message"
        set_status "Recording failed: $_message"
        present_alert "Recording failed" "$_message"
    fi
    /bin/rm -f "$1/actions.sig"
}

# --- one poller tick per pane --------------------------------------------------------------------
# The poller runs these every half second; the tests run them as one tick.

poll_live() {   # $1 = spool
    use_pane live
    local _pane="$1/live"
    [ -d "$_pane" ] || return 0
    local _run="$(current_run_dir "$_pane")"
    if [ -n "$_run" ]; then
        process_events "$_pane"
        local _changed=$?
        [ "$_changed" -eq 0 ] && render_transcript "$_pane"
        refresh_language_files_status "$_pane"
        finish_if_exited "$_pane"
        reflect_run_end "$_pane"
    fi
    refresh_live_actions "$_pane"
}

poll_recordings() {   # $1 = spool
    use_pane recordings
    local _pane="$1/recordings"
    [ -d "$_pane" ] || return 0
    local _capture="$(capture_dir "$_pane")"
    if [ -n "$_capture" ]; then
        process_capture_events "$_pane"
        finish_capture_if_exited "$_pane"
        settle_capture "$_pane"
    fi
    local _run="$(current_run_dir "$_pane")"
    if [ -n "$_run" ]; then
        process_events "$_pane"
        local _changed=$?
        [ "$_changed" -eq 0 ] && render_transcript "$_pane"
        refresh_language_files_status "$_pane"
        finish_if_exited "$_pane"
    fi
    advance_batch "$_pane"
    [ -f "$_pane/list.tsv" ] && render_recordings_table "$_pane"
    refresh_recordings_actions "$_pane"
}

# --- enabling controls -------------------------------------------------------------------------
# One function per pane decides every control's state from the spool, so a handler and the poller
# cannot disagree. The poller calls them every tick; the signature file keeps a tick that changes
# nothing from writing to the window, and a handler that changes state removes the signature.

refresh_live_actions() {   # $1 = pane dir
    use_pane live
    local _pane="$1"
    local _model="$(read_state "$_pane/model.id")"
    local _models_ready=0
    [ -f "$_pane/models.tsv" ] && _models_ready=1
    local _run="$(current_run_dir "$_pane")"
    local _state=""
    [ -n "$_run" ] && _state="$(read_state "$_run/state")"

    local _active=0
    case "$_state" in running|stopping) _active=1 ;; esac
    other_pane_is_busy "$_pane"
    local _other_status=$?
    local _other_busy=0
    [ "$_other_status" -eq 0 ] && _other_busy=1
    capture_is_active "$(/usr/bin/dirname "$_pane")/recordings"
    local _capture_status=$?
    local _other_recording=0
    [ "$_capture_status" -eq 0 ] && _other_recording=1
    local _can_live=0
    [ "$_active" = 0 ] && [ "$_other_busy" = 0 ] && [ -n "$_model" ] && _can_live=1
    local _can_stop=0
    [ "$_state" = running ] && _can_stop=1
    local _can_export=0
    [ "$_active" = 0 ] && [ -n "$_run" ] && [ -s "$_run/result.json" ] && _can_export=1
    local _can_copy=0
    [ "$_active" = 0 ] && [ -n "$_run" ] && [ -s "$_run/transcript.txt" ] && _can_copy=1
    local _can_pick=0
    [ "$_active" = 0 ] && [ "$_models_ready" = 1 ] && [ -n "$_model" ] && _can_pick=1
    # The Model picker stays open with no model to offer: its last option opens the Models window.
    local _can_pick_model=0
    [ "$_active" = 0 ] && [ "$_models_ready" = 1 ] && _can_pick_model=1

    local _signature="$_can_live$_can_stop$_can_export$_can_copy$_can_pick|$_models_ready|$_state|$_other_busy$_other_recording|$_model"
    [ "$_signature" = "$(read_state "$_pane/actions.sig")" ] && return 0
    write_state "$_pane/actions.sig" "$_signature"

    set_enabled "$LIVE_BTN" "$_can_live"
    set_enabled "$LIVE_STOP_BTN" "$_can_stop"
    set_enabled "$LIVE_EXPORT_MENU" "$_can_export"
    set_enabled "$LIVE_COPY_BTN" "$_can_copy"
    set_enabled "$LIVE_MODEL_PICKER" "$_can_pick_model"
    set_enabled "$LIVE_LANGUAGE_PICKER" "$_can_pick"

    # With no session to report on, the status line says what the tab is waiting for.
    [ -z "$_run" ] || return 0
    [ "$_models_ready" = 1 ] || return 0
    if [ -z "$_model" ]; then
        set_status "No speech model on this Mac can transcribe live yet. Choose $DOWNLOAD_MODELS_OPTION in the Model picker to get one."
    elif [ "$_other_recording" = 1 ]; then
        set_status "A recording is being made in the Recordings tab. Live is available when it is done."
    elif [ "$_other_busy" = 1 ]; then
        set_status "Recordings are being transcribed. Live is available when they are done."
    else
        set_status "Press Live to transcribe the microphone with $(tsv_field "$_pane/models.tsv" "$_model" 2)."
    fi
}

refresh_recordings_actions() {   # $1 = pane dir
    use_pane recordings
    local _pane="$1"
    local _model="$(read_state "$_pane/model.id")"
    local _models_ready=0
    [ -f "$_pane/models.tsv" ] && _models_ready=1
    local _batch="$(read_state "$_pane/batch")"
    local _count="$(recording_count "$_pane")"
    local _selected="$(read_state "$_pane/selected.key")"
    local _item=""
    local _item_state=""
    if [ -n "$_selected" ] && [ -d "$_pane/items/$_selected" ]; then
        _item="$_pane/items/$_selected"
        _item_state="$(read_state "$_item/state")"
    fi
    local _capture="$(capture_dir "$_pane")"
    local _capture_state=""
    [ -n "$_capture" ] && _capture_state="$(read_state "$_capture/state")"
    local _recording=0
    case "$_capture_state" in running|stopping) _recording=1 ;; esac

    local _active=0
    [ -n "$_batch" ] && _active=1
    other_pane_is_busy "$_pane"
    local _other_status=$?
    local _other_busy=0
    [ "$_other_status" -eq 0 ] && _other_busy=1
    local _can_transcribe=0
    [ "$_active" = 0 ] && [ "$_recording" = 0 ] && [ "$_other_busy" = 0 ] && [ "$_count" -gt 0 ] && [ -n "$_model" ] && _can_transcribe=1
    local _can_record=0
    [ "$_active" = 0 ] && [ "$_recording" = 0 ] && [ "$_other_busy" = 0 ] && _can_record=1
    local _can_stop=0
    [ "$_batch" = running ] && _can_stop=1
    [ "$_capture_state" = running ] && _can_stop=1
    local _item_finished=0
    case "$_item_state" in done|stopped|failed) _item_finished=1 ;; esac
    local _can_export=0
    [ "$_item_finished" = 1 ] && [ -s "$_item/result.json" ] && _can_export=1
    local _can_copy=0
    [ "$_item_finished" = 1 ] && [ -s "$_item/transcript.txt" ] && _can_copy=1
    # Remove and the pickers wait for a recording too: their handlers refuse a busy pane, and an
    # enabled picker would show a choice the pane did not take.
    local _can_remove=0
    [ "$_active" = 0 ] && [ "$_recording" = 0 ] && [ -n "$_selected" ] && _can_remove=1
    local _can_pick=0
    [ "$_active" = 0 ] && [ "$_recording" = 0 ] && [ "$_models_ready" = 1 ] && [ -n "$_model" ] && _can_pick=1
    # The Model picker stays open with no model to offer: its last option opens the Models window.
    local _can_pick_model=0
    [ "$_active" = 0 ] && [ "$_recording" = 0 ] && [ "$_models_ready" = 1 ] && _can_pick_model=1

    local _signature="$_can_transcribe$_can_record$_can_stop$_can_export$_can_copy$_can_remove$_can_pick|$_models_ready|$_batch|$_capture_state|$_other_busy|$_count|$_selected|$_item_state|$_model"
    [ "$_signature" = "$(read_state "$_pane/actions.sig")" ] && return 0
    write_state "$_pane/actions.sig" "$_signature"

    set_enabled "$REC_TRANSCRIBE_BTN" "$_can_transcribe"
    set_enabled "$REC_RECORD_BTN" "$_can_record"
    set_enabled "$REC_STOP_BTN" "$_can_stop"
    set_enabled "$REC_EXPORT_MENU" "$_can_export"
    set_enabled "$REC_COPY_BTN" "$_can_copy"
    set_enabled "$REC_REMOVE_BTN" "$_can_remove"
    set_enabled "$REC_MODEL_PICKER" "$_can_pick_model"
    set_enabled "$REC_LANGUAGE_PICKER" "$_can_pick"
    if [ "$_recording" = 1 ]; then
        "$dialog" "$window_uuid" "$REC_LEVEL" omc_show
    else
        "$dialog" "$window_uuid" "$REC_LEVEL" omc_hide
    fi

    # With nothing going on and no note about how the last batch or recording ended, the status
    # line says what the tab is waiting for.
    [ "$_active" = 0 ] && [ "$_recording" = 0 ] || return 0
    [ -f "$_pane/status.note" ] && return 0
    [ "$_models_ready" = 1 ] || return 0
    local _label="$(tsv_field "$_pane/models.tsv" "$_model" 2)"
    if [ -z "$_model" ]; then
        set_status "No speech model can run on this Mac yet. Choose $DOWNLOAD_MODELS_OPTION in the Model picker to get one."
    elif [ "$_count" = 0 ]; then
        set_status "Drop recordings here or add them, or press Record, then Transcribe. Each transcript is saved beside its recording."
    elif [ "$_other_busy" = 1 ]; then
        set_status "A live session is running. Stop it to transcribe recordings."
    elif [ "$_count" = 1 ]; then
        set_status "Ready to transcribe 1 recording with $_label."
    else
        set_status "Ready to transcribe $_count recordings with $_label."
    fi
}

# --- export ------------------------------------------------------------------------------------

# Convert a finished transcript to a format with `speech export`, to the path the Save panel
# returned. The extension is added when the name typed has none of its own.
export_transcript() {   # $1 = format (txt, srt, vtt, json), $2 = run dir
    local _dest="${OMC_DLG_SAVE_AS_PATH:-}"
    [ -n "$_dest" ] || return 0
    if [ -z "$2" ] || [ ! -s "$2/result.json" ]; then
        present_alert "Nothing to export" "Transcribe a recording first."
        return 0
    fi
    case "$_dest" in
        *."$1") ;;
        *) _dest="$_dest.$1" ;;
    esac
    "$SPEECH_BIN" export "$2/result.json" --format "$1" --output "$_dest" > /dev/null 2> "$2/export.err"
    local _export_status=$?
    if [ "$_export_status" -ne 0 ]; then
        present_alert "Could not export the transcript" "$(/usr/bin/head -3 "$2/export.err")"
        return 0
    fi
    set_status "Exported to $(/usr/bin/basename "$_dest")."
}
