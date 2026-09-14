# speech.models.info - a card's information button. Presents the information sheet
# (speech.model.info.json) with the model's catalog details and its family's page. The sheet's
# views join the window's pool when it is presented, so its text is set right after.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
row="$(card_row_of "${OMC_ACTIONUI_TRIGGER_VIEW_ID:-}")"
[ -n "$row" ] || exit 0
id="$(card_field "$spool" "$row" 1)"
[ -n "$id" ] || exit 0

markdown="$(model_info_markdown "$spool" "$row")"
"$dialog" "$window_uuid" omc_window omc_present_modal "speech.model.info"
"$dialog" "$window_uuid" "$MODEL_INFO_TEXT" markdown "$markdown"

exit 0
