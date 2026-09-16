# speech.recordings.trash - the trash button under the recordings list. This is the one button in
# the tab that touches the file itself, so it asks first; the alert's own button runs
# speech.recordings.trash.confirm. Alert buttons carry no context of their own, so the recording
# asked about waits in the pane's pending.trash.
#
# Taking a recording out of the list is the minus button's job and needs no asking, since nothing
# is lost by it.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

pane_is_busy "$pane"
busy=$?
if [ "$busy" -eq 0 ]; then
    set_status "Stop the transcription before moving a recording to the Trash."
    exit 0
fi

path="$(selected_recording_path "$pane")"
[ -n "$path" ] || exit 0

if [ ! -e "$path" ]; then
    note_status "$pane" "$(missing_recording_note "$path")"
    exit 0
fi
if [ -L "$path" ]; then
    note_status "$pane" "$(linked_recording_note "$path")"
    exit 0
fi

write_state "$pane/pending.trash" "$path"
"$dialog" "$window_uuid" omc_window omc_present_alert \
    "Move \"$(/usr/bin/basename "$path")\" to the Trash?" \
    "It leaves the list with it. Any transcript saved beside it stays where it is, and you can put the recording back from the Trash." \
    "Cancel:cancel:" "Move to Trash:destructive:speech.recordings.trash.confirm"

exit 0
