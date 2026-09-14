# speech.export.txt - the Live tab's Export > Plain Text. The Save panel has already run (SAVE_AS_DIALOG).
. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"
use_pane live
export_transcript txt "$(current_run_dir "$(pane_dir_for "$window_uuid" live)")"
exit 0
