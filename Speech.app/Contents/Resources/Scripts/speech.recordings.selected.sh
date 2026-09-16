# speech.recordings.selected - the selection in the recordings table changed. The table keeps each
# recording's path in a hidden third column. The selected recording's last transcript in this
# window, if it has one, is shown beside the list.
#
# Replacing the table's rows can report an empty selection that no one made. Inside the quiet
# window that follows a programmatic update, an empty selection is taken for that echo and
# ignored; a real selection is always taken.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

path="${OMC_ACTIONUI_TABLE_160_COLUMN_3_VALUE:-}"
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
else
    key="$(item_key "$path")"
    write_state "$pane/selected.key" "$key"
    show_transcript_file "$pane/items/$key/transcript.txt"
fi

# Playing follows the selection, so the play button always means the row the user is looking at and
# nothing goes on sounding out of a row no one can see. Re-selecting the recording that is playing,
# which is what the table's own refresh does every tick, leaves it alone.
playing="$(playing_path "$pane")"
[ -n "$playing" ] && [ "$playing" != "$path" ] && stop_playback "$pane"

/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
