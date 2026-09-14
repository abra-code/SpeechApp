# speech.recordings.stop - stop a batch of recordings. The recording being transcribed is signaled
# and marked as stopping, so the poller, seeing the process gone without a result, reports a stop
# rather than a failure; the recordings still waiting are not started. Transcripts already saved
# stay saved.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

[ "$(read_state "$pane/batch")" = running ] || exit 0
write_state "$pane/batch" stopping

run="$(current_run_dir "$pane")"
if [ -n "$run" ] && [ "$(read_state "$run/state")" = running ]; then
    write_state "$run/state" stopping
    signal_speech_pid "$(read_state "$run/speech.pid")" TERM
fi
set_status "Stopping..."
/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
