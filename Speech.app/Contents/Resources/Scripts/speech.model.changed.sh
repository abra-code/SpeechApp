# speech.model.changed - the Model picker changed. The picker delivers a 1-based index, resolved
# against the spool's models.tsv, which is in picker order. A change inside the quiet window is
# the echo of a programmatic update and is ignored, as is an index that resolves to nothing.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

spool="$(spool_dir_for "$window_uuid")"
[ -n "$window_uuid" ] && [ -d "$spool" ] || exit 0

quiet_active "$spool"
quiet=$?
[ "$quiet" -eq 0 ] && exit 0

index="${OMC_ACTIONUI_VIEW_25_VALUE:-}"
case "$index" in ''|*[!0-9]*) exit 0 ;; esac
model="$(/usr/bin/sed -n "${index}p" "$spool/models.tsv" 2>/dev/null | /usr/bin/cut -f1)"
[ -n "$model" ] || exit 0
[ "$model" = "$(read_state "$spool/model.id")" ] && exit 0

# The picker is disabled while a run is active; a change that arrives anyway waits for it.
run_is_active "$spool"
active=$?
[ "$active" -eq 0 ] && exit 0

write_state "$spool/model.id" "$model"
setting_set model "$model"
populate_language_picker "$spool"
/bin/rm -f "$spool/actions.sig"
refresh_actions "$spool"

exit 0
