# speech.window.cancel - the window is closing. Stop its speech process, if one is running, and
# remove the window's spool, which ends the poller on its next tick.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
[ -d "$spool" ] || exit 0

run="$(current_run_dir "$spool")"
# A live session would also end without this: removing the spool makes its stdin holder close the
# FIFO. It is signaled anyway, the one place a live session is, because the window and its
# transcript are going away and the microphone should be released now. If Stop was already
# pressed, this TERM is a second stop and cuts the final utterance short - which is what closing
# the window means.
if [ -n "$run" ]; then
    signal_speech_pid "$(read_state "$run/speech.pid")" TERM
fi
/bin/rm -rf "$spool"

exit 0
