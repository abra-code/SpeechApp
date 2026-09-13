# speech.window.cancel - the window is closing. Stop its speech process, if one is running, and
# remove the window's spool, which ends the poller on its next tick.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
[ -d "$spool" ] || exit 0

run="$(current_run_dir "$spool")"
if [ -n "$run" ]; then
    signal_speech_pid "$(read_state "$run/speech.pid")" TERM
fi
/bin/rm -rf "$spool"

exit 0
