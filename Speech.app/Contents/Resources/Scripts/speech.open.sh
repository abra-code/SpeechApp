# speech.open - the Recordings tab's add button, and File > Open. Runs after the
# CHOOSE_FILE_DIALOG (audio and movie types, several at once) has set OMC_DLG_CHOOSE_FILE_PATH,
# one path per line; a canceled panel leaves it empty.
#
# From a window the recordings join that window's list. From the menu with no window to add to,
# they open a window of their own.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

chosen="${OMC_DLG_CHOOSE_FILE_PATH:-}"
[ -n "$chosen" ] || exit 0

pane="$(pane_dir_for "$window_uuid" recordings)"
if [ -z "$window_uuid" ] || [ ! -d "$pane" ]; then
    route_files "$chosen"
    exit 0
fi

use_pane recordings
added="$(add_recordings "$pane" "$chosen")"
render_recordings_table "$pane"
"$dialog" "$window_uuid" "$TAB_VIEW" "$TAB_INDEX_RECORDINGS"
/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"
[ "${added:-0}" -gt 0 ] || set_status "Nothing was added: those recordings are already in the list, or are no longer there."

exit 0
