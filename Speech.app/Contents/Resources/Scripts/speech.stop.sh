# speech.stop - stop the running transcription or live session. The run is marked as stopping
# first, so the poller, seeing the process gone without a result, reports a stop rather than a
# failure. What was transcribed so far stays in the window.
#
# The two kinds stop differently, because speech does. A file transcription is signaled. A live
# session is asked: Stop leaves a request for the stdin holder (speech.live.stdin.sh), which sends
# "q" and waits for speech to finalize its last utterance and report `done`. A signal sent after
# that would kill the session instead of letting it finish (speech's docs/live.md).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

spool="$(spool_dir_for "$window_uuid")"
[ -n "$window_uuid" ] && [ -d "$spool" ] || exit 0

run="$(current_run_dir "$spool")"
[ -n "$run" ] || exit 0
[ "$(read_state "$run/state")" = running ] || exit 0

write_state "$run/state" stopping
if [ "$(read_state "$run/kind")" = live ]; then
    : > "$run/stop.request"
    set_status "Stopping the recording..."
else
    signal_speech_pid "$(read_state "$run/speech.pid")" TERM
    set_status "Stopping..."
fi
/bin/rm -f "$spool/actions.sig"
refresh_actions "$spool"

exit 0
