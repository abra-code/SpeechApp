# lib.speech.benchmark.sh - the Benchmark tab: measuring models on this Mac over a corpus, the
# queue one worker drains, and the table of results beside the reference measurements published
# with speech. Sourced by the speech.benchmark.* handlers, the window poller (speech.poll.sh) and
# the benchmark worker (speech.benchmark.worker.sh). POSIX /bin/sh (macOS bash 3.2): validate with
# `sh -n`.
#
# Shared by every window, under BENCHMARKS_DIR:
#   results.tsv          every measurement this app has taken, one line each, appended and never
#                        rewritten. Its first 23 columns are those of speech's measurements.tsv, so
#                        one reader shows both; then machine, speech_version, sample (the number of
#                        recordings of a quick sample, or "all"), status (ok | failed) and note.
#   queue/<name>.cell    one measurement waiting: model <TAB> corpus <TAB> sample. Names sort in the
#                        order they were added. A measurement leaves the queue once its line is in
#                        results.tsv; a stopped one stays, and Run starts it again from the start.
#   worker/              worker.pid, state (running | stopping), cell (the name being measured),
#                        speech.pid, stop.request, worker.log
#   runs/<name>/         the measurement in progress, or one that failed: events.jsonl, stderr.log,
#                        report/ (speech's summary.json), total, contended
# Shared by every window, under CORPUS_DOWNLOADS_DIR:
#   <corpus id>/         one corpus's download: worker.pid, fetch.pid (speech's fetch tool),
#                        fetch.log and fetch.err (its output and its messages), state (running |
#                        failed), message (why it failed), archive.seen (the archive has appeared, so
#                        its going means the unpacking is over). A download that finished or was
#                        stopped leaves no directory.
# A window's own, under Sessions/<window>/benchmark:
#   corpus.id, sample, model.id, models.tsv   the tab's choices, and the models it offers for the
#                                             corpus's language
#   corpora.sig          which corpora were on this Mac when the Corpus picker was filled
#   results.sig, results.rows, queue.rows, queue.selected, progress.key, progress.text, actions.sig

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

[ -n "${__SPEECH_BENCHMARK_LIB:-}" ] && return 0
__SPEECH_BENCHMARK_LIB=1

WORKER_DIR="$BENCHMARKS_DIR/worker"
RUNS_DIR="$BENCHMARKS_DIR/runs"
RESULTS_FILE="$BENCHMARKS_DIR/results.tsv"
RESULTS_COLUMNS="model corpus macos language resolved_locales rows skipped wer_pct cer_pct rtfx audio_seconds wall_seconds load_seconds peak_memory_bytes peak_footprint_bytes peak_neural_bytes reference_words reference_characters substitutions deletions insertions character_errors date machine speech_version sample status note"

# --- corpora -------------------------------------------------------------------------------------

corpus_ids() { /usr/bin/awk -F'\t' '!/^#/ && NF >= 5 { print $1 }' "$CORPORA_TSV" 2>/dev/null; }
corpus_title() { corpus_field "$1" 2; }   # $1 = corpus id

corpus_manifest() {   # $1 = corpus id
    printf '%s/%s' "$CORPORA_DIR" "$(corpus_field "$1" 4)"
}

# Returns 0 when the corpus's manifest is on this Mac.
corpus_is_present() {   # $1 = corpus id
    [ -n "$1" ] || return 1
    local _relative="$(corpus_field "$1" 4)"
    [ -n "$_relative" ] || return 1
    [ -s "$CORPORA_DIR/$_relative" ]
}

# Returns 0 when speech publishes reference measurements for this corpus. Only the corpora measured
# for the published battery have them; the rest of the FLEURS languages are offered all the same, and
# their table holds this Mac's own results alone.
corpus_has_reference() {   # $1 = corpus id
    [ -n "$1" ] || return 1
    local _found="$(/usr/bin/awk -F'\t' -v id="$1" '!/^#/ && $2 == id { print "yes"; exit }' "$REFERENCE_MEASUREMENTS" 2>/dev/null)"
    [ -n "$_found" ]
}

# One pass over corpora.tsv (speech.corpora.awk): which corpora are here, where the chosen one sits
# in the picker, and the picker's options. The table has a row for every FLEURS language, so the
# per-row corpus_field this used to do would be a hundred awk processes every half second.
corpora_scan() {   # $1 = the chosen corpus id, $2 = the ids downloading, space surrounded
    /usr/bin/awk -f "$SCRIPTS_DIR/speech.corpora.awk" -v dir="$CORPORA_DIR" \
        -v selected="$1" -v downloading="$2" "$CORPORA_TSV" 2>/dev/null
}

# The corpora downloading right now, each id surrounded by spaces, empty when none is. A corpus has a
# directory here only while its download is unfinished or has failed, so this usually reads nothing.
downloading_corpus_ids() {
    local _ids=" "
    local _dir _alive _id
    for _dir in "$CORPUS_DOWNLOADS_DIR"/*; do
        [ -f "$_dir/worker.pid" ] || continue
        _id="${_dir##*/}"
        corpus_download_alive "$_id"
        _alive=$?
        [ "$_alive" -eq 0 ] && _ids="$_ids$_id "
    done
    printf '%s' "$_ids"
}

# Which corpora are on this Mac, one letter each, and which are downloading, so the poller notices one
# arriving or starting to download.
corpora_signature() {
    local _downloading="$(downloading_corpus_ids)"
    local _marks="$(corpora_scan "" "$_downloading" | /usr/bin/sed -n 1p)"
    printf '%s%s' "$_marks" "$_downloading"
}

# A size as the Models window writes one: "355 MB", "1.2 GB".
format_size() {   # $1 = bytes
    /usr/bin/awk -v b="$1" 'BEGIN { if (b >= 1e9) printf "%.1f GB", b / 1e9; else printf "%.0f MB", b / 1e6 }'
}

# --- downloading a corpus ------------------------------------------------------------------------
# Download runs speech's own fetch tool for the corpus (column 8 of corpora.tsv) under a detached
# worker, speech.corpus.download.worker.sh, with SPEECH_CORPUS_DIR set to the Corpora directory, so
# the corpus lands where the tab looks for it and there is one implementation of fetching, checking
# and unpacking. The whole archive is fetched even for a quick sample: FLEURS and OpenSLR publish one
# archive per split, and the tools resume an interrupted download from the bytes already on disk.
# There is no Stop, as for a model's download; quitting stops it and Download resumes it.

corpus_download_dir() { printf '%s/%s' "$CORPUS_DOWNLOADS_DIR" "$1"; }   # $1 = corpus id

# Returns 0 while the corpus's download worker runs, judged by its argv, so a recycled pid is never
# taken for a download in progress.
corpus_download_alive() {   # $1 = corpus id
    [ -n "$1" ] || return 1
    local _pid_file="$(corpus_download_dir "$1")/worker.pid"
    [ -f "$_pid_file" ] || return 1
    local _pid="$(read_state "$_pid_file")"
    case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
    local _args="$(/bin/ps -p "$_pid" -o args= 2>/dev/null)"
    case "$_args" in
        "/bin/sh $CORPUS_WORKER_SCRIPT $1 "*) return 0 ;;
    esac
    return 1
}

# Returns 0 while any corpus downloads.
any_corpus_download_alive() {
    local _dir _alive
    for _dir in "$CORPUS_DOWNLOADS_DIR"/*; do
        [ -f "$_dir/worker.pid" ] || continue
        corpus_download_alive "${_dir##*/}"
        _alive=$?
        [ "$_alive" -eq 0 ] && return 0
    done
    return 1
}

# Why a corpus's last download failed; empty unless it did and nothing is downloading it now.
corpus_download_failure() {   # $1 = corpus id
    local _dir="$(corpus_download_dir "$1")"
    [ -f "$_dir/state" ] || return 0
    [ "$(read_state "$_dir/state")" = failed ] || return 0
    read_state "$_dir/message"
}

# Bytes free on the volume that holds the Corpora directory; empty when df cannot say.
corpora_free_bytes() {
    /bin/mkdir -p "$CORPORA_DIR" 2>/dev/null
    /bin/df -Pk "$CORPORA_DIR" 2>/dev/null | /usr/bin/awk 'NR == 2 && $4 ~ /^[0-9]+$/ { printf "%.0f", $4 * 1024 }'
}

# Why a corpus cannot be downloaded now; empty when it can. The archive and its unpacked audio are on
# disk together until the tool deletes the archive, less whatever part of the archive is already here.
corpus_download_refusal() {   # $1 = corpus id, $2 = free bytes (empty: not checked)
    local _title="$(corpus_title "$1")"
    corpus_is_present "$1"
    local _present=$?
    if [ "$_present" -eq 0 ]; then
        printf '%s is already on this Mac.' "$_title"
        return 0
    fi
    corpus_download_alive "$1"
    local _alive=$?
    if [ "$_alive" -eq 0 ]; then
        printf '%s is already downloading.' "$_title"
        return 0
    fi
    case "$2" in ''|*[!0-9]*) return 0 ;; esac
    local _archive_bytes="$(corpus_field "$1" 6)"
    local _unpacked_bytes="$(corpus_field "$1" 7)"
    local _have="$(/usr/bin/stat -f %z "$CORPORA_DIR/$(corpus_field "$1" 10)" 2>/dev/null)"
    local _need=$(( ${_archive_bytes:-0} - ${_have:-0} + ${_unpacked_bytes:-0} ))
    [ "$_need" -gt "$2" ] || return 0
    printf '%s needs about %s free while it downloads and unpacks, and this Mac has %s free.' \
        "$_title" "$(format_size "$_need")" "$(format_size "$2")"
}

# The question the Download alert asks: the sizes, why the whole set comes even for a quick sample,
# and where the corpus comes from under which license.
corpus_download_question() {   # $1 = corpus id
    printf 'About %s to download, and %s on this Mac once unpacked. The full set is downloaded even for a quick sample, because it is published as one archive. %s' \
        "$(format_size "$(corpus_field "$1" 6)")" "$(format_size "$(corpus_field "$1" 7)")" "$(corpus_field "$1" 11)"
}

# Start the corpus's download worker, detached, unless one is running. Returns non-zero when it
# cannot start.
start_corpus_download() {   # $1 = corpus id
    local _dir="$(corpus_download_dir "$1")"
    /bin/mkdir -p "$_dir" 2>/dev/null
    local _mkdir_status=$?
    [ "$_mkdir_status" -eq 0 ] || return 1
    /bin/mkdir "$_dir/dispatch.lock" 2>/dev/null
    local _lock_status=$?
    [ "$_lock_status" -eq 0 ] || return 0
    corpus_download_alive "$1"
    local _alive=$?
    if [ "$_alive" -ne 0 ]; then
        /bin/rm -f "$_dir/state" "$_dir/message" "$_dir/fetch.log" "$_dir/fetch.err" "$_dir/fetch.pid" "$_dir/worker.pid" "$_dir/archive.seen"
        write_state "$_dir/state" running
        /bin/sh "$CORPUS_WORKER_SCRIPT" "$1" "$_dir" < /dev/null > /dev/null 2>&1 &
        write_state "$_dir/worker.pid" "$!"
    fi
    /bin/rmdir "$_dir/dispatch.lock" 2>/dev/null
    return 0
}

# End a fetch tool and the process it is waiting for (curl or tar). The tool is judged by its argv;
# its children are taken from the same moment's process list before it is signaled, since once it is
# gone they belong to no one and would go on downloading. Each child is signaled only while its argv
# is still what that list showed, so a pid it gave up in the meantime is not taken for it.
stop_fetch_tool() {   # $1 = tool pid, $2 = tool file name
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    local _args="$(/bin/ps -p "$1" -o args= 2>/dev/null)"
    case "$_args" in
        "/bin/sh $FETCH_TOOLS_DIR/$2 "*) ;;
        *) return 1 ;;
    esac
    local _children="$(/bin/ps -axo pid=,ppid=,args= 2>/dev/null | /usr/bin/awk -v parent="$1" '$2 == parent')"
    /bin/kill -TERM "$1" 2>/dev/null
    local _child _parent _child_args _now
    printf '%s\n' "$_children" | while read -r _child _parent _child_args; do
        case "$_child" in ''|*[!0-9]*) continue ;; esac
        _now="$(/bin/ps -p "$_child" -o args= 2>/dev/null)"
        [ "$_now" = "$_child_args" ] || continue
        /bin/kill -TERM "$_child" 2>/dev/null
    done
    return 0
}

# Why a fetch tool failed, from its messages: the last "-- what went wrong" line and the indented
# line after it that says what to do. curl's exit status, which the tools quote, is put in words for
# the failures a user can do something about.
fetch_error_message() {   # $1 = download dir, $2 = the tool's exit status
    local _message="$(/usr/bin/tr '\r' '\n' < "$1/fetch.err" 2>/dev/null | /usr/bin/awk '
        /^-- / && $0 !~ /^-- [0-9]+ rows/ { text = substr($0, 4); hint = ""; next }
        /^   [^ ]/ && text != "" && hint == "" { hint = substr($0, 4) }
        END { if (text != "") { printf "%s", text; if (hint != "") printf "; %s", hint } }
    ')"
    local _reason=""
    case "$_message" in
        *"(curl 6)"*|*"(curl 7)"*) _reason="The server could not be reached. Check the network connection." ;;
        *"(curl 18)"*|*"(curl 28)"*|*"(curl 56)"*) _reason="The connection dropped." ;;
        *"(curl 22)"*) _reason="The server refused the request." ;;
    esac
    if [ -z "$_message" ]; then
        _message="The download tool ended with status $2 and did not say why."
    else
        _message="The download tool said: $_message."
    fi
    [ -n "$_reason" ] && _message="$_reason $_message"
    printf '%s' "$_message"
}

# Record how a download ended. One that finished, or was stopped, leaves nothing behind but what the
# tool wrote under Corpora; a failed one keeps its directory, so the tab can say why.
settle_corpus_download() {   # $1 = corpus id, $2 = download dir, $3 = the tool's exit status, $4 = 1 when stopped
    if [ "$4" = 1 ]; then
        /bin/rm -rf "$2"
        return 0
    fi
    case "$3" in 129|130|143)
        /bin/rm -rf "$2"
        return 0
        ;;
    esac
    corpus_is_present "$1"
    local _present=$?
    if [ "$3" -eq 0 ] && [ "$_present" -eq 0 ]; then
        /bin/rm -rf "$2"
        return 0
    fi
    local _message
    if [ "$3" -eq 0 ]; then
        _message="The download tool finished but left no list of recordings at $(corpus_manifest "$1")."
    else
        _message="$(fetch_error_message "$2" "$3")"
    fi
    write_state "$2/message" "$_message"
    write_state "$2/state" failed
}

# The status line for a corpus downloading: how much of the archive has arrived, then unpacking, then
# listing the recordings. What the tool is doing is read from its archive, which it names in
# corpora.tsv: growing, whole, then gone.
corpus_download_status() {   # $1 = corpus id
    local _dir="$(corpus_download_dir "$1")"
    local _title="$(corpus_title "$1")"
    local _total="$(corpus_field "$1" 6)"
    local _size="$(/usr/bin/stat -f %z "$CORPORA_DIR/$(corpus_field "$1" 10)" 2>/dev/null)"
    if [ -n "$_size" ]; then
        # printf, not `:`, to make the marker: the worker may have removed the directory since the
        # caller saw it running, and a redirection error on a special builtin ends a non-interactive
        # /bin/sh, which here is the window's poller.
        [ -f "$_dir/archive.seen" ] || printf '' > "$_dir/archive.seen" 2>/dev/null
        if [ "$_size" -lt "${_total:-0}" ]; then
            printf 'Downloading %s: %s of %s (%s%%).' "$_title" "$(format_size "$_size")" "$(format_size "$_total")" "$((_size * 100 / _total))"
        else
            printf 'Unpacking %s...' "$_title"
        fi
    elif [ -f "$_dir/archive.seen" ]; then
        printf 'Listing the recordings of %s...' "$_title"
    else
        printf 'Starting to download %s...' "$_title"
    fi
}

# A sample is the number of recordings a quick sample takes from the start of the corpus, or "all".
sample_limit() {   # $1 = sample; prints nothing for the full set
    case "$1" in ''|all|*[!0-9]*) return 0 ;; esac
    printf '%s' "$1"
}

sample_name() {   # $1 = sample
    if [ "$1" = all ]; then
        printf 'full set'
    else
        printf 'quick sample'
    fi
}

# A model's label as the catalog gives it, with the engine's mark for a table, or plain for the
# status line. The id when the catalog does not list the model.
benchmark_model_label() {   # $1 = spool, $2 = model id, $3 = plain (optional)
    local _row="$(/usr/bin/awk -F'\t' -v id="$2" '$1 == id { print $2 "\t" $3; exit }' "$1/labels.tsv" 2>/dev/null)"
    if [ -z "$_row" ]; then
        printf '%s' "$2"
        return 0
    fi
    if [ -n "${3:-}" ]; then
        printf '%s' "${_row%%"$TAB"*}"
    else
        model_display_label "${_row%%"$TAB"*}" "${_row#*"$TAB"}"
    fi
}

# --- the queue -----------------------------------------------------------------------------------

queued_cells() {   # prints the names of the waiting measurements, in order
    local _cell
    for _cell in "$BENCHMARKS_DIR"/queue/*.cell; do
        [ -f "$_cell" ] || continue
        _cell="${_cell##*/}"
        printf '%s\n' "${_cell%.cell}"
    done
}

queue_count() { queued_cells | /usr/bin/awk 'END { print NR }'; }

cell_field() {   # $1 = cell name, $2 = column (1 model, 2 corpus, 3 sample)
    /usr/bin/awk -F'\t' -v col="$2" 'NR == 1 { print $col; exit }' "$BENCHMARKS_DIR/queue/$1.cell" 2>/dev/null
}

# Queue a measurement. Returns 1 when the same one is already waiting, 2 when it cannot be written.
add_cell() {   # $1 = model id, $2 = corpus id, $3 = sample
    /bin/mkdir -p "$BENCHMARKS_DIR/queue" 2>/dev/null
    local _mkdir_status=$?
    [ "$_mkdir_status" -eq 0 ] || return 2
    local _line="$1$TAB$2$TAB$3"
    local _name
    for _name in $(queued_cells); do
        [ "$(read_state "$BENCHMARKS_DIR/queue/$_name.cell")" = "$_line" ] && return 1
    done
    # Seconds, then this handler's pid: names sort in the order they were added, and a name taken
    # in the same second moves to the next one.
    local _now="$(/bin/date +%s)"
    _name="$(printf '%s-%06d' "$_now" "$$")"
    while [ -e "$BENCHMARKS_DIR/queue/$_name.cell" ]; do
        _now=$((_now + 1))
        _name="$(printf '%s-%06d' "$_now" "$$")"
    done
    write_state "$BENCHMARKS_DIR/queue/$_name.cell" "$_line" || return 2
    return 0
}

# Take a measurement out of the queue. Returns 1 when it is the one being measured.
remove_cell() {   # $1 = cell name
    benchmark_worker_alive
    local _alive=$?
    if [ "$_alive" -eq 0 ] && [ "$(read_state "$WORKER_DIR/cell")" = "$1" ]; then
        return 1
    fi
    /bin/rm -f "$BENCHMARKS_DIR/queue/$1.cell"
    return 0
}

# --- the worker ----------------------------------------------------------------------------------

# Returns 0 while the benchmark worker runs, judged by its argv, so a recycled pid is never taken for
# a measurement in progress.
benchmark_worker_alive() {
    local _pid="$(read_state "$WORKER_DIR/worker.pid")"
    case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
    local _args="$(/bin/ps -p "$_pid" -o args= 2>/dev/null)"
    case "$_args" in
        "/bin/sh $BENCHMARK_WORKER_SCRIPT"|"/bin/sh $BENCHMARK_WORKER_SCRIPT "*) return 0 ;;
    esac
    return 1
}

# Start the worker, detached, unless one is running. A second Run, in this window or another, finds
# the lock or the running worker and does nothing. Returns non-zero when it cannot start.
start_benchmark_worker() {
    /bin/mkdir -p "$WORKER_DIR" 2>/dev/null
    local _mkdir_status=$?
    [ "$_mkdir_status" -eq 0 ] || return 1
    /bin/mkdir "$BENCHMARKS_DIR/dispatch.lock" 2>/dev/null
    local _lock_status=$?
    [ "$_lock_status" -eq 0 ] || return 0
    benchmark_worker_alive
    local _alive=$?
    if [ "$_alive" -ne 0 ]; then
        /bin/rm -f "$WORKER_DIR/cell" "$WORKER_DIR/speech.pid" "$WORKER_DIR/stop.request" "$WORKER_DIR/worker.pid"
        write_state "$WORKER_DIR/state" running
        /bin/sh "$BENCHMARK_WORKER_SCRIPT" < /dev/null > "$WORKER_DIR/worker.log" 2>&1 &
        write_state "$WORKER_DIR/worker.pid" "$!"
    fi
    /bin/rmdir "$BENCHMARKS_DIR/dispatch.lock" 2>/dev/null
    return 0
}

# Stop: the worker is asked to finish, and the measurement in progress is signaled. It stays in the
# queue; what was scored of it so far is not kept, because a WER over part of a corpus is not that
# corpus's WER.
stop_benchmark() {
    benchmark_worker_alive
    local _alive=$?
    [ "$_alive" -eq 0 ] || return 0
    write_state "$WORKER_DIR/state" stopping
    : > "$WORKER_DIR/stop.request"
    signal_speech_pid "$(read_state "$WORKER_DIR/speech.pid")" TERM
    return 0
}

# Returns 0 while any window is transcribing, live or from recordings, or making a recording. A
# measurement taken meanwhile shares the processor, the GPU and the Neural Engine with it.
other_windows_busy() {
    local _pane _busy
    for _pane in "$SESSIONS_DIR"/*/live "$SESSIONS_DIR"/*/recordings; do
        [ -d "$_pane" ] || continue
        pane_is_busy "$_pane"
        _busy=$?
        [ "$_busy" -eq 0 ] && return 0
    done
    return 1
}

# Returns 0 while anything else Speech does competes with a measurement: a window at work, or a
# corpus downloading, whose unpacking takes the processor and the disk.
competing_work_busy() {
    local _busy
    other_windows_busy
    _busy=$?
    [ "$_busy" -eq 0 ] && return 0
    any_corpus_download_alive
}

# Mark the run contended whenever other work is busy, for as long as speech runs. Also the net under
# Stop: a Stop pressed before speech.pid was written signals nothing, so speech is signaled here
# once stop.request is seen, as it is when the app that started the worker is gone without running
# app.will.terminate (killed), which would otherwise leave speech measuring for the rest of the
# corpus.
watch_contention() {   # $1 = run dir, $2 = speech pid, $3 = app pid (optional)
    local _alive _busy _app_alive
    while :; do
        pid_alive "$2"
        _alive=$?
        [ "$_alive" -eq 0 ] || break
        competing_work_busy
        _busy=$?
        [ "$_busy" -eq 0 ] && : > "$1/contended"
        if [ -f "$WORKER_DIR/stop.request" ]; then
            signal_speech_pid "$2" TERM
        elif [ -n "${3:-}" ]; then
            pid_alive "$3"
            _app_alive=$?
            [ "$_app_alive" -eq 0 ] || signal_speech_pid "$2" TERM
        fi
        /bin/sleep 2
    done
}

append_result() {   # $1 = one line of results.tsv
    /bin/mkdir -p "$BENCHMARKS_DIR" 2>/dev/null
    if [ ! -s "$RESULTS_FILE" ]; then
        printf '%s\n' "$RESULTS_COLUMNS" | /usr/bin/tr ' ' '\t' > "$RESULTS_FILE"
    fi
    printf '%s\n' "$1" >> "$RESULTS_FILE"
}

# A failed measurement's line: what was asked, when and where, and why it failed.
record_failed_cell() {   # $1 = model, $2 = corpus, $3 = sample, $4 = speech version, $5 = reason
    local _macos="$(/usr/bin/sw_vers -productVersion 2>/dev/null)"
    local _machine="$(/usr/sbin/sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    local _date="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
    local _note="$(printf '%s' "$5" | /usr/bin/tr '\t\r\n' '   ')"
    # Columns 5 to 22 hold figures, and a failed measurement has none.
    local _blank=""
    local _i=0
    while [ "$_i" -lt 18 ]; do
        _blank="$_blank$TAB"
        _i=$((_i + 1))
    done
    append_result "$(printf '%s\t%s\t%s\t%s\t%s%s\t%s\t%s\t%s\tfailed\t%s' \
        "$1" "$2" "$_macos" "$(corpus_field "$2" 3)" "$_blank" "$_date" "$_machine" "$4" "$3" "$_note")"
}

# Why speech failed: its error event, else the last line of its stderr.
benchmark_error_message() {   # $1 = run dir, $2 = speech's exit status
    local _message="$("$jq" -R -r 'fromjson? | select(type == "object" and .type == "error") | .message // empty' "$1/events.jsonl" 2>/dev/null | /usr/bin/tail -1)"
    [ -n "$_message" ] || _message="$(/usr/bin/tail -1 "$1/stderr.log" 2>/dev/null)"
    if [ -z "$_message" ] && [ "$2" -gt 128 ]; then
        _message="speech ended on signal $(($2 - 128)) and did not say why."
    fi
    [ -n "$_message" ] || _message="speech ended with status $2 and did not say why."
    printf '%s' "$_message"
}

# Measure one queued cell with `speech eval`, and settle it. The worker's only job; it keeps the
# speech pid in BENCH_SPEECH_PID for its signal trap, reads BENCH_STOP, which the trap sets, and
# BENCH_APP_PID, the app whose going ends the measurement.
# Returns 0 when the measurement was recorded, as a result or a failure, and 2 when it was stopped
# and stays in the queue.
measure_cell() {   # $1 = cell name, $2 = speech version
    local _cell="$BENCHMARKS_DIR/queue/$1.cell"
    local _model="$(cell_field "$1" 1)"
    local _corpus="$(cell_field "$1" 2)"
    local _sample="$(cell_field "$1" 3)"
    local _run="$RUNS_DIR/$1"
    if [ -z "$_model" ] || [ -z "$_corpus" ]; then
        /bin/rm -f "$_cell"
        return 0
    fi
    write_state "$WORKER_DIR/cell" "$1"

    /bin/rm -rf "$_run"
    /bin/mkdir -p "$_run/report"
    local _mkdir_status=$?
    if [ "$_mkdir_status" -ne 0 ]; then
        record_failed_cell "$_model" "$_corpus" "$_sample" "$2" "Speech could not create $_run."
        /bin/rm -f "$_cell"
        return 0
    fi
    local _manifest="$(corpus_manifest "$_corpus")"
    corpus_is_present "$_corpus"
    local _present=$?
    if [ "$_present" -ne 0 ]; then
        record_failed_cell "$_model" "$_corpus" "$_sample" "$2" "$(corpus_title "$_corpus") is not on this Mac."
        /bin/rm -f "$_cell"
        return 0
    fi
    local _language="$(corpus_field "$_corpus" 3)"
    local _limit="$(sample_limit "$_sample")"
    local _total="$(/usr/bin/awk 'NF { n++ } END { print n + 0 }' "$_manifest" 2>/dev/null)"
    [ -n "$_limit" ] && [ "${_total:-0}" -gt "$_limit" ] && _total="$_limit"
    write_state "$_run/total" "$_total"

    local _busy
    competing_work_busy
    _busy=$?
    [ "$_busy" -eq 0 ] && : > "$_run/contended"

    # A Stop that arrived since the worker's loop looked: nothing to signal yet, so do not start.
    if [ "${BENCH_STOP:-0}" = 1 ] || [ -f "$WORKER_DIR/stop.request" ]; then
        return 2
    fi
    if [ -n "$_limit" ]; then
        "$SPEECH_BIN" --json eval --model "$_model" --manifest "$_manifest" --language "$_language" \
            --limit "$_limit" --report "$_run/report" < /dev/null > "$_run/events.jsonl" 2> "$_run/stderr.log" &
    else
        "$SPEECH_BIN" --json eval --model "$_model" --manifest "$_manifest" --language "$_language" \
            --report "$_run/report" < /dev/null > "$_run/events.jsonl" 2> "$_run/stderr.log" &
    fi
    BENCH_SPEECH_PID=$!
    write_state "$WORKER_DIR/speech.pid" "$BENCH_SPEECH_PID"
    watch_contention "$_run" "$BENCH_SPEECH_PID" "${BENCH_APP_PID:-}" < /dev/null > /dev/null 2>&1 &
    local _watcher=$!
    wait_for_speech "$BENCH_SPEECH_PID"
    local _status=$?
    /bin/kill "$_watcher" 2>/dev/null
    BENCH_SPEECH_PID=""
    /bin/rm -f "$WORKER_DIR/speech.pid"
    competing_work_busy
    _busy=$?
    [ "$_busy" -eq 0 ] && : > "$_run/contended"

    if [ "${BENCH_STOP:-0}" = 1 ] || [ -f "$WORKER_DIR/stop.request" ]; then
        return 2
    fi
    # HUP, INT and TERM are how speech is stopped: by Stop, by quitting, by a watcher that found the
    # app gone. Any other signal is a crash or the system killing it for memory, which is recorded as
    # a failure rather than quietly queued again.
    case "$_status" in 129|130|143) return 2 ;; esac

    if [ "$_status" -eq 0 ] && [ -s "$_run/report/summary.json" ]; then
        local _note=""
        [ -f "$_run/contended" ] && _note="Speech was transcribing in a window or downloading a corpus during this measurement, so its speed and memory may be worse than this Mac can do."
        local _line
        _line="$("$jq" -r --arg corpus "$_corpus" --arg sample "$_sample" --arg version "$2" --arg note "$_note" \
            -f "$SCRIPTS_DIR/speech.benchmark.summary.jq" "$_run/report/summary.json" 2> "$_run/summary.err")"
        local _jq_status=$?
        if [ "$_jq_status" -eq 0 ] && [ -n "$_line" ]; then
            append_result "$_line"
            /bin/rm -f "$_cell"
            /bin/rm -rf "$_run"
            return 0
        fi
        record_failed_cell "$_model" "$_corpus" "$_sample" "$2" "speech's summary could not be read: $(/usr/bin/head -1 "$_run/summary.err" 2>/dev/null)"
        /bin/rm -f "$_cell"
        return 0
    fi

    record_failed_cell "$_model" "$_corpus" "$_sample" "$2" "$(benchmark_error_message "$_run" "$_status")"
    /bin/rm -f "$_cell"
    return 0
}

# --- progress ------------------------------------------------------------------------------------

# How far the measurement in progress has got, without trailing punctuation: recordings scored and
# the word error rate so far, or what speech is doing before the first recording. The events are read
# again only when the file has grown.
benchmark_progress_text() {   # $1 = pane dir, $2 = cell name
    local _run="$RUNS_DIR/$2"
    local _size="$(/usr/bin/stat -f %z "$_run/events.jsonl" 2>/dev/null)"
    if [ "$2|$_size" = "$(read_state "$1/progress.key")" ]; then
        read_state "$1/progress.text"
        return 0
    fi
    local _record="$("$jq" -R -r -n --arg us "$US" -f "$SCRIPTS_DIR/speech.benchmark.progress.jq" "$_run/events.jsonl" 2>/dev/null)"
    local _rows="${_record%%"$US"*}"
    local _rest="${_record#*"$US"}"
    local _wer="${_rest%%"$US"*}"
    _rest="${_rest#*"$US"}"
    local _phase="${_rest%%"$US"*}"
    _rest="${_rest#*"$US"}"
    local _percent="${_rest%%"$US"*}"
    local _file="${_rest#*"$US"}"
    local _text
    case "$_rows" in ''|*[!0-9]*) _rows=0 ;; esac
    if [ "$_rows" -gt 0 ]; then
        _text="$_rows of $(read_state "$_run/total") recordings, about $_wer% WER so far"
    else
        case "$_phase" in
            downloading) _text="Downloading the model, ${_percent:-0}%" ;;
            installing)
                if [ -n "$_file" ]; then
                    _text="Downloading Apple's $(language_display_name "${_file%%[-_]*}") speech files, ${_percent:-0}%"
                else
                    _text="Installing the model, ${_percent:-0}%"
                fi
                ;;
            compiling) _text="Preparing the model (may be slow on first run)" ;;
            *) _text="Loading the model" ;;
        esac
    fi
    write_state "$1/progress.key" "$2|$_size"
    write_state "$1/progress.text" "$_text"
    printf '%s' "$_text"
}

# --- the tab -------------------------------------------------------------------------------------

# The poller's first job for the tab, once the model list is read: the saved corpus, else the first
# one on this Mac, else the first; the saved sample size; and the pickers.
setup_benchmark() {   # $1 = spool
    use_pane benchmark
    local _pane="$1/benchmark"
    /bin/mkdir -p "$_pane"
    local _corpus="$(setting_get benchmark.corpus)"
    [ -n "$_corpus" ] && [ -z "$(corpus_title "$_corpus")" ] && _corpus=""
    if [ -z "$_corpus" ]; then
        # The marks are one character per corpus in the table's order, so what stands before the
        # first p counts the corpora that are not here: the first one that is sits one line further.
        local _marks="$(corpora_scan "" "$(downloading_corpus_ids)" | /usr/bin/sed -n 1p)"
        local _absent="${_marks%%p*}"
        [ "$_absent" != "$_marks" ] && _corpus="$(corpus_ids | /usr/bin/sed -n "$(( ${#_absent} + 1 ))p")"
    fi
    [ -n "$_corpus" ] || _corpus="$(corpus_ids | /usr/bin/head -1)"
    write_state "$_pane/corpus.id" "$_corpus"
    local _sample="$(setting_get benchmark.sample)"
    [ "$_sample" = all ] || _sample="$QUICK_SAMPLE_ROWS"
    write_state "$_pane/sample" "$_sample"

    populate_corpus_picker "$_pane"
    populate_sample_picker "$_pane"
    pane_models "$1" benchmark
    populate_model_picker "$_pane"
}

# The Corpus picker: every standard corpus, with the ones not on this Mac said so.
populate_corpus_picker() {   # $1 = pane dir
    local _selected="$(read_state "$1/corpus.id")"
    local _downloading="$(downloading_corpus_ids)"
    local _scan="$(corpora_scan "$_selected" "$_downloading")"
    local _marks="$(printf '%s\n' "$_scan" | /usr/bin/sed -n 1p)"
    local _line="$(printf '%s\n' "$_scan" | /usr/bin/sed -n 2p)"
    local _options="$(printf '%s\n' "$_scan" | /usr/bin/sed -n 3p)"
    write_state "$1/corpora.sig" "$_marks$_downloading"
    quiet_begin "$1"
    "$dialog" "$window_uuid" "$BENCH_CORPUS_PICKER" omc_set_property "options" "$_options"
    [ -n "$_line" ] && "$dialog" "$window_uuid" "$BENCH_CORPUS_PICKER" "$_line"
    return 0
}

populate_sample_picker() {   # $1 = pane dir
    local _rows="$(corpus_field "$(read_state "$1/corpus.id")" 5)"
    local _line=1
    [ "$(read_state "$1/sample")" = all ] && _line=2
    quiet_begin "$1"
    "$dialog" "$window_uuid" "$BENCH_SAMPLE_PICKER" omc_set_property "options" \
        "[\"Quick sample ($QUICK_SAMPLE_ROWS recordings)\",\"Full set (${_rows:-all} recordings)\"]"
    "$dialog" "$window_uuid" "$BENCH_SAMPLE_PICKER" "$_line"
}

# The Corpus picker changed: its sample sizes, the models that speak its language, and its results.
handle_corpus_changed() {   # $1 = spool, $2 = picker value
    local _pane="$1/benchmark"
    quiet_active "$_pane"
    local _quiet=$?
    [ "$_quiet" -eq 0 ] && return 0
    case "$2" in ''|*[!0-9]*) return 0 ;; esac
    local _corpus="$(corpus_ids | /usr/bin/sed -n "${2}p")"
    [ -n "$_corpus" ] || return 0
    [ "$_corpus" = "$(read_state "$_pane/corpus.id")" ] && return 0
    write_state "$_pane/corpus.id" "$_corpus"
    setting_set benchmark.corpus "$_corpus"
    populate_sample_picker "$_pane"
    pane_models "$1" benchmark
    populate_model_picker "$_pane"
    /bin/rm -f "$_pane/results.sig" "$_pane/actions.sig"
    render_results_table "$1"
}

handle_sample_changed() {   # $1 = spool, $2 = picker value
    local _pane="$1/benchmark"
    quiet_active "$_pane"
    local _quiet=$?
    [ "$_quiet" -eq 0 ] && return 0
    local _sample
    case "$2" in
        1) _sample="$QUICK_SAMPLE_ROWS" ;;
        2) _sample=all ;;
        *) return 0 ;;
    esac
    [ "$_sample" = "$(read_state "$_pane/sample")" ] && return 0
    write_state "$_pane/sample" "$_sample"
    setting_set benchmark.sample "$_sample"
    /bin/rm -f "$_pane/results.sig" "$_pane/actions.sig"
    render_results_table "$1"
}

# The results table for the tab's corpus and sample size (speech.benchmark.results.awk), pushed
# only when its inputs or the rows changed.
render_results_table() {   # $1 = spool
    local _pane="$1/benchmark"
    local _corpus="$(read_state "$_pane/corpus.id")"
    local _sample="$(read_state "$_pane/sample")"
    local _results="$RESULTS_FILE"
    [ -f "$_results" ] || _results=/dev/null
    local _reference="$REFERENCE_MEASUREMENTS"
    [ -f "$_reference" ] || _reference=/dev/null
    local _labels="$1/labels.tsv"
    [ -f "$_labels" ] || _labels=/dev/null
    local _sig="$_corpus|$_sample|$(/usr/bin/stat -f '%m %z' "$_results" "$_reference" "$_labels" 2>/dev/null | /usr/bin/tr '\n' ' ')"
    [ "$_sig" = "$(read_state "$_pane/results.sig")" ] && return 0

    local _this_macos="$(read_state "$1/this_macos")"
    local _rows="$_pane/results.rows.tmp.$$"
    /usr/bin/awk -F'\t' -v corpus="$_corpus" -v sample="$_sample" \
        -v macos="$_this_macos" \
        -v mlx="$MLX_MARK" -v ggml="$GGML_MARK" -v fluid="$FLUID_MARK" \
        -f "$SCRIPTS_DIR/speech.benchmark.results.awk" \
        role=labels "$_labels" role=results "$_results" role=reference "$_reference" 2>/dev/null \
        | LC_ALL=C /usr/bin/sort -t "$TAB" -k1,1 | /usr/bin/cut -f2- > "$_rows"
    write_state "$_pane/results.sig" "$_sig"
    /usr/bin/cmp -s "$_rows" "$_pane/results.rows"
    local _same=$?
    if [ "$_same" -eq 0 ] && [ -f "$_pane/results.shown" ]; then
        /bin/rm -f "$_rows"
        return 0
    fi
    /bin/mv -f "$_rows" "$_pane/results.rows"
    "$dialog" "$window_uuid" "$BENCH_RESULTS_TABLE" omc_table_set_rows_from_stdin < "$_pane/results.rows"
    : > "$_pane/results.shown"
}

# Every waiting measurement's row before its status, in queue order: name <TAB> the model's label
# with the engine's mark <TAB> "corpus, sample". One awk over every cell, where a lookup per column
# per row cost a quarter of a second a tick with ten rows queued.
queue_static_rows() {   # $1 = spool
    local _labels="$1/labels.tsv"
    [ -f "$_labels" ] || _labels=/dev/null
    set -- "$BENCHMARKS_DIR"/queue/*.cell
    [ -f "$1" ] || return 0
    /usr/bin/awk -F'\t' -v mlx="$MLX_MARK" -v ggml="$GGML_MARK" -v fluid="$FLUID_MARK" '
        role == "labels" { label[$1] = $2; engine[$1] = $3; next }
        role == "corpora" { if ($0 !~ /^#/) title[$1] = $2; next }
        FNR == 1 {
            name = FILENAME; sub(/.*\//, "", name); sub(/\.cell$/, "", name)
            model = ($1 in label) ? label[$1] : $1
            if (engine[$1] == "mlx") model = model " " mlx
            else if (engine[$1] == "ggml") model = model " " ggml
            else if (engine[$1] == "fluid") model = model " " fluid
            print name "\t" model "\t" (($2 in title) ? title[$2] : $2) ", " ($3 == "all" ? "full set" : "quick sample")
        }
    ' role=labels "$_labels" role=corpora "$CORPORA_TSV" role=cells "$@" 2>/dev/null
}

# The queue table: model, corpus and sample, and what is happening to each, with the cell's name in
# a hidden fourth column. Pushed when a row changed, with the selection put back.
render_queue_table() {   # $1 = spool
    local _pane="$1/benchmark"
    local _rows="$_pane/queue.rows.tmp.$$"
    : > "$_rows"
    local _running=""
    local _stopping=0
    benchmark_worker_alive
    local _alive=$?
    if [ "$_alive" -eq 0 ]; then
        _running="$(read_state "$WORKER_DIR/cell")"
        [ "$(read_state "$WORKER_DIR/state")" = stopping ] && _stopping=1
    fi
    local _name _label _what _status
    queue_static_rows "$1" | while IFS="$TAB" read -r _name _label _what; do
        if [ "$_name" != "$_running" ]; then
            _status="Waiting"
        elif [ "$_stopping" = 1 ]; then
            _status="Stopping..."
        else
            _status="$(benchmark_progress_text "$_pane" "$_name")"
        fi
        printf '%s\t%s\t%s\t%s\n' "$_label" "$_what" "$_status" "$_name" >> "$_rows"
    done
    /usr/bin/cmp -s "$_rows" "$_pane/queue.rows"
    local _same=$?
    if [ "$_same" -eq 0 ] && [ -f "$_pane/queue.shown" ]; then
        /bin/rm -f "$_rows"
        return 0
    fi
    /bin/mv -f "$_rows" "$_pane/queue.rows"
    quiet_begin "$_pane" table
    "$dialog" "$window_uuid" "$BENCH_QUEUE_TABLE" omc_table_set_rows_from_stdin < "$_pane/queue.rows"
    : > "$_pane/queue.shown"
    local _selected="$(read_state "$_pane/queue.selected")"
    [ -n "$_selected" ] || return 0
    if [ -f "$BENCHMARKS_DIR/queue/$_selected.cell" ]; then
        "$dialog" "$window_uuid" "$BENCH_QUEUE_TABLE" omc_select_row_with_content "$_selected" 4
    else
        /bin/rm -f "$_pane/queue.selected"
    fi
    return 0
}

# Every control's state and the status line, from the tab's choices and the shared queue.
refresh_benchmark_actions() {   # $1 = spool
    use_pane benchmark
    local _pane="$1/benchmark"
    [ -f "$_pane/corpus.id" ] || return 0
    local _corpus="$(read_state "$_pane/corpus.id")"
    local _model="$(read_state "$_pane/model.id")"
    local _models_ready=0
    [ -f "$_pane/models.tsv" ] && _models_ready=1
    corpus_is_present "$_corpus"
    local _present_status=$?
    local _present=0
    [ "$_present_status" -eq 0 ] && _present=1
    local _downloading=0
    local _download_failure=""
    if [ "$_present" = 0 ] && [ -n "$_corpus" ]; then
        corpus_download_alive "$_corpus"
        local _downloading_status=$?
        [ "$_downloading_status" -eq 0 ] && _downloading=1
        [ "$_downloading" = 0 ] && _download_failure="$(corpus_download_failure "$_corpus")"
    fi
    local _count="$(queue_count)"
    benchmark_worker_alive
    local _alive_status=$?
    local _alive=0
    [ "$_alive_status" -eq 0 ] && _alive=1
    local _state=""
    local _cell=""
    if [ "$_alive" = 1 ]; then
        _state="$(read_state "$WORKER_DIR/state")"
        _cell="$(read_state "$WORKER_DIR/cell")"
    fi
    local _selected="$(read_state "$_pane/queue.selected")"
    if [ -n "$_selected" ] && [ ! -f "$BENCHMARKS_DIR/queue/$_selected.cell" ]; then
        _selected=""
    fi

    local _can_add=0
    [ "$_models_ready" = 1 ] && [ -n "$_model" ] && [ "$_present" = 1 ] && _can_add=1
    local _can_run=0
    [ "${_count:-0}" -gt 0 ] && [ "$_alive" = 0 ] && _can_run=1
    local _can_stop=0
    [ "$_alive" = 1 ] && [ "$_state" != stopping ] && _can_stop=1
    local _can_remove=0
    [ -n "$_selected" ] && [ "$_selected" != "$_cell" ] && _can_remove=1
    local _can_download=0
    [ "$_models_ready" = 1 ] && [ -n "$_corpus" ] && [ "$_present" = 0 ] && [ "$_downloading" = 0 ] && _can_download=1
    local _can_reveal=0
    [ "$_models_ready" = 1 ] && [ "$_present" = 1 ] && _can_reveal=1

    # A corpus downloading or failed to download says so before the measurement's progress, which the
    # queue table shows anyway: it is the corpus the user is looking at.
    local _text=""
    if [ "$_alive" = 1 ] && [ "$_state" = stopping ]; then
        _text="Stopping the measurement. Everything still waiting stays in the queue."
    elif [ "$_models_ready" = 1 ] && [ "$_downloading" = 1 ]; then
        _text="$(corpus_download_status "$_corpus")"
    elif [ "$_models_ready" = 1 ] && [ -n "$_download_failure" ]; then
        _text="Could not download $(corpus_title "$_corpus"). $_download_failure Press Download to try again."
    elif [ "$_alive" = 1 ] && [ -n "$_cell" ] && [ -f "$BENCHMARKS_DIR/queue/$_cell.cell" ]; then
        _text="Measuring $(benchmark_model_label "$1" "$(cell_field "$_cell" 1)" plain) on $(corpus_title "$(cell_field "$_cell" 2)"), $(sample_name "$(cell_field "$_cell" 3)"): $(benchmark_progress_text "$_pane" "$_cell")."
        [ "$_count" -gt 1 ] && _text="$_text $((_count - 1)) more waiting."
    elif [ "$_alive" = 1 ]; then
        _text="Measuring..."
    elif [ "$_models_ready" = 0 ]; then
        _text=""
    elif [ "$_present" = 0 ]; then
        _text="$(corpus_title "$_corpus") is not on this Mac yet. Press Download to get it ($(format_size "$(corpus_field "$_corpus" 6)"))."
    elif [ -z "$_model" ]; then
        local _tag="$(corpus_field "$_corpus" 3)"
        _text="No model on this Mac transcribes $(language_display_name "${_tag%%-*}") yet. Choose $DOWNLOAD_MODELS_OPTION in the Model picker to get one."
    elif [ "$_count" = 1 ]; then
        _text="1 measurement is waiting. Press Run to measure it."
    elif [ "${_count:-0}" -gt 1 ]; then
        _text="$_count measurements are waiting. Press Run to measure them one after another."
    else
        corpus_has_reference "$_corpus"
        local _has_reference=$?
        if [ "$_has_reference" -eq 0 ]; then
            _text="Add models to the queue, then press Run. Results from this Mac are listed above the reference results."
        else
            _text="Add models to the queue, then press Run. No reference results are published for $(corpus_title "$_corpus"), so the table shows this Mac's measurements alone."
        fi
    fi

    local _signature="$_can_add$_can_run$_can_stop$_can_remove$_can_download$_can_reveal$_models_ready|$_text"
    [ "$_signature" = "$(read_state "$_pane/actions.sig")" ] && return 0
    write_state "$_pane/actions.sig" "$_signature"

    set_enabled "$BENCH_ADD_BTN" "$_can_add"
    set_enabled "$BENCH_DOWNLOAD_BTN" "$_can_download"
    set_enabled "$BENCH_REVEAL_BTN" "$_can_reveal"
    set_enabled "$BENCH_RUN_BTN" "$_can_run"
    set_enabled "$BENCH_STOP_BTN" "$_can_stop"
    set_enabled "$BENCH_REMOVE_BTN" "$_can_remove"
    set_enabled "$BENCH_CORPUS_PICKER" "$_models_ready"
    set_enabled "$BENCH_SAMPLE_PICKER" "$_models_ready"
    set_enabled "$BENCH_MODEL_PICKER" "$_models_ready"
    [ -n "$_text" ] && set_status "$_text"
    return 0
}

# One poller tick for the tab.
poll_benchmark() {   # $1 = spool
    use_pane benchmark
    local _pane="$1/benchmark"
    [ -f "$_pane/corpus.id" ] || return 0
    if [ "$(corpora_signature)" != "$(read_state "$_pane/corpora.sig")" ]; then
        populate_corpus_picker "$_pane"
        /bin/rm -f "$_pane/actions.sig"
    fi
    render_results_table "$1"
    render_queue_table "$1"
    refresh_benchmark_actions "$1"
}
