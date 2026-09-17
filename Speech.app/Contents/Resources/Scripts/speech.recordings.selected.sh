# speech.recordings.selected - the selection in the recordings table changed. The table keeps each
# recording's path in a hidden fourth column. The selected recording's last transcript in this
# window, if it has one, is shown beside the list, and what its Status stands for in the status line.
#
# Replacing the table's rows can report an empty selection that no one made. Inside the quiet
# window that follows a programmatic update, an empty selection is taken for that echo and
# ignored; a real selection is always taken.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

path="${OMC_ACTIONUI_TABLE_160_COLUMN_4_VALUE:-}"
if [ -n "$path" ]; then
    /usr/bin/grep -Fxq -- "$path" "$pane/list.tsv" 2>/dev/null
    listed=$?
    [ "$listed" -eq 0 ] || path=""
fi

if [ -z "$path" ]; then
    quiet_active "$pane" table
    quiet=$?
    [ "$quiet" -eq 0 ] && exit 0
    /bin/rm -f "$pane/selected.key"
    show_transcript_file ""
    show_recording_detail "$pane" ""
else
    key="$(item_key "$path")"
    previous="$(read_state "$pane/selected.key")"
    write_state "$pane/selected.key" "$key"
    show_transcript_file "$pane/items/$key/transcript.txt"
    # The Status column keeps to a word or two; choosing a recording says the rest. Only a new
    # choice does: the table's own refresh re-selects the same row every time its rows change, and
    # would otherwise put this over the progress of a batch.
    [ "$key" != "$previous" ] && show_recording_detail "$pane" "$path"
fi

# Playing follows the selection, so the play button always means the row the user is looking at and
# nothing goes on sounding out of a row no one can see. Re-selecting the recording that is playing,
# which is what the table's own refresh does every tick, leaves it alone.
playing="$(playing_path "$pane")"
[ -n "$playing" ] && [ "$playing" != "$path" ] && stop_playback "$pane"

/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
