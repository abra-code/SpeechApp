# speech.recordings.export.txt - the Recordings tab's Export > Plain Text, for the selected recording. The Save panel has already run (SAVE_AS_DIALOG).
. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"
use_pane recordings
pane="$(pane_dir_for "$window_uuid" recordings)"
selected="$(read_state "$pane/selected.key")"
[ -n "$selected" ] && export_transcript txt "$pane/items/$selected"
exit 0
