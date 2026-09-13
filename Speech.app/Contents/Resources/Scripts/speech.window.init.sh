# speech.window.init - runs before the window appears. Creates the window's spool, takes over a
# recording handed to this window by Speech.main, File > Open or the Services menu, and starts
# the poller. The model list is the poller's first job rather than this script's: reading the
# catalog takes a second or two, and the window should not wait for it.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
/bin/mkdir -p "$spool"
mkdir_status=$?
if [ "$mkdir_status" -ne 0 ]; then
    set_status "Could not create $spool"
    exit 1
fi

disable_ctrl "$TRANSCRIBE_BTN"
disable_ctrl "$STOP_BTN"
disable_ctrl "$EXPORT_MENU"
disable_ctrl "$COPY_BTN"
disable_ctrl "$MODEL_PICKER"
disable_ctrl "$LANGUAGE_PICKER"
set_status "Reading the model list..."

# Consume the handoff before acting on it, so a failed or repeated open cannot pick it up twice.
handoff="$(pb_get "$PB_OPEN_PATH")"
pb_set "$PB_OPEN_PATH" ""
if [ -n "$handoff" ] && [ -f "$handoff" ]; then
    set_source "$spool" "$handoff"
fi

/bin/sh "$POLL_SCRIPT" "$window_uuid" "$spool" < /dev/null > "$spool/poll.log" 2>&1 &

exit 0
