# speech.transcript.size.changed - the size picker of the Live or the Recordings tab changed. Both
# transcripts take the new size, the other tab's picker follows, and the size is kept for the next
# window. A pick of the size the window already has changes nothing.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
[ -d "$spool" ] || exit 0

case "${OMC_ACTIONUI_TRIGGER_VIEW_ID:-}" in
    "$LIVE_SIZE_PICKER") picked="${OMC_ACTIONUI_VIEW_56_VALUE:-}" ;;
    "$REC_SIZE_PICKER") picked="${OMC_ACTIONUI_VIEW_157_VALUE:-}" ;;
    *) exit 0 ;;
esac
size="$(transcript_size_at "$picked")"
[ -n "$size" ] || exit 0
[ "$size" = "$(read_state "$spool/transcript.size")" ] && exit 0

apply_transcript_size "$spool" "$size"
setting_set transcript.size "$size"

exit 0
