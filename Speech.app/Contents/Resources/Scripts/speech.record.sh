# speech.record - record a new sound file from the microphone, into the recordings folder
# (~/Documents/Speech Recordings). The handler only starts `speech record` and its stdin holder;
# the poller shows the elapsed time and the microphone while it runs, and when it ends adds the file
# to the list, ready to transcribe. Stop, or Record pressed again, ends it with "q", which keeps
# everything recorded.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

# While recording, Record is the Stop button, from when capture_can_stop says. Before that it starts
# nothing, so a double click cannot start a recording and stop it at once.
capture_can_stop "$(capture_dir "$pane")"
stoppable=$?
if [ "$stoppable" -eq 0 ]; then
    request_capture_stop "$pane"
    stopped=$?
    [ "$stopped" -eq 0 ] && exit 0
fi

# Shared with Transcribe: one thing at a time in the tab, whichever button started it.
/bin/mkdir "$pane/dispatch.lock" 2>/dev/null
lock_status=$?
[ "$lock_status" -eq 0 ] || exit 0
trap '/bin/rmdir "$pane/dispatch.lock" 2>/dev/null' EXIT

pane_is_busy "$pane"
busy=$?
[ "$busy" -eq 0 ] && exit 0
other_pane_is_busy "$pane"
other_busy=$?
if [ "$other_busy" -eq 0 ]; then
    set_status "A live session is running. Stop it to record."
    exit 0
fi

# Whatever was playing stops before the microphone opens, or it would be in the new recording.
stop_playback "$pane"

/bin/mkdir -p "$RECORDINGS_DIR"
mkdir_status=$?
if [ "$mkdir_status" -ne 0 ] || [ ! -d "$RECORDINGS_DIR" ]; then
    set_status "Could not create the recordings folder, $RECORDINGS_DIR."
    exit 0
fi
stamp="$(/bin/date '+%Y-%m-%d at %H.%M.%S')"
output="$(recording_path_for "$RECORDINGS_DIR" "$stamp")"

now="$(/bin/date +%s)"
name="capture-$now-$$"
dir="$pane/$name"
/bin/mkdir -p "$dir"
mkdir_status=$?
if [ "$mkdir_status" -ne 0 ]; then
    set_status "Could not create a working directory in $pane"
    exit 1
fi
write_state "$dir/kind" record
write_state "$dir/output.path" "$output"
write_state "$dir/state" running

pid="$(spawn_record "$dir" "$output")"
if [ -z "$pid" ]; then
    write_state "$dir/error.txt" "Could not create the recording's input in $dir."
    write_state "$dir/state" failed
else
    write_state "$dir/speech.pid" "$pid"
fi
# The recording becomes the tab's capture only once its pid is on disk: the poller settles a
# running capture whose process it cannot find as failed.
write_state "$pane/capture" "$name"
for old in "$pane"/capture-*; do
    [ -d "$old" ] || continue
    [ "$old" = "$dir" ] && continue
    /bin/rm -rf "$old"
done

/bin/rm -f "$pane/status.note"
"$dialog" "$window_uuid" "$REC_CLOCK" "0:00"
set_status "Starting the microphone..."
/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
