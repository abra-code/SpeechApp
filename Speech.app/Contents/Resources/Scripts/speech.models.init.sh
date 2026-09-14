# speech.models.init - runs before the Models window appears. Creates the window's spool and starts
# its poller, which reads the catalog and builds the cards, so the window does not wait for that.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
/bin/mkdir -p "$spool"
mkdir_status=$?
if [ "$mkdir_status" -ne 0 ]; then
    "$dialog" "$window_uuid" "$MODELS_STATUS" "Could not create $spool"
    exit 1
fi
write_state "$spool/kind" models
"$dialog" "$window_uuid" "$MODELS_STATUS" "Reading the model list..."

/bin/sh "$MODELS_POLL_SCRIPT" "$window_uuid" "$spool" < /dev/null > "$spool/poll.log" 2>&1 &

exit 0
