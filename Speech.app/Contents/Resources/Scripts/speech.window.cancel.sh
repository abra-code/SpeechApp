# speech.window.cancel - the window is closing. Stop its speech processes, if any are running, and
# remove the window's spool, which ends the poller on its next tick.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
[ -d "$spool" ] || exit 0

# A live session would also end without this: removing the spool makes its stdin holder close the
# FIFO. It is signaled anyway, the one place a live session is, because the window and its
# transcript are going away and the microphone should be released now. If Stop was already
# pressed, this TERM is a second stop and cuts the final utterance short - which is what closing
# the window means. A recording being transcribed is signaled for the same reason; the recordings
# still waiting in the batch are simply never started. A new recording being made is signaled
# too: `speech record` treats TERM as a stop and keeps the file it wrote, though the window that
# would have listed it is gone.
for pane in live recordings; do
    run="$(current_run_dir "$spool/$pane")"
    [ -n "$run" ] && signal_speech_pid "$(read_state "$run/speech.pid")" TERM
done
capture="$(capture_dir "$spool/recordings")"
[ -n "$capture" ] && signal_speech_pid "$(read_state "$capture/speech.pid")" TERM
/bin/rm -rf "$spool"

exit 0
