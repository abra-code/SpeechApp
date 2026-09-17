# speech.live - start transcribing the microphone live with the Live tab's model and language.
# The handler only starts `speech stream` and its stdin holder; the poller reads the session's
# events into the window. While the session runs, the same button reads Stop, and pressed ends it
# (request_live_stop in lib.speech.sh).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" live)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane live

# While a session runs, Live is its Stop button, from when run_can_stop says. Before that a press
# starts nothing, so a double click cannot start a session and stop it at once.
run_can_stop "$(current_run_dir "$pane")"
stoppable=$?
if [ "$stoppable" -eq 0 ]; then
    request_live_stop "$pane"
    exit 0
fi

# A button press and a disabled button arriving late are two ways in. The lock makes a second
# press a no-op rather than a second session.
/bin/mkdir "$pane/dispatch.lock" 2>/dev/null
lock_status=$?
[ "$lock_status" -eq 0 ] || exit 0
trap '/bin/rmdir "$pane/dispatch.lock" 2>/dev/null' EXIT

run_is_active "$pane"
active=$?
[ "$active" -eq 0 ] && exit 0
other_pane_is_busy "$pane"
other_busy=$?
if [ "$other_busy" -eq 0 ]; then
    capture_is_active "$(spool_dir_for "$window_uuid")/recordings"
    recording=$?
    if [ "$recording" -eq 0 ]; then
        set_status "A recording is being made in the Recordings tab. Live is available when it is done."
    else
        set_status "Recordings are being transcribed. Live is available when they are done."
    fi
    exit 0
fi

model="$(read_state "$pane/model.id")"
if [ -z "$model" ]; then
    set_status "No speech model on this Mac can transcribe live yet."
    exit 0
fi
label="$(tsv_field "$pane/models.tsv" "$model" 2)"
[ -n "$label" ] || label="$model"
model_is_live "$pane" "$model"
live=$?
if [ "$live" -ne 0 ]; then
    set_status "$label cannot transcribe live. Choose a model that can."
    exit 0
fi
language="$(read_state "$pane/language.tag")"

# Whatever the Recordings tab's preview was playing stops before the microphone opens, or the
# session would transcribe it.
stop_recording_preview "$(spool_dir_for "$window_uuid")/recordings"

run="$(new_run_dir "$pane")"
if [ -z "$run" ]; then
    set_status "Could not create a working directory in $pane"
    exit 1
fi
: > "$run/segments.tsv"
write_state "$run/kind" live
write_state "$run/model" "$model"
write_state "$run/language" "$language"
write_state "$run/state" running

show_transcript_file ""
pid="$(spawn_stream "$run" "$model" "$language")"
if [ -z "$pid" ]; then
    write_state "$run/error.txt" "Could not create the live session's input in $run."
    write_state "$run/state" failed
    activate_run_dir "$pane" "$run"
    /bin/rm -f "$pane/actions.sig"
    exit 0
fi
write_state "$run/speech.pid" "$pid"
# The card's first words go in before the run is current: once it is, the poller may have consumed
# engine.ready and written a newer status, which a later write here would put back.
write_state "$run/progress.text" "Loading $label..."
# The run becomes current only once its pid is on disk: the poller settles a running run whose
# process it cannot find as failed.
activate_run_dir "$pane" "$run"

set_status "Loading $label..."
refresh_live_card "$pane"
/bin/rm -f "$pane/actions.sig"
refresh_live_actions "$pane"

exit 0
