# speech.recordings.transcribe - transcribe every recording in the list, one after another, with
# the Recordings tab's model and language. The handler only queues the batch; the poller starts
# each recording, saves its transcript beside it and moves on (advance_batch in lib.speech.sh).
# Starting the first recording is the poller's job too, so there is only ever one place that
# starts one.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

# The button and its Command-Return shortcut are two ways in, and disabling the button is not
# instant. The lock makes a second press a no-op rather than a second batch.
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
    set_status "A live session is running. Stop it to transcribe recordings."
    exit 0
fi

count="$(recording_count "$pane")"
if [ "$count" = 0 ]; then
    set_status "Drop recordings here or add them, then press Transcribe."
    exit 0
fi
model="$(read_state "$pane/model.id")"
if [ -z "$model" ]; then
    set_status "No speech model can run on this Mac yet."
    exit 0
fi

start_batch "$pane"
show_transcript_file ""
render_recordings_table "$pane"
set_status "Starting $(tsv_field "$pane/models.tsv" "$model" 2)..."
/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
