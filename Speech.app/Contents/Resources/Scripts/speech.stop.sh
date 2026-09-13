# speech.stop - stop the running transcription. The run is marked as stopping before the process
# is signaled, so the poller, seeing the process gone without a result, reports a stop rather
# than a failure. What was transcribed so far stays in the window.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

spool="$(spool_dir_for "$window_uuid")"
[ -n "$window_uuid" ] && [ -d "$spool" ] || exit 0

run="$(current_run_dir "$spool")"
[ -n "$run" ] || exit 0
[ "$(read_state "$run/state")" = running ] || exit 0

write_state "$run/state" stopping
signal_speech_pid "$(read_state "$run/speech.pid")" TERM
set_status "Stopping..."
/bin/rm -f "$spool/actions.sig"
refresh_actions "$spool"

exit 0
