# speech.export.json - the Live tab's Export > JSON with Timings. The Save panel has already run (SAVE_AS_DIALOG).
. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"
use_pane live
export_transcript json "$(current_run_dir "$(pane_dir_for "$window_uuid" live)")"
exit 0
