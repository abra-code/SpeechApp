# lib.speech.models.sh - the Models window: its cards, downloads and deletion. Sourced by the
# speech.models.* handlers, the Models window's poller (speech.models.poll.sh) and the download
# worker (speech.download.worker.sh). POSIX /bin/sh (macOS bash 3.2): validate with `sh -n`.
#
# State:
#   Sessions/<window>/            a Models window's spool, removed when the window closes
#     catalog.json, catalog.err   the last `speech --json catalog` and its stderr
#     cards.list, cards.json      the rows and their cards (speech.models.jq)
#     cards.ids                   the card ids inserted into the window, for removing them again
#     render.sig                  the md5 of the cards.json the window shows
#     card.<row>.sig              what a download last put on a card, so a tick that changes
#                                 nothing writes nothing
#     models.seen, loaded         the models.changed value the cards were read at; the first read
#     pending.delete              the model a delete alert asks about
#   Downloads/<md5 of id>/        one model's download, shared by every window
#     id, worker.pid, speech.pid, events.jsonl, stderr.log
#     state, message              running | failed, and speech's reason. A download that finished
#                                 or stopped removes its directory: the catalog then tells the rest.
#   Adding/                       the model being added, or the last one; see "adding a model"
#   Sessions/<window>/add.shown   what the window's status line last said about an add
#   Sessions/<window>/add.opened  the add that had already ended when the window opened

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

[ -n "${__SPEECH_MODELS_LIB:-}" ] && return 0
__SPEECH_MODELS_LIB=1

set_models_status() { "$dialog" "$window_uuid" "$MODELS_STATUS" "$1"; }   # $1 = text

set_shown() {   # $1 = view id, $2 = 1 to show, anything else to hide
    if [ "$2" = 1 ]; then
        "$dialog" "$window_uuid" "$1" omc_show
    else
        "$dialog" "$window_uuid" "$1" omc_hide
    fi
}

# --- cards and rows ------------------------------------------------------------------------------
# A card's id is MODEL_CARD_BASE + row * 10, the row counted from 1 in cards.list, and its parts
# sit at the CARD_* offsets. A button handler finds its row from the id that triggered it.

card_base() { printf '%s' "$((MODEL_CARD_BASE + $1 * 10))"; }   # $1 = row

card_row_of() {   # $1 = view id; prints the row, nothing when the id is not a card's
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -gt "$MODEL_CARD_BASE" ] && [ "$1" -lt "$MODEL_INFO_TEXT" ] || return 1
    printf '%s' "$((($1 - MODEL_CARD_BASE) / 10))"
}

card_field() {   # $1 = spool, $2 = row, $3 = field number (speech.models.jq)
    /usr/bin/awk -F"$US" -v row="$2" -v col="$3" 'NR == row { print $col; exit }' "$1/cards.list" 2>/dev/null
}

row_of_id() {   # $1 = spool, $2 = model id
    /usr/bin/awk -F"$US" -v id="$2" '$1 == id { print NR; exit }' "$1/cards.list" 2>/dev/null
}

# Read the catalog into cards.list and cards.json. Returns non-zero, with the reason in
# catalog.err, when the catalog cannot be read.
load_cards() {   # $1 = spool
    "$SPEECH_BIN" --json catalog > "$1/catalog.json" 2> "$1/catalog.err"
    local _catalog_status=$?
    [ "$_catalog_status" -eq 0 ] || return 1
    "$jq" -r --argjson base "$MODEL_CARD_BASE" --argjson builtin "$MODELS_BUILTIN_LIST" \
        --argjson installed "$MODELS_INSTALLED_LIST" --argjson available "$MODELS_AVAILABLE_LIST" \
        -f "$SCRIPTS_DIR/speech.models.jq" "$1/catalog.json" > "$1/cards.out.tmp" 2>> "$1/catalog.err"
    local _jq_status=$?
    if [ "$_jq_status" -ne 0 ]; then
        /bin/rm -f "$1/cards.out.tmp"
        return 1
    fi
    /usr/bin/awk -v prefix="L$US" 'index($0, prefix) == 1 { print substr($0, 3) }' "$1/cards.out.tmp" > "$1/cards.list.tmp"
    /usr/bin/awk -v prefix="C$US" 'index($0, prefix) == 1 { print substr($0, 3) }' "$1/cards.out.tmp" > "$1/cards.json.tmp"
    /bin/mv -f "$1/cards.list.tmp" "$1/cards.list"
    /bin/mv -f "$1/cards.json.tmp" "$1/cards.json"
    /bin/rm -f "$1/cards.out.tmp"
}

# Replace the window's cards with cards.json, unless that is what the window already shows.
# Showing a section only when it has a card keeps an empty heading out of the window.
render_cards() {   # $1 = spool
    local _sig="$(/sbin/md5 -q "$1/cards.json" 2>/dev/null)"
    [ -n "$_sig" ] || return 1
    local _old="$(read_state "$1/render.sig")"
    [ "$_sig" = "$_old" ] && return 0

    local _card
    if [ -f "$1/cards.ids" ]; then
        while IFS= read -r _card; do
            case "$_card" in ''|*[!0-9]*) continue ;; esac
            "$dialog" "$window_uuid" "$_card" omc_remove_element
        done < "$1/cards.ids"
    fi
    /bin/rm -f "$1/cards.ids" "$1"/card.*.sig

    local _builtin=0
    local _installed=0
    local _available=0
    local _container _json
    while IFS="$US" read -r _container _card _json; do
        [ -n "$_json" ] || continue
        "$dialog" "$window_uuid" "$_container" omc_insert_element "$_json"
        printf '%s\n' "$_card" >> "$1/cards.ids"
        case "$_container" in
            "$MODELS_BUILTIN_LIST") _builtin=1 ;;
            "$MODELS_INSTALLED_LIST") _installed=1 ;;
            "$MODELS_AVAILABLE_LIST") _available=1 ;;
        esac
    done < "$1/cards.json"
    set_shown "$MODELS_BUILTIN_BOX" "$_builtin"
    set_shown "$MODELS_INSTALLED_BOX" "$_installed"
    set_shown "$MODELS_AVAILABLE_BOX" "$_available"
    write_state "$1/render.sig" "$_sig"
}

push_card() {   # $1 = row, $2 = state text, $3 = download enabled (1/0), $4 = delete enabled (1/0)
    local _base="$(card_base "$1")"
    "$dialog" "$window_uuid" "$((_base + CARD_STATE))" "$2"
    set_enabled "$((_base + CARD_DOWNLOAD))" "$3"
    set_enabled "$((_base + CARD_DELETE))" "$4"
}

# --- downloads -----------------------------------------------------------------------------------

download_dir_for() { printf '%s/%s' "$DOWNLOADS_DIR" "$(item_key "$1")"; }   # $1 = model id

# Returns 0 while the download directory's worker is running, judged by its argv, so a recycled
# pid is never taken for a download in progress.
download_worker_alive() {   # $1 = download dir
    local _pid="$(read_state "$1/worker.pid")"
    case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
    local _id="$(read_state "$1/id")"
    [ -n "$_id" ] || return 1
    local _args="$(/bin/ps -p "$_pid" -o args= 2>/dev/null)"
    case "$_args" in
        "/bin/sh $DOWNLOAD_WORKER_SCRIPT $_id "*) return 0 ;;
    esac
    return 1
}

# Wait for a speech process this shell started, and return its exit status. A signal the caller
# traps interrupts wait before speech has exited, so wait again for speech's own status.
wait_for_speech() {   # $1 = pid
    wait "$1"
    local _status=$?
    local _alive
    while [ "$_status" -gt 128 ]; do
        pid_alive "$1"
        _alive=$?
        [ "$_alive" -eq 0 ] || break
        wait "$1"
        _status=$?
    done
    return "$_status"
}

download_progress_text() {   # $1 = download dir
    /usr/bin/tail -n 40 "$1/events.jsonl" 2>/dev/null \
        | "$jq" -R -r -n --arg want progress -f "$SCRIPTS_DIR/speech.download.jq" 2>/dev/null
}

# Record how a download ended, then tell every window to read the catalog again. A failed download
# keeps its directory, so its card can say why; one that finished or was stopped needs nothing but
# the catalog, which now reports it installed or partly downloaded.
settle_download() {   # $1 = download dir, $2 = speech's exit status
    local _outcome="$("$jq" -R -r -n --arg want outcome -f "$SCRIPTS_DIR/speech.download.jq" "$1/events.jsonl" 2>/dev/null)"
    local _state _message
    case "$_outcome" in
        installed) _state=done ;;
        "error$US"*)
            _state=failed
            _message="${_outcome#error$US}"
            ;;
        *)
            if [ "$2" -eq 0 ]; then
                _state=done
            elif [ "$2" -gt 128 ]; then
                _state=stopped
            else
                _state=failed
                _message="$(/usr/bin/head -1 "$1/stderr.log" 2>/dev/null)"
            fi
            ;;
    esac
    if [ "$_state" = failed ] && [ -z "$_message" ]; then
        _message="speech ended with status $2 and did not say why."
    fi
    write_state "$1/message" "$_message"
    write_state "$1/state" "$_state"
    bump_models_stamp
    [ "$_state" = failed ] || /bin/rm -rf "$1"
}

# Put each download's progress on its card, and a failed download's reason. A download whose
# worker is gone without saying how it ended (it was killed) gives the card back its catalog state,
# and so does one whose directory is gone (it finished or was stopped) when the catalog it brought
# left the card as it was, so render_cards rebuilt nothing.
refresh_download_cards() {   # $1 = spool
    local _dir _sig _text _download _delete
    for _sig in "$1"/card.*.sig; do
        [ -f "$_sig" ] || continue
        local _row="${_sig##*/card.}"
        _row="${_row%.sig}"
        case "$_row" in ''|*[!0-9]*) continue ;; esac
        local _id="$(card_field "$1" "$_row" 1)"
        if [ -n "$_id" ]; then
            local _dl_dir="$(download_dir_for "$_id")"
            [ -f "$_dl_dir/id" ] && continue
            push_card "$_row" "$(card_field "$1" "$_row" 9)" "$(card_field "$1" "$_row" 10)" "$(card_field "$1" "$_row" 11)"
        fi
        /bin/rm -f "$_sig"
    done
    for _dir in "$DOWNLOADS_DIR"/*; do
        [ -f "$_dir/id" ] || continue
        local _id="$(read_state "$_dir/id")"
        local _row="$(row_of_id "$1" "$_id")"
        [ -n "$_row" ] || continue
        download_worker_alive "$_dir"
        local _alive=$?
        local _state="$(read_state "$_dir/state")"
        if [ "$_alive" -eq 0 ]; then
            _text="$(download_progress_text "$_dir")"
            _download=0
            _delete=0
        elif [ "$_state" = failed ]; then
            _text="Download failed: $(read_state "$_dir/message")"
            _download="$(card_field "$1" "$_row" 10)"
            _delete="$(card_field "$1" "$_row" 11)"
        else
            [ -f "$1/card.$_row.sig" ] || continue
            push_card "$_row" "$(card_field "$1" "$_row" 9)" "$(card_field "$1" "$_row" 10)" "$(card_field "$1" "$_row" 11)"
            /bin/rm -f "$1/card.$_row.sig"
            continue
        fi
        local _sig="$_text|$_download|$_delete"
        local _old="$(read_state "$1/card.$_row.sig")"
        [ "$_sig" = "$_old" ] && continue
        push_card "$_row" "$_text" "$_download" "$_delete"
        write_state "$1/card.$_row.sig" "$_sig"
    done
}

# --- adding a model ------------------------------------------------------------------------------
# Add Model... (speech.model.add.json) runs `speech models add` for a Hugging Face repository under
# a worker of its own (speech.add.worker.sh), one add at a time, in ADDING_DIR:
#   repo, quant, token          what was asked for, and a value no other add shares
#   worker.pid, speech.pid, events.jsonl, stderr.log
#   state, message              running | done | failed | stopped; the id added, or speech's reason
#   how                         for a done add: added, downloaded (already listed, speech finished
#                               its download) or listed (already listed and downloaded)
# The directory stays after the add ends, so every open Models window can report how it ended,
# and is replaced by the next add. Only transcribe.cpp (ggml) models can be added: it is the one
# engine that runs a model from its file alone.

# The repository in what was typed: owner/name, or a huggingface.co address of the repository or
# of a page inside it. Prints nothing, and returns non-zero, when there is none.
repo_from_input() {   # $1 = the Repository field
    local _text="$(printf '%s' "$1" | /usr/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    local _address=0
    case "$_text" in http://*|https://*) _address=1 ;; esac
    _text="${_text#https://}"
    _text="${_text#http://}"
    _text="${_text#www.}"
    case "$_text" in
        huggingface.co/*) _text="${_text#huggingface.co/}" ;;
        hf.co/*) _text="${_text#hf.co/}" ;;
        *) [ "$_address" -eq 0 ] || return 1 ;;
    esac
    _text="${_text%%[?#]*}"
    case "$_text" in */*) ;; *) return 1 ;; esac
    local _owner="${_text%%/*}"
    local _rest="${_text#*/}"
    local _name="${_rest%%/*}"
    _name="${_name%.git}"
    # An owner starting with a dash would reach speech as an option, not a repository.
    case "$_owner" in ''|.|..|-*|*[!A-Za-z0-9._-]*) return 1 ;; esac
    case "$_name" in ''|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac
    printf '%s/%s' "$_owner" "$_name"
}

# The Quantization field, trimmed. Empty is fine: speech then takes the only file, or the Q8_0.
# Returns non-zero when it holds anything but letters, digits and underscores.
quant_from_input() {   # $1 = the Quantization field
    local _text="$(printf '%s' "$1" | /usr/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$_text" in *[!A-Za-z0-9_]*) return 1 ;; esac
    printf '%s' "$_text"
}

set_add_error() { "$dialog" "$window_uuid" "$MODEL_ADD_ERROR" "$1"; }   # $1 = text

# Returns 0 while the add's worker is running, judged by its argv, as for a download.
add_worker_alive() {
    local _pid="$(read_state "$ADDING_DIR/worker.pid")"
    case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
    local _repo="$(read_state "$ADDING_DIR/repo")"
    [ -n "$_repo" ] || return 1
    local _args="$(/bin/ps -p "$_pid" -o args= 2>/dev/null)"
    case "$_args" in
        "/bin/sh $ADD_WORKER_SCRIPT $_repo "*) return 0 ;;
    esac
    return 1
}

# Why an add cannot start now; prints nothing when it can.
add_refusal() {
    add_worker_alive
    local _alive=$?
    [ "$_alive" -eq 0 ] || return 0
    printf 'Speech is still adding %s. Wait for it to finish, then add another.' "$(read_state "$ADDING_DIR/repo")"
}

# Record how an add ended. A model that was added changes the catalog, so every window is told
# before the state is written: a window that sees the add done has the new card to name.
settle_add() {   # $1 = add dir, $2 = speech's exit status
    local _outcome="$("$jq" -R -r -n --arg want added -f "$SCRIPTS_DIR/speech.download.jq" "$1/events.jsonl" 2>/dev/null)"
    local _state _message
    local _how=listed
    case "$_outcome" in
        "added$US"*)
            _state=done
            _how=added
            _message="${_outcome#added$US}"
            ;;
        "installed$US"*)
            _state=done
            _how=downloaded
            _message="${_outcome#installed$US}"
            ;;
        "error$US"*)
            _state=failed
            _message="${_outcome#error$US}"
            ;;
        *)
            if [ "$2" -eq 0 ]; then
                _state=done
            elif [ "$2" -gt 128 ]; then
                _state=stopped
            else
                _state=failed
                _message="$(/usr/bin/head -1 "$1/stderr.log" 2>/dev/null)"
            fi
            ;;
    esac
    if [ "$_state" = failed ] && [ -z "$_message" ]; then
        _message="speech ended with status $2 and did not say why."
    fi
    [ "$_state" = done ] && bump_models_stamp
    write_state "$1/how" "$_how"
    write_state "$1/message" "$_message"
    write_state "$1/state" "$_state"
}

# Put the add on the window's status line - its progress, or how it ended - and offer Add Model...
# only when no add is running. An add that ended before the window opened is not reported, and
# one whose worker is gone without saying how it ended (the app was killed) clears what the line
# said about it.
refresh_add_status() {   # $1 = spool
    local _token="$(read_state "$ADDING_DIR/token")"
    local _repo="$(read_state "$ADDING_DIR/repo")"
    local _state="$(read_state "$ADDING_DIR/state")"
    local _text=""
    local _enabled=1
    local _show=1
    local _alive
    case "$_state" in
        running)
            add_worker_alive
            _alive=$?
            if [ "$_alive" -eq 0 ]; then
                _text="Adding $_repo: $(/usr/bin/tail -n 40 "$ADDING_DIR/events.jsonl" 2>/dev/null \
                    | "$jq" -R -r -n --arg want adding -f "$SCRIPTS_DIR/speech.download.jq" 2>/dev/null)"
                _enabled=0
            else
                _state=stopped
                _show=0
            fi
            ;;
        done)
            local _id="$(read_state "$ADDING_DIR/message")"
            local _how="$(read_state "$ADDING_DIR/how")"
            local _row=""
            [ -n "$_id" ] && _row="$(row_of_id "$1" "$_id")"
            local _label=""
            [ -n "$_row" ] && _label="$(card_field "$1" "$_row" 3)"
            case "$_how" in
                added) _text="Added ${_label:-$_id} from $_repo. It is listed under Downloaded." ;;
                downloaded) _text="${_label:-$_id} was already in the model list. Speech finished downloading it." ;;
                *) _text="$_repo is already in the model list." ;;
            esac
            ;;
        failed)
            _text="Could not add $_repo: $(read_state "$ADDING_DIR/message")"
            ;;
        *)
            _show=0
            ;;
    esac
    if [ "$_state" != running ] && [ -n "$_token" ] && [ "$_token" = "$(read_state "$1/add.opened")" ]; then
        _show=0
    fi
    local _sig="$_token|$_state|$_show|$_text"
    local _old="$(read_state "$1/add.shown")"
    [ "$_sig" = "$_old" ] && return 0
    write_state "$1/add.shown" "$_sig"
    set_enabled "$MODELS_ADD_BTN" "$_enabled"
    if [ "$_show" = 1 ]; then
        set_models_status "$_text"
    else
        case "$_old" in "$_token|running|1|"*) set_models_status "" ;; esac
    fi
}

# --- deletion ------------------------------------------------------------------------------------

# Returns 0 while a window is transcribing with the model: a batch using it, or a run of it in
# progress. Deleting files from under a running model is not something to find out about later.
model_in_use() {   # $1 = model id
    local _pane
    for _pane in "$SESSIONS_DIR"/*/live "$SESSIONS_DIR"/*/recordings; do
        [ -d "$_pane" ] || continue
        local _batch="$(read_state "$_pane/batch")"
        local _batch_model="$(read_state "$_pane/batch.model")"
        [ -n "$_batch" ] && [ "$_batch_model" = "$1" ] && return 0
        local _run="$(current_run_dir "$_pane")"
        [ -n "$_run" ] || continue
        local _state="$(read_state "$_run/state")"
        case "$_state" in running|stopping) ;; *) continue ;; esac
        local _model="$(read_state "$_run/model")"
        [ "$_model" = "$1" ] && return 0
    done
    return 1
}

# Why a model cannot be deleted now; prints nothing when it can.
delete_refusal() {   # $1 = spool, $2 = row
    local _id="$(card_field "$1" "$2" 1)"
    local _label="$(card_field "$1" "$2" 3)"
    download_worker_alive "$(download_dir_for "$_id")"
    local _downloading=$?
    if [ "$_downloading" -eq 0 ]; then
        printf '%s is downloading. Wait for the download to end, then delete it.' "$_label"
        return 0
    fi
    model_in_use "$_id"
    local _in_use=$?
    if [ "$_in_use" -eq 0 ]; then
        printf '%s is transcribing in a Speech window. Stop it there, then delete it.' "$_label"
    fi
}

# --- the information sheet -----------------------------------------------------------------------

# A model's information as Markdown: what the catalog says about the row, where its files are, and
# the model family's page from Resources/Reference/models, which holds the reference measurements.
model_info_markdown() {   # $1 = spool, $2 = row
    local _id="$(card_field "$1" "$2" 1)"
    local _label="$(card_field "$1" "$2" 3)"
    local _engine="$(card_field "$1" "$2" 4)"
    local _family="$(card_field "$1" "$2" 5)"
    local _role="$(card_field "$1" "$2" 6)"
    local _state="$(card_field "$1" "$2" 7)"
    local _state_text="$(card_field "$1" "$2" 9)"
    local _source="$(card_field "$1" "$2" 13)"
    local _precision="$(card_field "$1" "$2" 14)"
    local _params="$(card_field "$1" "$2" 15)"
    local _languages="$(card_field "$1" "$2" 16)"
    local _modes="$(card_field "$1" "$2" 17)"

    local _engine_name _use
    case "$_engine" in
        apple) _engine_name="Apple Speech, part of macOS" ;;
        fluid) _engine_name="FluidAudio (Core ML)" ;;
        ggml)  _engine_name="transcribe.cpp (ggml)" ;;
        mlx)   _engine_name="MLX" ;;
        *)     _engine_name="$_engine" ;;
    esac
    if [ "$_role" = helper ]; then
        _use="Used by other models, not for transcribing on its own"
    else
        case ",$_modes," in
            *,live,*) _use="Recordings and live" ;;
            *) _use="Recordings only" ;;
        esac
    fi

    printf '### %s\n\n' "$_label"
    printf -- '- **Id:** `%s`\n' "$_id"
    printf -- '- **Engine:** %s\n' "$_engine_name"
    printf -- '- **Status:** %s\n' "$_state_text"
    printf -- '- **Transcribes:** %s\n' "$_use"
    [ -n "$_precision" ] && printf -- '- **Precision:** %s\n' "$_precision"
    [ -n "$_params" ] && printf -- '- **Parameters:** %s million\n' "$_params"
    if [ -n "$_languages" ]; then
        local _names=""
        local _tag
        for _tag in $(printf '%s' "$_languages" | /usr/bin/tr ',' ' '); do
            if [ -z "$_names" ]; then
                _names="$(language_display_name "$_tag")"
            else
                _names="$_names, $(language_display_name "$_tag")"
            fi
        done
        printf -- '- **Languages:** %s\n' "$_names"
    fi
    [ -n "$_source" ] && printf -- '- **Source:** [%s](https://huggingface.co/%s)\n' "$_source" "$_source"
    if [ "$_state" != system_managed ]; then
        local _path="$("$SPEECH_BIN" --json models status "$_id" 2>/dev/null | "$jq" -r 'select(.type == "model.entry") | .path // empty' 2>/dev/null)"
        if [ -n "$_path" ] && [ "$_state" = installed ]; then
            printf -- '- **Location:** %s\n' "$_path"
        elif [ -n "$_path" ]; then
            printf -- '- **Downloads to:** %s\n' "$_path"
        fi
    fi

    case "$_family" in
        ''|*[!a-z0-9.-]*) return 0 ;;
    esac
    local _page="$RESOURCES_DIR/Reference/models/$_family.md"
    [ -f "$_page" ] || return 0
    printf '\n---\n\n'
    /bin/cat "$_page"
}

# --- the poller's tick ---------------------------------------------------------------------------

poll_models_window() {   # $1 = spool
    local _stamp="$(models_stamp)"
    local _seen="$(read_state "$1/models.seen")"
    if [ ! -f "$1/cards.list" ] || [ "$_stamp" != "$_seen" ]; then
        load_cards "$1"
        local _load_status=$?
        if [ "$_load_status" -ne 0 ]; then
            local _reason="$(/usr/bin/head -3 "$1/catalog.err" 2>/dev/null)"
            set_models_status "Could not read the model catalog: ${_reason:-speech did not answer}"
            /bin/rm -f "$1/loaded"
            return 1
        fi
        write_state "$1/models.seen" "$_stamp"
        if [ ! -f "$1/loaded" ]; then
            set_models_status ""
            : > "$1/loaded"
        fi
    fi
    render_cards "$1"
    refresh_download_cards "$1"
    refresh_add_status "$1"
}
