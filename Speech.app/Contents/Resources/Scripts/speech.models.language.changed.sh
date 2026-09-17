# speech.models.language.changed - the Models window's "Best for" language picker changed
# (handle_suggest_language_changed in lib.speech.models.sh).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
[ -d "$spool/suggest" ] || exit 0

handle_suggest_language_changed "$spool" "${OMC_ACTIONUI_VIEW_1010_VALUE:-}"

exit 0
