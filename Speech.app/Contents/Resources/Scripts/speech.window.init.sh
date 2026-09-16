# speech.window.init - runs before the window appears. Creates the window's spool, takes over the
# recordings handed to this window by Speech.main, File > Open or the Services menu, and starts
# the poller. The model lists are the poller's first job rather than this script's: reading the
# catalog takes a second or two, and the window should not wait for it.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
/bin/mkdir -p "$spool/live" "$spool/recordings" "$spool/benchmark"
mkdir_status=$?
if [ "$mkdir_status" -ne 0 ]; then
    use_pane live
    set_status "Could not create $spool"
    exit 1
fi
: >> "$spool/recordings/list.tsv"
# The app that owns this spool, so the next launch can remove it if this app is killed.
write_state "$spool/app.pid" "${OMC_APP_PROCESS_ID:-}"

for control in "$LIVE_BTN" "$LIVE_STOP_BTN" "$LIVE_EXPORT_MENU" "$LIVE_COPY_BTN" "$LIVE_MODEL_PICKER" "$LIVE_LANGUAGE_PICKER" \
    "$REC_TRANSCRIBE_BTN" "$REC_STOP_BTN" "$REC_EXPORT_MENU" "$REC_COPY_BTN" "$REC_REMOVE_BTN" "$REC_MODEL_PICKER" "$REC_LANGUAGE_PICKER" \
    "$BENCH_CORPUS_PICKER" "$BENCH_SAMPLE_PICKER" "$BENCH_MODEL_PICKER" "$BENCH_ADD_BTN" "$BENCH_RUN_BTN" "$BENCH_STOP_BTN" "$BENCH_REMOVE_BTN"; do
    disable_ctrl "$control"
done
for pane in live recordings benchmark; do
    use_pane "$pane"
    set_status "Reading the model list..."
done

# Consume the handoff before acting on it, so a failed or repeated open cannot pick it up twice.
handoff="$(pb_get "$PB_OPEN_PATH")"
pb_set "$PB_OPEN_PATH" ""
if [ -n "$handoff" ]; then
    use_pane recordings
    added="$(add_recordings "$spool/recordings" "$handoff")"
    if [ "${added:-0}" -gt 0 ]; then
        render_recordings_table "$spool/recordings"
        "$dialog" "$window_uuid" "$TAB_VIEW" "$TAB_INDEX_RECORDINGS"
    fi
fi

/bin/sh "$POLL_SCRIPT" "$window_uuid" "$spool" < /dev/null > "$spool/poll.log" 2>&1 &

exit 0
