# speech.model.changed - the Live tab's Model picker changed (handle_model_changed in
# lib.speech.sh).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" live)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane live

handle_model_changed "$pane" "${OMC_ACTIONUI_VIEW_25_VALUE:-}"
refresh_live_actions "$pane"

exit 0
