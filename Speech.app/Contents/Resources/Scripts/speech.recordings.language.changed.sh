# speech.recordings.language.changed - the Recordings tab's Language picker changed
# (handle_language_changed in lib.speech.sh).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

handle_language_changed "$pane" "${OMC_ACTIONUI_VIEW_126_VALUE:-}"

exit 0
