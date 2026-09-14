# speech.recordings.export.srt - the Recordings tab's Export > SRT Subtitles, for the selected recording. The Save panel has already run (SAVE_AS_DIALOG).
. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"
use_pane recordings
pane="$(pane_dir_for "$window_uuid" recordings)"
selected="$(read_state "$pane/selected.key")"
[ -n "$selected" ] && export_transcript srt "$pane/items/$selected"
exit 0
