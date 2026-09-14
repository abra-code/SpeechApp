# speech.models.delete.confirm - the Delete button of the delete alert. Deletes the model named in
# pending.delete with `speech models delete`, after checking again that nothing started using or
# downloading it while the alert was open, then tells every window to read the catalog again.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
id="$(read_state "$spool/pending.delete")"
/bin/rm -f "$spool/pending.delete"
[ -n "$id" ] || exit 0
row="$(row_of_id "$spool" "$id")"
[ -n "$row" ] || exit 0
can_delete="$(card_field "$spool" "$row" 11)"
[ "$can_delete" = 1 ] || exit 0

refusal="$(delete_refusal "$spool" "$row")"
if [ -n "$refusal" ]; then
    set_models_status "$refusal"
    exit 0
fi

label="$(card_field "$spool" "$row" 3)"
"$SPEECH_BIN" --json models delete "$id" > "$spool/delete.out" 2> "$spool/delete.err"
delete_status=$?
if [ "$delete_status" -ne 0 ]; then
    reason="$(/usr/bin/head -1 "$spool/delete.err" 2>/dev/null)"
    set_models_status "Could not delete $label: ${reason:-speech did not say why.}"
    exit 1
fi

# A failed download's directory held only the reason it failed, which no longer applies.
/bin/rm -rf "$(download_dir_for "$id")"
bump_models_stamp
set_models_status "Deleted $label."

exit 0
