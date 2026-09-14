# speech.copy - copy the live transcript, as shown in the window, to the clipboard.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" live)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane live
run="$(current_run_dir "$pane")"
[ -n "$run" ] && [ -s "$run/transcript.txt" ] || exit 0

"$pasteboard" general set "$(/bin/cat "$run/transcript.txt")"
copy_status=$?
if [ "$copy_status" -ne 0 ]; then
    set_status "Could not copy the transcript."
    exit 0
fi
set_status "Copied the transcript."

exit 0
