# speech.add.worker.sh - adds one model with `speech models add`, for as long as that takes. Not an
# OMC command: speech.models.add.start starts it with /bin/sh, detached, so an add goes on after
# the Models window closes, and a Models window opened later shows its progress.
#   args: <owner/repo> <add dir>; the quantization, when one was given, is in <add dir>/quant
#
# speech lists the repository, downloads the file, loads it to check that transcribe.cpp can run
# it, and writes the catalog entry; a file it cannot run is refused and its download removed. This
# script waits for it and records how it ended (settle_add in lib.speech.models.sh).
#
# When Speech quits, app.will.terminate stops the speech process like any other, and the add is
# recorded as stopped.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

repo="$1"
dir="$2"
[ -n "$repo" ] && [ -d "$dir" ] || exit 0
quant="$(read_state "$dir/quant")"

if [ -n "$quant" ]; then
    "$SPEECH_BIN" --json models add "$repo" --quant "$quant" < /dev/null > "$dir/events.jsonl" 2> "$dir/stderr.log" &
else
    "$SPEECH_BIN" --json models add "$repo" < /dev/null > "$dir/events.jsonl" 2> "$dir/stderr.log" &
fi
speech_pid=$!
write_state "$dir/speech.pid" "$speech_pid"

# A signal to the worker is passed on to speech, so stopping either one ends the add the same way.
trap 'signal_speech_pid "$speech_pid" TERM' TERM INT HUP

wait_for_speech "$speech_pid"
exit_status=$?

settle_add "$dir" "$exit_status"

exit 0
