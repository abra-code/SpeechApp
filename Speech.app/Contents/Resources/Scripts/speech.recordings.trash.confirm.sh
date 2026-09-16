# speech.recordings.trash.confirm - the Move to Trash button of the trash alert. Moves the recording
# named in pending.trash to the Trash through Finder, after checking again that nothing started
# using it while the alert stood open, and takes it out of the list.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

path="$(read_state "$pane/pending.trash")"
/bin/rm -f "$pane/pending.trash"
[ -n "$path" ] || exit 0

# The alert is not modal to the rest of the tab: a batch can have started, and the recording can
# have been taken out of the list, while it stood open.
pane_is_busy "$pane"
busy=$?
if [ "$busy" -eq 0 ]; then
    set_status "Stop the transcription before moving a recording to the Trash."
    exit 0
fi
/usr/bin/grep -Fxq -- "$path" "$pane/list.tsv" 2>/dev/null
listed=$?
[ "$listed" -eq 0 ] || exit 0

if [ ! -e "$path" ]; then
    note_status "$pane" "$(missing_recording_note "$path")"
    exit 0
fi
if [ -L "$path" ]; then
    note_status "$pane" "$(linked_recording_note "$path")"
    exit 0
fi

name="$(/usr/bin/basename "$path")"
playing="$(playing_path "$pane")"
[ "$playing" = "$path" ] && stop_playback "$pane"

trash_file "$path" "$pane/trash.err"
trash_status=$?
if [ "$trash_status" -ne 0 ]; then
    # Finder's own words, which say whether it was the file or the permission to control Finder.
    # osascript puts the script's path and the error's position in front of them
    # ("<script>:74:79: execution error: ..."), which mean nothing to the user and go.
    reason="$(/usr/bin/head -1 "$pane/trash.err" 2>/dev/null | /usr/bin/sed 's/^.*execution error: //')"
    note_status "$pane" "Could not move $name to the Trash: ${reason:-the Finder did not say why.}"
    exit 0
fi

remove_recording "$pane" "$path"
show_transcript_file ""
render_recordings_table "$pane"
"$dialog" "$window_uuid" "$REC_TABLE" omc_deselect
note_status "$pane" "Moved $name to the Trash."
/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
