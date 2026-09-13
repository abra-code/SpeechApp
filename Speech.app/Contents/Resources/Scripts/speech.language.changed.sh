# speech.language.changed - the Language picker changed. The 1-based index is resolved against
# the spool's languages.tsv, which is in picker order. The saved preference is a language tag,
# never an index, because the list differs from one model to the next.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

spool="$(spool_dir_for "$window_uuid")"
[ -n "$window_uuid" ] && [ -d "$spool" ] || exit 0

quiet_active "$spool"
quiet=$?
[ "$quiet" -eq 0 ] && exit 0

index="${OMC_ACTIONUI_VIEW_26_VALUE:-}"
case "$index" in ''|*[!0-9]*) exit 0 ;; esac
tag="$(/usr/bin/sed -n "${index}p" "$spool/languages.tsv" 2>/dev/null | /usr/bin/cut -f1)"
[ -n "$tag" ] || exit 0
[ "$tag" = "$(read_state "$spool/language.tag")" ] && exit 0

write_state "$spool/language.tag" "$tag"
setting_set language "$tag"

exit 0
