# speech.recordings.export.json - the Recordings tab's Export > JSON with Timings, for the selected recording or, with Join on, every recording in the list. The Save panel has already run (SAVE_AS_DIALOG).
. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"
use_pane recordings
pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
export_recordings json "$pane"
exit 0
