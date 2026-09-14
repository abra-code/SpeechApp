# speech.language.changed - the Live tab's Language picker changed (handle_language_changed in
# lib.speech.sh).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" live)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane live

handle_language_changed "$pane" "${OMC_ACTIONUI_VIEW_26_VALUE:-}"

exit 0
