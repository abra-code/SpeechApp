# speech.record - start transcribing the microphone live with the selected model and language.
# The handler only starts `speech stream` and its stdin holder; the poller reads the session's
# events into the window, and Stop ends it.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

spool="$(spool_dir_for "$window_uuid")"
[ -n "$window_uuid" ] && [ -d "$spool" ] || exit 0

# Shared with Transcribe: one run per window, whichever button started it.
/bin/mkdir "$spool/dispatch.lock" 2>/dev/null
lock_status=$?
[ "$lock_status" -eq 0 ] || exit 0
trap '/bin/rmdir "$spool/dispatch.lock" 2>/dev/null' EXIT

run_is_active "$spool"
active=$?
[ "$active" -eq 0 ] && exit 0

model="$(read_state "$spool/model.id")"
if [ -z "$model" ]; then
    set_status "No speech model can run on this Mac yet."
    exit 0
fi
label="$(tsv_field "$spool/models.tsv" "$model" 2)"
model_is_live "$spool" "$model"
live=$?
if [ "$live" -ne 0 ]; then
    set_status "$label cannot transcribe live. Choose a model that can."
    exit 0
fi
language="$(read_state "$spool/language.tag")"

run="$(new_run_dir "$spool")"
if [ -z "$run" ]; then
    set_status "Could not create a working directory in $spool"
    exit 1
fi
: > "$run/segments.tsv"
write_state "$run/kind" live
write_state "$run/model" "$model"
write_state "$run/language" "$language"
write_state "$run/state" running

printf '' | "$dialog" "$window_uuid" "$TRANSCRIPT_EDITOR" omc_set_value_from_stdin plain
pid="$(spawn_stream "$run" "$model" "$language")"
if [ -z "$pid" ]; then
    write_state "$run/error.txt" "Could not create the live session's input in $run."
    write_state "$run/state" failed
    activate_run_dir "$spool" "$run"
    /bin/rm -f "$spool/actions.sig"
    exit 0
fi
write_state "$run/speech.pid" "$pid"
# The run becomes current only once its pid is on disk: the poller settles a running run whose
# process it cannot find as failed.
activate_run_dir "$spool" "$run"

set_status "Starting the microphone with $label..."
/bin/rm -f "$spool/actions.sig"
refresh_actions "$spool"

exit 0
