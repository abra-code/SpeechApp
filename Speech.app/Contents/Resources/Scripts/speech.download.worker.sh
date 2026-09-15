# speech.download.worker.sh - downloads one model, for as long as that takes. Not an OMC command:
# speech.models.download starts it with /bin/sh, detached, so a download goes on after the Models
# window closes, and a Models window opened later shows its progress.
#   args: <catalog id> <download dir>
#
# speech does the downloading: it resumes from the bytes already on disk and marks a row installed
# only once every file checks out. This script waits for it, records how it ended in the download
# directory (settle_download), and then writes a new value into models.changed, which is how every
# window learns to read the catalog again.
#
# When Speech quits, app.will.terminate stops the speech process like any other. What was
# downloaded stays on disk, and the model's card offers Resume.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

id="$1"
dir="$2"
[ -n "$id" ] && [ -d "$dir" ] || exit 0

"$SPEECH_BIN" --json models download "$id" < /dev/null > "$dir/events.jsonl" 2> "$dir/stderr.log" &
speech_pid=$!
write_state "$dir/speech.pid" "$speech_pid"

# A signal to the worker is passed on to speech, so stopping either one ends the download the same
# way.
trap 'signal_speech_pid "$speech_pid" TERM' TERM INT HUP

wait_for_speech "$speech_pid"
exit_status=$?

settle_download "$dir" "$exit_status"

exit 0
