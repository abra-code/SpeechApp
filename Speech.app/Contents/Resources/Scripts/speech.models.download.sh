# speech.models.download - a card's Download or Resume button. Starts the download worker for that
# model (speech.download.worker.sh), detached, so the download goes on when this window closes.
# The card shows the progress from the next tick of the Models window's poller.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
row="$(card_row_of "${OMC_ACTIONUI_TRIGGER_VIEW_ID:-}")"
[ -n "$row" ] || exit 0
id="$(card_field "$spool" "$row" 1)"
[ -n "$id" ] || exit 0
can_download="$(card_field "$spool" "$row" 10)"
[ "$can_download" = 1 ] || exit 0

dir="$(download_dir_for "$id")"
/bin/mkdir -p "$dir"
mkdir_status=$?
if [ "$mkdir_status" -ne 0 ]; then
    set_models_status "Could not create $dir"
    exit 1
fi

# One download per model: a second click, or the same click in a second Models window, finds the
# lock or the running worker and does nothing.
/bin/mkdir "$dir/dispatch.lock" 2>/dev/null
lock_status=$?
[ "$lock_status" -eq 0 ] || exit 0
trap '/bin/rmdir "$dir/dispatch.lock" 2>/dev/null' EXIT
download_worker_alive "$dir"
alive_status=$?
[ "$alive_status" -eq 0 ] && exit 0

/bin/rm -f "$dir/state" "$dir/message" "$dir/events.jsonl" "$dir/stderr.log" "$dir/speech.pid" "$dir/worker.pid"
write_state "$dir/id" "$id"
write_state "$dir/state" running
/bin/sh "$DOWNLOAD_WORKER_SCRIPT" "$id" "$dir" < /dev/null > /dev/null 2>&1 &
write_state "$dir/worker.pid" "$!"

text="Starting the download..."
push_card "$row" "$text" 0 0
write_state "$spool/card.$row.sig" "$text|0|0"

exit 0
