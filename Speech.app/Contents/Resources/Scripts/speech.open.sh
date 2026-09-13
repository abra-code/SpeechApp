# speech.open - Choose File... in the window, and File > Open. Runs after the CHOOSE_FILE_DIALOG
# (audio and movie types) has set OMC_DLG_CHOOSE_FILE_PATH; a canceled panel leaves it empty.
#
# From a window's button the recording loads into that window. From the menu with no window to
# load into, it opens a window of its own.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

chosen="${OMC_DLG_CHOOSE_FILE_PATH:-}"
[ -n "$chosen" ] && [ -f "$chosen" ] || exit 0

spool="$(spool_dir_for "$window_uuid")"
if [ -z "$window_uuid" ] || [ ! -d "$spool" ]; then
    route_file "$chosen"
    exit 0
fi

run_is_active "$spool"
active=$?
if [ "$active" -eq 0 ]; then
    set_status "Stop the current transcription before choosing another recording."
    exit 0
fi

set_source "$spool" "$chosen"
refresh_actions "$spool"

exit 0
