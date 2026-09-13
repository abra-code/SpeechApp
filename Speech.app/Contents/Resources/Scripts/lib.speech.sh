# lib.speech.sh - shared library for the Speech applet. Sourced by every handler and by the
# window poller (speech.poll.sh). POSIX /bin/sh (macOS bash 3.2): validate with `sh -n`, never
# `bash -n`.

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

# --- Substitutable outside world ---------------------------------------------------------------
# Everything below names something a test must not reach for real: the speech binary, which
# loads gigabytes of weights and opens the microphone; the background poller, which would keep
# writing into the window while a test reads it back; and the user's real model store, settings
# and session state. omctest intercepts the OMC support tools but cannot redirect an absolute or
# bundle-relative path, so a variable is the only seam. Nothing sets these in normal use.
#
# Two environment namespaces share the SPEECH_ prefix and must not be treated as one set. The
# ones read here (SPEECH_BIN, SPEECH_POLL_SCRIPT, SPEECH_APP_SUPPORT) are this applet's test
# hooks. SPEECH_MODELS_DIR and SPEECH_CATALOG_DIR, exported below, are the speech binary's own
# production configuration.
SPEECH_BIN="${SPEECH_BIN:-$OMC_APP_BUNDLE_PATH/Contents/Support/speech}"
POLL_SCRIPT="${SPEECH_POLL_SCRIPT:-$SCRIPTS_DIR/speech.poll.sh}"
APP_SUPPORT="${SPEECH_APP_SUPPORT:-$HOME/Library/Application Support/Speech}"
SESSIONS_DIR="$APP_SUPPORT/Sessions"
SETTINGS_DIR="$APP_SUPPORT/Settings"

# The speech binary's model store and user catalog, exported so every speech process this applet
# starts lands in the applet's store without each call site passing --models-dir. The CLI's own
# defaults are the same two paths today, but only by construction: computing them in one place
# is what keeps a test that redirects SPEECH_APP_SUPPORT from reading the user's real models.
SPEECH_MODELS_DIR="$APP_SUPPORT/Models"
SPEECH_CATALOG_DIR="$APP_SUPPORT/Catalog"
export SPEECH_MODELS_DIR SPEECH_CATALOG_DIR

# ActionUI control ids (must match speech.window.json).
TAB_VIEW=5
MODEL_PICKER=25
LANGUAGE_PICKER=26
TRANSCRIBE_BTN=40
STOP_BTN=41
EXPORT_MENU=50
COPY_BTN=55
SOURCE_TEXT=110
CHOOSE_BTN=111
TRANSCRIPT_EDITOR=200
STATUS_TEXT=300

# The one global handoff key: a file opened from Finder, the Dock, File > Open or the Services
# menu is stashed here and consumed by the window that opens for it.
PB_OPEN_PATH="SPEECH_OPEN_PATH"

# --- small helpers -----------------------------------------------------------------------------

pb_set() { "$pasteboard" "$1" set "$2"; }
pb_get() { "$pasteboard" "$1" get 2>/dev/null; }

# Open a new window for a file: stash the path for speech.window.init, then chain to the window.
route_file() {   # $1 = file path
    pb_set "$PB_OPEN_PATH" "$1"
    "$next_command" "$OMC_CURRENT_COMMAND_GUID" "speech.new"
}

spool_dir_for() { printf '%s' "$SESSIONS_DIR/$1"; }

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

# --- picker quiet window -----------------------------------------------------------------------
# Programmatic option and selection updates can fire a picker's actionID with a transitional
# value. Every programmatic update opens a two-second window in which the change handlers do
# nothing, so an echo can neither switch the model nor overwrite a saved preference.

quiet_begin() {   # $1 = spool
    local _now="$(/bin/date +%s)"
    write_state "$1/picker_quiet" "$((_now + 2))"
}

# Returns 0 while the quiet window is open.
quiet_active() {   # $1 = spool
    local _until="$(read_state "$1/picker_quiet")"
    case "$_until" in ''|*[!0-9]*) return 1 ;; esac
    local _now="$(/bin/date +%s)"
    [ "$_now" -lt "$_until" ]
}

# --- the model list ----------------------------------------------------------------------------
# models.tsv in the spool holds the rows this window can transcribe with, in picker order:
#   id <TAB> label <TAB> languages <TAB> modes <TAB> capabilities
# speech.catalog.jq decides which rows qualify. Returns non-zero, with the reason in the spool's
# catalog.err, when the catalog cannot be read.

load_models() {   # $1 = spool
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

# Fill the Model picker from models.tsv and settle the selection: the saved model if it is still
# runnable, else apple.transcriber when present, else the first row. The selection is recorded
# in the spool's model.id, which every handler reads rather than trusting a picker index.
populate_model_picker() {   # $1 = spool
    local _spool="$1"
    local _options="["
    local _first=1
    local _id _label _rest
    while IFS="$TAB" read -r _id _label _rest; do
        [ -n "$_id" ] || continue
        if [ "$_first" = 1 ]; then _first=0; else _options="$_options,"; fi
        _options="$_options\"$(json_escape "$_label")\""
    done < "$_spool/models.tsv"

    if [ "$_first" = 1 ]; then
        /bin/rm -f "$_spool/model.id" "$_spool/languages.tsv" "$_spool/language.tag"
        quiet_begin "$_spool"
        "$dialog" "$window_uuid" "$MODEL_PICKER" omc_set_property "options" '["No models available"]'
        "$dialog" "$window_uuid" "$LANGUAGE_PICKER" omc_set_property "options" '["-"]'
        return 0
    fi
    _options="$_options]"

    local _selected=""
    local _saved="$(setting_get model)"
    local _line
    if [ -n "$_saved" ]; then
        _line="$(tsv_line_of "$_spool/models.tsv" "$_saved")"
        [ -n "$_line" ] && _selected="$_saved"
    fi
    if [ -z "$_selected" ]; then
        _line="$(tsv_line_of "$_spool/models.tsv" apple.transcriber)"
        [ -n "$_line" ] && _selected="apple.transcriber"
    fi
    if [ -z "$_selected" ]; then
        _selected="$(/usr/bin/head -1 "$_spool/models.tsv" | /usr/bin/cut -f1)"
    fi
    _line="$(tsv_line_of "$_spool/models.tsv" "$_selected")"
    write_state "$_spool/model.id" "$_selected"

    quiet_begin "$_spool"
    "$dialog" "$window_uuid" "$MODEL_PICKER" omc_set_property "options" "$_options"
    "$dialog" "$window_uuid" "$MODEL_PICKER" "$_line"
    populate_language_picker "$_spool"
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

# Fill the Language picker for the selected model. languages.tsv in the spool holds the options
# in picker order: tag <TAB> display name. The tags are the model's own spelling, which is what
# speech has to be given back.
#
# "Automatic" is offered only to a model that identifies languages itself (lang_id). The others
# need a language: Apple's engines refuse to run without one, and Canary given none silently
# translates into English rather than failing.
populate_language_picker() {   # $1 = spool
    local _spool="$1"
    local _model="$(read_state "$_spool/model.id")"
    local _languages="$(tsv_field "$_spool/models.tsv" "$_model" 3)"
    local _caps="$(tsv_field "$_spool/models.tsv" "$_model" 5)"

    : > "$_spool/languages.unsorted"
    local _tag
    if [ "$_languages" = "*" ]; then
        # The engine reports no list of its own: offer every language the name table knows.
        /usr/bin/awk -F'\t' '!/^#/ && NF >= 2 { printf "%s\t%s\n", $1, $2 }' "$RESOURCES_DIR/languages.tsv" > "$_spool/languages.unsorted" 2>/dev/null
    else
        for _tag in $(printf '%s' "$_languages" | /usr/bin/tr ',' ' '); do
            printf '%s\t%s\n' "$_tag" "$(language_display_name "$_tag")" >> "$_spool/languages.unsorted"
        done
    fi

    : > "$_spool/languages.tsv.tmp"
    case ",$_caps," in
        *,lang_id,*) printf 'auto\tAutomatic\n' >> "$_spool/languages.tsv.tmp" ;;
    esac
    LC_ALL=C /usr/bin/sort -t "$TAB" -k2,2f "$_spool/languages.unsorted" >> "$_spool/languages.tsv.tmp"
    /bin/mv -f "$_spool/languages.tsv.tmp" "$_spool/languages.tsv"
    /bin/rm -f "$_spool/languages.unsorted"

    local _options="["
    local _first=1
    local _name
    while IFS="$TAB" read -r _tag _name; do
        [ -n "$_tag" ] || continue
        if [ "$_first" = 1 ]; then _first=0; else _options="$_options,"; fi
        _options="$_options\"$(json_escape "$_name")\""
    done < "$_spool/languages.tsv"
    _options="$_options]"

    # The selection: the saved language when this model offers it, else Automatic when offered,
    # else the language of the user's locale, else English, else the first entry. Matching falls
    # back to the primary subtag, so a saved "pl" still finds a model's "pl-PL".
    local _selected=""
    local _want
    local _saved="$(setting_get language)"
    local _locale_language="$(printf '%s' "${LANG%%[_.]*}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    for _want in "$_saved" auto "$_locale_language" en; do
        [ -n "$_want" ] || continue
        _selected="$(/usr/bin/awk -F'\t' -v want="$_want" '
            { tag = tolower($1); primary = tag; sub(/[-_].*/, "", primary) }
            tag == tolower(want) { print $1; found = 1; exit }
            primary == tolower(want) && first == "" { first = $1 }
            END { if (!found && first != "") print first }
        ' "$_spool/languages.tsv")"
        [ -n "$_selected" ] && break
    done
    [ -n "$_selected" ] || _selected="$(/usr/bin/head -1 "$_spool/languages.tsv" | /usr/bin/cut -f1)"
    write_state "$_spool/language.tag" "$_selected"
    local _line="$(tsv_line_of "$_spool/languages.tsv" "$_selected")"

    quiet_begin "$_spool"
    "$dialog" "$window_uuid" "$LANGUAGE_PICKER" omc_set_property "options" "$_options"
    [ -n "$_line" ] && "$dialog" "$window_uuid" "$LANGUAGE_PICKER" "$_line"
    return 0
}

# --- the recording being transcribed ---------------------------------------------------------

# Point the window at a recording. Whatever the previous run produced described a different
# recording, so it goes too.
set_source() {   # $1 = spool, $2 = file path
    write_state "$1/source.path" "$2"
    local _name="$(/usr/bin/basename "$2")"
    "$dialog" "$window_uuid" "$SOURCE_TEXT" "$_name"
    "$dialog" "$window_uuid" omc_window "$_name - Speech"
    clear_run "$1"
}

# --- runs ----------------------------------------------------------------------------------------
# A run lives in its own directory, <spool>/run-<epoch>-<pid>, named by the spool's `current`
# file. Starting a run writes a fresh directory and then repoints `current`, so a poller in the
# middle of reading the previous run's events can never write into the new one.
#
# Files in a run directory:
#   state          running | stopping | done | failed | stopped
#   speech.pid     the speech process
#   events.jsonl   its stdout, one JSON event per line; stderr.log, its stderr
#   events.lines   how many complete event lines the poller has consumed
#   segments.tsv   id <TAB> kind <TAB> text, sorted by id - the transcript's source of truth
#   transcript.txt the rendered transcript; result.json, the finished transcript from speech
#   summary.txt, error.txt, warnings.txt, reflected

current_run_dir() {   # $1 = spool; prints the run directory, empty when there is none
    local _name="$(read_state "$1/current")"
    [ -n "$_name" ] || return 1
    [ -d "$1/$_name" ] || return 1
    printf '%s' "$1/$_name"
}

run_state() {   # $1 = spool
    local _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 0
    read_state "$_run/state"
}

# Returns 0 while the current run is running or stopping.
run_is_active() {   # $1 = spool
    local _state="$(run_state "$1")"
    case "$_state" in running|stopping) return 0 ;; esac
    return 1
}

new_run_dir() {   # $1 = spool; prints the new run directory
    local _now="$(/bin/date +%s)"
    local _name="run-$_now-$$"
    /bin/mkdir -p "$1/$_name"
    local _mkdir_status=$?
    [ "$_mkdir_status" -eq 0 ] || return 1
    printf '%s' "$1/$_name"
}

# Make a run directory current and remove every other one.
activate_run_dir() {   # $1 = spool, $2 = run directory
    local _name="$(/usr/bin/basename "$2")"
    write_state "$1/current" "$_name"
    local _old
    for _old in "$1"/run-*; do
        [ -d "$_old" ] || continue
        [ "$_old" = "$2" ] && continue
        /bin/rm -rf "$_old"
    done
}

clear_run() {   # $1 = spool
    /bin/rm -f "$1/current"
    local _old
    for _old in "$1"/run-*; do
        [ -d "$_old" ] && /bin/rm -rf "$_old"
    done
    printf '' | "$dialog" "$window_uuid" "$TRANSCRIPT_EDITOR" omc_set_value_from_stdin plain
    /bin/rm -f "$1/actions.sig"
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

# --- reading a run's events --------------------------------------------------------------------

# A duration in seconds as "4.4 s" or "2 min 05 s".
format_seconds() {   # $1 = seconds
    /usr/bin/awk -v s="$1" 'BEGIN {
        if (s == "" || s < 0) s = 0
        if (s < 60) printf "%.1f s", s
        else printf "%d min %02d s", int(s / 60), int(s) % 60
    }'
}

# Consume the event lines the poller has not seen yet, and fold their segments into the segment
# table. Returns 0 when the segment table changed.
#
# Only complete lines are consumed. The line speech is in the middle of writing has no newline
# yet; `wc -l` counts newlines, so taking that many lines leaves it for the next tick, and it is
# read whole then. speech.events.jq turns the batch into one record per event.
process_events() {   # $1 = spool
    local _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 1
    [ -f "$_run/events.jsonl" ] || return 1
    local _consumed="$(read_state "$_run/events.lines")"
    case "$_consumed" in ''|*[!0-9]*) _consumed=0 ;; esac

    /usr/bin/tail -n "+$((_consumed + 1))" "$_run/events.jsonl" > "$_run/events.new" 2>/dev/null
    local _complete="$(/usr/bin/wc -l < "$_run/events.new" | /usr/bin/tr -d ' ')"
    case "$_complete" in ''|*[!0-9]*) _complete=0 ;; esac
    if [ "$_complete" -eq 0 ]; then
        /bin/rm -f "$_run/events.new"
        return 1
    fi
    /usr/bin/head -n "$_complete" "$_run/events.new" > "$_run/events.batch"
    /bin/rm -f "$_run/events.new"

    "$jq" -r -f "$SCRIPTS_DIR/speech.events.jq" "$_run/events.batch" > "$_run/events.records" 2> "$_run/events.err"
    local _jq_status=$?
    if [ "$_jq_status" -ne 0 ]; then
        # One unreadable line fails the whole batch. Go line by line instead, so it costs only
        # itself, and keep the line for whoever has to find out why.
        : > "$_run/events.records"
        local _raw
        while IFS= read -r _raw; do
            printf '%s\n' "$_raw" | "$jq" -r -f "$SCRIPTS_DIR/speech.events.jq" >> "$_run/events.records" 2>/dev/null
            local _line_status=$?
            [ "$_line_status" -eq 0 ] || printf '%s\n' "$_raw" >> "$_run/events.unreadable"
        done < "$_run/events.batch"
    fi

    local _name="$(/usr/bin/basename "$(read_state "$1/source.path")")"
    local _status=""
    : > "$_run/segments.new"
    local _type _id _text _percent _phase _message _segments _audio _wall _rtfx
    while IFS="$US" read -r _type _id _text _percent _phase _message _segments _audio _wall _rtfx; do
        case "$_type" in
            segment.partial) printf '%s\tpartial\t%s\n' "$_id" "$_text" >> "$_run/segments.new" ;;
            segment.final)   printf '%s\tfinal\t%s\n' "$_id" "$_text" >> "$_run/segments.new" ;;
            segment.refined) printf '%s\trefined\t%s\n' "$_id" "$_text" >> "$_run/segments.new" ;;
            progress)
                _status="Transcribing $_name... ${_percent:-0}%"
                ;;
            model.progress)
                case "$_phase" in
                    downloading) _status="Downloading the model... ${_percent:-0}%" ;;
                    compiling)   _status="Preparing the model (the first run of a model is the slow one)..." ;;
                    installing)  _status="Installing the model... ${_percent:-0}%" ;;
                    *)           _status="Checking the model..." ;;
                esac
                ;;
            engine.ready)
                _status="Transcribing $_name..."
                ;;
            warning)
                printf '%s\n' "$_message" >> "$_run/warnings.txt"
                ;;
            error)
                [ -s "$_run/error.txt" ] || write_state "$_run/error.txt" "$_message"
                write_state "$_run/state" failed
                ;;
            done)
                write_state "$_run/summary.txt" "$_segments segments, $(format_seconds "$_audio") of audio in $(format_seconds "$_wall") (${_rtfx}x real time)"
                # A stop that arrives after the work finished still leaves a finished transcript.
                [ -s "$_run/error.txt" ] || write_state "$_run/state" done
                ;;
        esac
    done < "$_run/events.records"
    /bin/rm -f "$_run/events.batch" "$_run/events.records"
    write_state "$_run/events.lines" "$((_consumed + _complete))"

    # Only the last status of the batch is worth showing.
    [ -n "$_status" ] && set_status "$_status"

    if [ ! -s "$_run/segments.new" ]; then
        /bin/rm -f "$_run/segments.new"
        return 1
    fi
    # The last row seen for an id wins, so a final replaces its partial and a refinement replaces
    # its final, whether they arrived in this batch or an earlier one.
    /bin/cat "$_run/segments.tsv" "$_run/segments.new" 2>/dev/null \
        | /usr/bin/awk -F'\t' '$1 ~ /^[0-9]+$/ { row[$1] = $0 } END { for (id in row) print row[id] }' \
        | LC_ALL=C /usr/bin/sort -t "$TAB" -k1,1n > "$_run/segments.tsv.tmp"
    /bin/mv -f "$_run/segments.tsv.tmp" "$_run/segments.tsv"
    /bin/rm -f "$_run/segments.new"
    return 0
}

# Rebuild the transcript from the segment table and push it into the window: one segment per
# line, in id order, with the leading space some engines put before a segment trimmed.
render_transcript() {   # $1 = spool
    local _run="$(current_run_dir "$1")"
    [ -n "$_run" ] || return 0
    /usr/bin/awk -F'\t' '{ text = $3; sub(/^ +/, "", text); sub(/ +$/, "", text); if (text != "") print text }' \
        "$_run/segments.tsv" > "$_run/transcript.txt" 2>/dev/null
    /bin/cat "$_run/transcript.txt" | "$dialog" "$window_uuid" "$TRANSCRIPT_EDITOR" omc_set_value_from_stdin plain
}

# Settle a run whose process has exited: read whatever it wrote last, then decide how it ended.
# A process that exited without a `done` or an `error` event was stopped (if Stop was pressed)
# or died, and its stderr is the only account of why.
finish_if_exited() {   # $1 = spool
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

# Say once how a run ended.
reflect_run_end() {   # $1 = spool
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

# --- enabling controls -------------------------------------------------------------------------
# One function decides every control's state from the spool, so a handler and the poller cannot
# disagree. The poller calls it every tick; the signature file keeps a tick that changes nothing
# from writing to the window, and a handler that changes state removes the signature.

refresh_actions() {   # $1 = spool
    local _spool="$1"
    local _source="$(read_state "$_spool/source.path")"
    local _model="$(read_state "$_spool/model.id")"
    local _models_ready=0
    [ -f "$_spool/models.tsv" ] && _models_ready=1
    local _run="$(current_run_dir "$_spool")"
    local _state=""
    [ -n "$_run" ] && _state="$(read_state "$_run/state")"

    local _active=0
    case "$_state" in running|stopping) _active=1 ;; esac
    local _can_transcribe=0
    [ "$_active" = 0 ] && [ -n "$_source" ] && [ -f "$_source" ] && [ -n "$_model" ] && _can_transcribe=1
    local _can_stop=0
    [ "$_state" = running ] && _can_stop=1
    local _can_export=0
    [ "$_active" = 0 ] && [ -n "$_run" ] && [ -s "$_run/result.json" ] && _can_export=1
    local _can_copy=0
    [ "$_active" = 0 ] && [ -n "$_run" ] && [ -s "$_run/transcript.txt" ] && _can_copy=1
    local _can_choose=1
    [ "$_active" = 1 ] && _can_choose=0
    local _can_pick=0
    [ "$_active" = 0 ] && [ "$_models_ready" = 1 ] && [ -n "$_model" ] && _can_pick=1

    local _signature="$_can_transcribe$_can_stop$_can_export$_can_copy$_can_choose$_can_pick|$_models_ready|$_state|$_source|$_model"
    [ "$_signature" = "$(read_state "$_spool/actions.sig")" ] && return 0
    write_state "$_spool/actions.sig" "$_signature"

    set_enabled "$TRANSCRIBE_BTN" "$_can_transcribe"
    set_enabled "$STOP_BTN" "$_can_stop"
    set_enabled "$EXPORT_MENU" "$_can_export"
    set_enabled "$COPY_BTN" "$_can_copy"
    set_enabled "$CHOOSE_BTN" "$_can_choose"
    set_enabled "$MODEL_PICKER" "$_can_pick"
    set_enabled "$LANGUAGE_PICKER" "$_can_pick"

    # With no run to report on, the status line says what the window is waiting for.
    [ -z "$_run" ] || return 0
    [ "$_models_ready" = 1 ] || return 0
    if [ -z "$_model" ]; then
        set_status "No speech model can run on this Mac yet."
    elif [ -z "$_source" ]; then
        set_status "Choose or drop a recording to transcribe."
    else
        local _label="$(tsv_field "$_spool/models.tsv" "$_model" 2)"
        set_status "Ready to transcribe $(/usr/bin/basename "$_source") with $_label."
    fi
}

# --- export ------------------------------------------------------------------------------------

# Convert the finished transcript to a format with `speech export`, to the path the Save panel
# returned. The extension is added when the name typed has none of its own.
export_transcript() {   # $1 = format (txt, srt, vtt, json)
    local _dest="${OMC_DLG_SAVE_AS_PATH:-}"
    [ -n "$_dest" ] || return 0
    local _spool="$(spool_dir_for "$window_uuid")"
    local _run="$(current_run_dir "$_spool")"
    if [ -z "$_run" ] || [ ! -s "$_run/result.json" ]; then
        present_alert "Nothing to export" "Transcribe a recording first."
        return 0
    fi
    case "$_dest" in
        *."$1") ;;
        *) _dest="$_dest.$1" ;;
    esac
    "$SPEECH_BIN" export "$_run/result.json" --format "$1" --output "$_dest" > /dev/null 2> "$_run/export.err"
    local _export_status=$?
    if [ "$_export_status" -ne 0 ]; then
        present_alert "Could not export the transcript" "$(/usr/bin/head -3 "$_run/export.err")"
        return 0
    fi
    set_status "Exported to $(/usr/bin/basename "$_dest")."
}
