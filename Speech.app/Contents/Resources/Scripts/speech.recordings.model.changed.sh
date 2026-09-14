# speech.recordings.model.changed - the Recordings tab's Model picker changed
# (handle_model_changed in lib.speech.sh).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

handle_model_changed "$pane" "${OMC_ACTIONUI_VIEW_125_VALUE:-}"
refresh_recordings_actions "$pane"

exit 0
