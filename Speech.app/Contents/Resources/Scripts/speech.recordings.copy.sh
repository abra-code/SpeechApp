# speech.recordings.copy - copy the selected recording's transcript, as shown in the window, to the
# clipboard.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings
selected="$(read_state "$pane/selected.key")"
[ -n "$selected" ] && [ -s "$pane/items/$selected/transcript.txt" ] || exit 0

"$pasteboard" general set "$(/bin/cat "$pane/items/$selected/transcript.txt")"
copy_status=$?
if [ "$copy_status" -ne 0 ]; then
    set_status "Could not copy the transcript."
    exit 0
fi
set_status "Copied the transcript."

exit 0
