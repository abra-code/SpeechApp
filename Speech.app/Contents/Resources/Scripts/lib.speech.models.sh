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

# Where speech keeps a model's files, or downloads them to: a folder. Prints nothing when speech
# does not say.
model_path() {   # $1 = model id
    "$SPEECH_BIN" --json models status "$1" 2>/dev/null \
        | "$jq" -r 'select(.type == "model.entry") | .path // empty' 2>/dev/null
}

# The sheet's Markdown reader takes *, _, [ and ` as syntax wherever they fall, including inside a
# word: a label like "Whisper large-v3-turbo (Q4_K_M)" comes out as "Q4KM" with an italic K. This
# escapes them for a value that belongs in the prose. A value that is a literal - the id, the
# precision, a path - goes in a code span instead, which reads better and needs no escaping. The
# tilde is in the list because a pair of them is this reader's strikethrough.
md_escape() {   # $1 = text
    local _out="${1//\\/\\\\}"
    _out="${_out//\*/\\*}"
    _out="${_out//_/\\_}"
    _out="${_out//\[/\\[}"
    _out="${_out//\]/\\]}"
    _out="${_out//\`/\\\`}"
    _out="${_out//\~/\\~}"
    printf '%s' "$_out"
}

# A model's information as Markdown: what the catalog says about the row, where its files are, and
# the model family's page from Resources/Reference/models, which holds the reference measurements.
model_info_markdown() {   # $1 = spool, $2 = row
    local _id="$(card_field "$1" "$2" 1)"
    local _label="$(card_field "$1" "$2" 3)"
    local _engine="$(card_field "$1" "$2" 4)"
    local _family="$(card_field "$1" "$2" 5)"
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
    case ",$_modes," in
        *,live,*) _use="Recordings and live" ;;
        *) _use="Recordings only" ;;
    esac

    printf '### %s\n\n' "$(md_escape "$_label")"
    printf -- '- **Id:** `%s`\n' "$_id"
    printf -- '- **Engine:** %s\n' "$(md_escape "$_engine_name")"
    printf -- '- **Status:** %s\n' "$(md_escape "$_state_text")"
    printf -- '- **Transcribes:** %s\n' "$_use"
    # A code span, as the Id is: a precision like q4_k_m is a literal, and Markdown would otherwise
    # read the pair of underscores as emphasis and draw "q4km" with an italic k.
    [ -n "$_precision" ] && printf -- '- **Precision:** `%s`\n' "$_precision"
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
    # The link's text is prose, the URL is not: a repository name can carry an underscore.
    [ -n "$_source" ] && printf -- '- **Source:** [%s](https://huggingface.co/%s)\n' "$(md_escape "$_source")" "$_source"
    if [ "$_state" != system_managed ]; then
        local _path="$(model_path "$_id")"
        # Also a code span: a folder name carries the model id, which can hold the same underscores.
        if [ -n "$_path" ] && [ "$_state" = installed ]; then
            printf -- '- **Location:** `%s`\n' "$_path"
        elif [ -n "$_path" ]; then
            printf -- '- **Downloads to:** `%s`\n' "$_path"
        fi
    fi

    # A page for this exact row when there is one, otherwise the family's. The
    # two Apple engines share a family but differ enough in languages and
    # accuracy to be described separately. A variant id carries '@' and fails
    # the name test, so those fall through to the family page as before.
    local _page=""
    case "$_id" in
        ''|*[!a-z0-9.-]*) ;;
        *) [ -f "$RESOURCES_DIR/Reference/models/$_id.md" ] \
               && _page="$RESOURCES_DIR/Reference/models/$_id.md" ;;
    esac
    if [ -z "$_page" ]; then
        case "$_family" in
            ''|*[!a-z0-9.-]*) return 0 ;;
        esac
        _page="$RESOURCES_DIR/Reference/models/$_family.md"
    fi
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
    refresh_suggestion "$1"
}

# --- best for a language -------------------------------------------------------------------------
# The box above the list answers one question: which model should I use for this language? The
# Benchmarks tab holds the whole ranking, which is several axes wide; this is two lines for a quick
# decision, and it only ever repeats a measurement. speech.suggest.awk makes the picks and its
# header states the rules; everything here is the language list, the wording and the state.
#
# State in the window's spool, under suggest/:
#   models.tsv        every transcriber row of the catalog (speech.suggest.jq)
#   languages.tsv     the picker's options in order: tag <TAB> display name
#   language.names    the display names alone, in the same order, for the picker
#   language.tag      the language the box is showing
#   picks, picks.sig  the last picks and the inputs they were made from, so a tick that changes
#                     nothing pushes nothing
#   picker_quiet      the quiet window (quiet_begin), this picker's alone

suggest_dir() { printf '%s/suggest' "$1"; }   # $1 = spool

# The catalog as speech.suggest.awk wants it, including rows not downloaded yet: a suggestion may
# name a model worth having, and its size is what the user would be agreeing to.
load_suggest_models() {   # $1 = spool
    local _dir="$(suggest_dir "$1")"
    /bin/mkdir -p "$_dir"
    [ -f "$1/catalog.json" ] || return 1
    "$jq" -r -f "$SCRIPTS_DIR/speech.suggest.jq" "$1/catalog.json" > "$_dir/models.tmp" 2>/dev/null
    local _status=$?
    if [ "$_status" -ne 0 ] || [ ! -s "$_dir/models.tmp" ]; then
        /bin/rm -f "$_dir/models.tmp"
        return 1
    fi
    # Only replace the file when its content changed: render_suggestion signs its inputs by
    # modification time, and a rewrite every tick would make every tick look like new evidence.
    /usr/bin/cmp -s "$_dir/models.tmp" "$_dir/models.tsv"
    local _same=$?
    if [ "$_same" -eq 0 ]; then
        /bin/rm -f "$_dir/models.tmp"
        return 0
    fi
    /bin/mv -f "$_dir/models.tmp" "$_dir/models.tsv" || return 1
    # The content changed, whatever the clock says: a second rewrite of the same size within
    # one second would leave the modification time and size alone.
    /bin/rm -f "$_dir/picks.sig"
}

# The measurement files, with an absent one named as /dev/null so awk still reads a role for it.
suggest_input() {   # $1 = results | reference | live
    local _path
    case "$1" in
        results) _path="$RESULTS_FILE" ;;
        reference) _path="$REFERENCE_MEASUREMENTS" ;;
        live) _path="$REFERENCE_LIVE_MEASUREMENTS" ;;
    esac
    if [ -f "$_path" ]; then printf '%s' "$_path"; else printf '/dev/null'; fi
}

# The measurement files as a signature: modification time and size of each one that exists. An
# absent file is a fixed mark, never a stat of /dev/null, whose modification time is the last
# write to it by anything on the Mac and so changes every second.
suggest_inputs_sig() {
    local _role _path
    for _role in results reference live; do
        _path="$(suggest_input "$_role")"
        if [ "$_path" = /dev/null ]; then
            printf '%s:- ' "$_role"
        else
            printf '%s:%s ' "$_role" "$(/usr/bin/stat -f '%m/%z' "$_path" 2>/dev/null)"
        fi
    done
}

# The languages the picker offers: the ones something has been measured in. Not every language the
# catalog claims - 96 of the 102 corpora have no measurement at all, and a menu whose entries can
# only answer "not measured" is a worse menu. This Mac's own results are read too, so measuring a
# new language in the Benchmarks tab adds it here.
measured_languages() {
    /usr/bin/awk -F'\t' '
        /^#/ { next }
        $1 == "model" {
            language_column = 0
            status_column = 0
            for (i = 1; i <= NF; i++) {
                if ($i == "language") language_column = i
                if ($i == "status") status_column = i
            }
            next
        }
        # A failed run of this Mac is not a measurement (speech.suggest.awk skips it too).
        status_column > 0 && $status_column != "ok" { next }
        language_column > 0 && $language_column != "" && $language_column != "-" {
            tag = $language_column
            cut = index(tag, "-")
            if (cut > 0) tag = substr(tag, 1, cut - 1)
            if (tag != "" && !(tag in seen)) { seen[tag] = 1; print tag }
        }
    ' "$(suggest_input results)" "$(suggest_input reference)" "$(suggest_input live)"
}

# Fill the picker: English first, which the owner asked for as the default and which has the most
# measured rows, then the rest by name. Returns non-zero when nothing has been measured at all.
populate_suggest_languages() {   # $1 = spool
    local _dir="$(suggest_dir "$1")"
    /bin/mkdir -p "$_dir"
    local _tag
    : > "$_dir/languages.unsorted"
    measured_languages | while IFS= read -r _tag; do
        [ -n "$_tag" ] || continue
        printf '%s\t%s\n' "$_tag" "$(language_display_name "$_tag")" >> "$_dir/languages.unsorted"
    done
    if [ ! -s "$_dir/languages.unsorted" ]; then
        /bin/rm -f "$_dir/languages.unsorted"
        return 1
    fi
    : > "$_dir/languages.tsv.tmp"
    /usr/bin/awk -F'\t' '$1 == "en"' "$_dir/languages.unsorted" >> "$_dir/languages.tsv.tmp"
    /usr/bin/awk -F'\t' '$1 != "en"' "$_dir/languages.unsorted" \
        | LC_ALL=C /usr/bin/sort -t "$TAB" -k2,2f >> "$_dir/languages.tsv.tmp"
    /bin/mv -f "$_dir/languages.tsv.tmp" "$_dir/languages.tsv"
    /bin/rm -f "$_dir/languages.unsorted"
    /usr/bin/awk -F'\t' '{ print $2 }' "$_dir/languages.tsv" > "$_dir/language.names"

    local _options
    _options="$("$jq" -R -s -c 'split("\n") | map(select(length > 0))' < "$_dir/language.names" 2>/dev/null)"
    [ -n "$_options" ] || return 1
    quiet_begin "$_dir"
    "$dialog" "$window_uuid" "$MODELS_BEST_LANG" omc_set_property "options" "$_options"

    # The remembered language when the picker still offers it, English otherwise.
    local _want="$(read_state "$_dir/language.tag")"
    [ -n "$_want" ] || _want="$(setting_get models.best.language)"
    local _position="$(/usr/bin/awk -F'\t' -v want="$_want" '$1 == want { print NR; exit }' "$_dir/languages.tsv")"
    if [ -z "$_position" ]; then
        _position="$(/usr/bin/awk -F'\t' '$1 == "en" { print NR; exit }' "$_dir/languages.tsv")"
        [ -n "$_position" ] || _position=1
        _want="$(/usr/bin/awk -F'\t' -v line="$_position" 'NR == line { print $1; exit }' "$_dir/languages.tsv")"
    fi
    write_state "$_dir/language.tag" "$_want"
    "$dialog" "$window_uuid" "$MODELS_BEST_LANG" "$_position"
}

# One pick as a phrase: the model, its error rate, and the figure that matters for the mode -
# throughput for a recording, the wait for the first text when speaking.
suggest_phrase() {   # $1 = mode, $2 = name, $3 = metric, $4 = figure, $5 = second, $6 = state, $7 = wait
    local _errors="word errors"
    [ "$3" = cer ] && _errors="character errors"
    printf '%s - %s%% %s' "$2" "$4" "$_errors"
    if [ -n "$5" ]; then
        case "$1" in
            recordings) printf ', %sx real time' "$5" ;;
            # A row that emits partials shows text while you speak; one that does not has nothing
            # to show until a sentence closes, and its figure is how far behind that text arrives.
            live)
                if [ "$7" = final ]; then
                    printf ', whole sentences %s s behind you' "$5"
                else
                    printf ', first text after %s s' "$5"
                fi
                ;;
        esac
    fi
    case "$6" in
        installed|system_managed) ;;
        *) printf ' (not downloaded)' ;;
    esac
}

# The line for one mode, as markdown: a bold label, the pick, and any second answer on its own
# line. Two trailing spaces before a newline are a markdown hard break, which AttributedString
# keeps (a bare newline collapses to a space). Nothing here says where a figure came from or how
# many recordings it scored: four facts a line is four facts nobody reads, and the Benchmarks tab
# is where provenance belongs.
suggest_line() {   # $1 = picks file, $2 = mode, $3 = language name
    local _mode _kind _id _name _metric _figure _second _rows _corpus _source _state _size _wait
    local _text=""
    local _label="Recordings"
    [ "$2" = live ] && _label="Live"
    # A tab in IFS is whitespace to `read`, which runs a row's empty fields together and shifts
    # the ones after them; the unit separator keeps every field in its place. The here-document
    # keeps the loop in this shell, so _text survives it.
    while IFS="$US" read -r _mode _kind _id _name _metric _figure _second _rows _corpus _source _state _size _wait; do
        [ "$_mode" = "$2" ] || continue
        case "$_kind" in
            none)
                if [ "$_id" = unsupported ]; then
                    _text="**$_label:** no model lists $3."
                elif [ "$_figure" = 0 ]; then
                    _text="**$_label:** nothing measured in $3."
                elif [ "$2" = recordings ]; then
                    _text="**$_label:** not measured in $3 yet - $_figure models list it, and the Benchmarks tab measures one on this Mac."
                else
                    _text="**$_label:** not measured in $3 yet - $_figure models list it."
                fi
                ;;
            accurate)
                if [ -z "$_text" ]; then
                    _text="**$_label:** $(suggest_phrase "$2" "$_name" "$_metric" "$_figure" "$_second" "$_state" "$_wait")"
                else
                    # A second corpus of the same language picked a different model: both are
                    # true, and which one matters depends on the kind of recording.
                    _text="$_text  
**Clear Recordings:** $(suggest_phrase "$2" "$_name" "$_metric" "$_figure" "$_second" "$_state" "$_wait")"
                fi
                ;;
            fast)
                local _second_label="Faster"
                [ "$2" = live ] && _second_label="Quicker to show text"
                _text="$_text  
**$_second_label:** $(suggest_phrase "$2" "$_name" "$_metric" "$_figure" "$_second" "$_state" "$_wait")"
                ;;
        esac
    done <<EOF
$(/usr/bin/tr '\t' '\037' < "$1")
EOF
    printf '%s' "$_text"
}

# The picks for the chosen language, pushed only when their inputs changed.
render_suggestion() {   # $1 = spool
    local _dir="$(suggest_dir "$1")"
    local _tag="$(read_state "$_dir/language.tag")"
    [ -n "$_tag" ] || return 0
    [ -f "$_dir/models.tsv" ] || return 0
    local _results="$(suggest_input results)"
    local _reference="$(suggest_input reference)"
    local _live="$(suggest_input live)"
    local _sig="$_tag|$(/usr/bin/stat -f '%m/%z' "$_dir/models.tsv" 2>/dev/null) $(suggest_inputs_sig)"
    [ "$_sig" = "$(read_state "$_dir/picks.sig")" ] && return 0

    /usr/bin/awk -F'\t' -v language="$_tag" \
        -v mlx="$MLX_MARK" -v ggml="$GGML_MARK" -v fluid="$FLUID_MARK" \
        -f "$SCRIPTS_DIR/speech.suggest.awk" \
        role=models "$_dir/models.tsv" role=results "$_results" \
        role=reference "$_reference" role=live "$_live" > "$_dir/picks.tmp" 2>/dev/null
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        /bin/rm -f "$_dir/picks.tmp"
        return 1
    fi
    /bin/mv -f "$_dir/picks.tmp" "$_dir/picks"
    write_state "$_dir/picks.sig" "$_sig"

    local _name="$(language_display_name "$_tag")"
    "$dialog" "$window_uuid" "$MODELS_BEST_RECORDINGS" markdown \
        "$(suggest_line "$_dir/picks" recordings "$_name")"
    "$dialog" "$window_uuid" "$MODELS_BEST_LIVE" markdown \
        "$(suggest_line "$_dir/picks" live "$_name")"
}

handle_suggest_language_changed() {   # $1 = spool, $2 = picker value
    local _dir="$(suggest_dir "$1")"
    quiet_active "$_dir"
    local _quiet=$?
    [ "$_quiet" -eq 0 ] && return 0
    case "$2" in ''|*[!0-9]*) return 0 ;; esac
    local _tag="$(suggest_language_at "$1" "$2")"
    [ -n "$_tag" ] || return 0
    [ "$_tag" = "$(read_state "$_dir/language.tag")" ] && return 0
    write_state "$_dir/language.tag" "$_tag"
    setting_set models.best.language "$_tag"
    /bin/rm -f "$_dir/picks.sig"
    render_suggestion "$1"
}

suggest_language_at() {   # $1 = spool, $2 = 1-based picker position
    /usr/bin/awk -F'\t' -v line="$2" 'NR == line { print $1; exit }' \
        "$(suggest_dir "$1")/languages.tsv" 2>/dev/null
}

# The box, from the window's init and from every tick that read a new catalog: the language list
# can gain a language when this Mac measures one, and the picks can change when a model is
# downloaded or deleted.
refresh_suggestion() {   # $1 = spool
    local _dir="$(suggest_dir "$1")"
    load_suggest_models "$1" || return 1
    # The list is rebuilt only when the measurement files themselves changed, because filling a
    # picker fires its action with a transitional value; a tick that pushed the same options every
    # half second would spend every tick inside a quiet window.
    local _list_sig="$(suggest_inputs_sig)"
    if [ ! -f "$_dir/languages.tsv" ] || [ ! -f "$_dir/language.tag" ] \
        || [ "$_list_sig" != "$(read_state "$_dir/languages.sig")" ]; then
        populate_suggest_languages "$1"
        local _status=$?
        if [ "$_status" -ne 0 ]; then
            set_shown "$MODELS_BEST_BOX" 0
            return 1
        fi
        write_state "$_dir/languages.sig" "$_list_sig"
        set_shown "$MODELS_BEST_BOX" 1
        /bin/rm -f "$_dir/picks.sig"
    fi
    render_suggestion "$1"
}
