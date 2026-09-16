# speech.recordings.play - listen to the selected recording, or stop it when it is the one playing.
#
# The button plays and stops rather than playing and pausing. afplay is what a Mac ships to play a
# sound file from a script, and it can neither pause nor start part way in: stopping it and starting
# it again would begin at the top, so a pause would be a stop wearing the wrong icon. Nothing is
# played while the microphone is open, for Record here or for a session on the Live tab, or it
# would end up in what is being recorded or transcribed.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

# A double click sends the action twice, and the two handlers can run at once: without this the
# second would start a playback of its own, and the pid file would keep only one of them. The
# lock makes the second press a no-op rather than a second afplay.
/bin/mkdir "$pane/play.lock" 2>/dev/null
lock_status=$?
[ "$lock_status" -eq 0 ] || exit 0
trap '/bin/rmdir "$pane/play.lock" 2>/dev/null' EXIT

path="$(selected_recording_path "$pane")"
[ -n "$path" ] || exit 0

# Pressed on the recording that is playing: that is the stop.
playing="$(playing_path "$pane")"
if [ "$playing" = "$path" ]; then
    stop_playback "$pane"
    /bin/rm -f "$pane/actions.sig"
    refresh_recordings_actions "$pane"
    exit 0
fi

capture_is_active "$pane"
capturing=$?
if [ "$capturing" -eq 0 ]; then
    set_status "Stop the recording before playing one back, or the microphone will hear it."
    exit 0
fi
other_pane_is_busy "$pane"
live_busy=$?
if [ "$live_busy" -eq 0 ]; then
    set_status "Stop the live session before playing a recording back, or the microphone will hear it."
    exit 0
fi

if [ ! -f "$path" ]; then
    note_status "$pane" "$(missing_recording_note "$path")"
    exit 0
fi

start_playback "$pane" "$path"
started=$?
if [ "$started" -ne 0 ]; then
    note_status "$pane" "Could not play $(/usr/bin/basename "$path")."
    exit 0
fi

/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
