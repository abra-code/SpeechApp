# speech.corpus.download.worker.sh - downloads one standard corpus, for as long as that takes. Not an
# OMC command: speech.benchmark.download.confirm starts it with /bin/sh, detached, so the download
# goes on when the window closes, and every window's Benchmark tab shows its progress.
#   args: <corpus id> <download dir>
#
# speech's own fetch tool does the work (tools/fetch-fleurs.sh or tools/fetch-librispeech.sh, named in
# corpora.tsv and bundled by update_speech.sh): it downloads the archive, resuming from the bytes on
# disk, checks and unpacks it, and writes the manifest the tab looks for. This script runs it with
# SPEECH_CORPUS_DIR pointed at the app's Corpora directory, waits for it, and records how it ended
# (settle_corpus_download).
#
# When Speech quits, app.will.terminate signals this worker, which stops the tool and the curl or tar
# it is waiting for. The partial archive stays on disk, and the next Download resumes it.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

id="$1"
dir="$2"
[ -n "$id" ] && [ -d "$dir" ] || exit 0

tool="$(corpus_field "$id" 8)"
argument="$(corpus_field "$id" 9)"
if [ -z "$tool" ] || [ -z "$argument" ] || [ ! -f "$FETCH_TOOLS_DIR/$tool" ]; then
    write_state "$dir/message" "Speech has no download tool for $(corpus_title "$id") in $FETCH_TOOLS_DIR."
    write_state "$dir/state" failed
    exit 0
fi

/bin/mkdir -p "$CORPORA_DIR"
mkdir_status=$?
if [ "$mkdir_status" -ne 0 ]; then
    write_state "$dir/message" "Speech could not create $CORPORA_DIR."
    write_state "$dir/state" failed
    exit 0
fi

# A signal to the worker stops the tool and what it is waiting for, and the download counts as
# stopped, not failed. The trap is set before the tool starts, so a signal in between cannot end the
# worker and leave the tool running; one that arrived before the pid was known is acted on after.
stopped=0
fetch_pid=""
trap 'stopped=1; stop_fetch_tool "$fetch_pid" "$tool"' TERM INT HUP

SPEECH_CORPUS_DIR="$CORPORA_DIR" /bin/sh "$FETCH_TOOLS_DIR/$tool" "$argument" < /dev/null > "$dir/fetch.log" 2> "$dir/fetch.err" &
fetch_pid=$!
write_state "$dir/fetch.pid" "$fetch_pid"
[ "$stopped" = 1 ] && stop_fetch_tool "$fetch_pid" "$tool"

wait_for_speech "$fetch_pid"
exit_status=$?

settle_corpus_download "$id" "$dir" "$exit_status" "$stopped"

exit 0
