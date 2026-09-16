# speech.recordings.remove - take the selected recording out of the list. The recording itself,
# and any transcript saved beside it, stay where they are. Not while a batch is running: the list
# is what the batch reports on.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

pane_is_busy "$pane"
busy=$?
if [ "$busy" -eq 0 ]; then
    set_status "Stop the transcription before removing a recording from the list."
    exit 0
fi

path="$(selected_recording_path "$pane")"
[ -n "$path" ] || exit 0

# A recording no longer in the list has no button left to stop it with.
playing="$(playing_path "$pane")"
[ "$playing" = "$path" ] && stop_playback "$pane"

remove_recording "$pane" "$path"
show_transcript_file ""
render_recordings_table "$pane"
"$dialog" "$window_uuid" "$REC_TABLE" omc_deselect
/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
