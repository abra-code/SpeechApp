# speech.poll.sh - the window poller, one per open window. Not an OMC command: speech.window.init
# starts it with /bin/sh, and it runs until the window's spool directory disappears (window
# closed, app quit) or the app itself is gone.
#   args: <window_uuid> <spool_dir>
#
# The first thing it does is read the catalog, so the window can appear before that work is
# done. After that, each tick it reads the current run's new events into the segment table,
# re-renders the transcript when the table changed, settles a run whose process has exited, and
# brings every control's enabled state in line with the spool.
#
# A SIGKILLed app runs no cleanup, so the poller watches the app's pid as well as the spool:
# without that, it would poll a spool nobody will ever remove, forever.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

window_uuid="$1"
spool="$2"
[ -n "$window_uuid" ] && [ -d "$spool" ] || exit 0
app_pid="${OMC_APP_PROCESS_ID:-}"

load_models "$spool"
load_status=$?
if [ "$load_status" -ne 0 ]; then
    reason="$(/usr/bin/head -3 "$spool/catalog.err" 2>/dev/null)"
    set_status "Could not read the model catalog: ${reason:-speech did not answer}"
    present_alert "Could not read the model catalog" "${reason:-The speech tool inside Speech.app did not answer. Reinstalling the app may help.}"
    exit 1
fi
populate_model_picker "$spool"

while [ -d "$spool" ]; do
    if [ -n "$app_pid" ]; then
        pid_alive "$app_pid"
        app_status=$?
        [ "$app_status" -eq 0 ] || break
    fi
    run="$(current_run_dir "$spool")"
    if [ -n "$run" ]; then
        process_events "$spool"
        changed=$?
        [ "$changed" -eq 0 ] && render_transcript "$spool"
        finish_if_exited "$spool"
        reflect_run_end "$spool"
    fi
    refresh_actions "$spool"
    /bin/sleep 0.5
done

exit 0
