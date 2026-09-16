# speech.recordings.reveal - show the selected recording in the Finder. Nothing here changes the
# list or the file; a recording that has been moved or deleted since it was listed says so rather
# than opening a Finder window on nothing.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

path="$(selected_recording_path "$pane")"
[ -n "$path" ] || exit 0

if [ ! -e "$path" ]; then
    note_status "$pane" "$(missing_recording_note "$path")"
    exit 0
fi

"$OPEN_BIN" -R "$path"

exit 0
