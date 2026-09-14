# speech.models.delete - a card's trash button. Asks before deleting; the alert's Delete button
# runs speech.models.delete.confirm. Alert buttons carry no context of their own, so the model
# asked about waits in the spool's pending.delete.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
row="$(card_row_of "${OMC_ACTIONUI_TRIGGER_VIEW_ID:-}")"
[ -n "$row" ] || exit 0
id="$(card_field "$spool" "$row" 1)"
[ -n "$id" ] || exit 0
can_delete="$(card_field "$spool" "$row" 11)"
[ "$can_delete" = 1 ] || exit 0

refusal="$(delete_refusal "$spool" "$row")"
if [ -n "$refusal" ]; then
    set_models_status "$refusal"
    exit 0
fi

write_state "$spool/pending.delete" "$id"
label="$(card_field "$spool" "$row" 3)"
size="$(card_field "$spool" "$row" 12)"
if [ -n "$size" ]; then
    message="This removes $size from this Mac. You can download it again later."
else
    message="You can download it again later."
fi
"$dialog" "$window_uuid" omc_window omc_present_alert "Delete $label?" "$message" \
    "Cancel:cancel:" "Delete:destructive:speech.models.delete.confirm"

exit 0
