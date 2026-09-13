# speech.transcribe - start transcribing the window's recording with the selected model and
# language. The handler only starts the process; the poller reads its events into the window.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

spool="$(spool_dir_for "$window_uuid")"
[ -n "$window_uuid" ] && [ -d "$spool" ] || exit 0

# The button and its Command-Return shortcut are two ways in, and disabling the button is not
# instant. The lock makes a second press a no-op rather than a second process.
/bin/mkdir "$spool/dispatch.lock" 2>/dev/null
lock_status=$?
[ "$lock_status" -eq 0 ] || exit 0
trap '/bin/rmdir "$spool/dispatch.lock" 2>/dev/null' EXIT

run_is_active "$spool"
active=$?
[ "$active" -eq 0 ] && exit 0

source_path="$(read_state "$spool/source.path")"
if [ -z "$source_path" ] || [ ! -f "$source_path" ]; then
    set_status "Choose or drop a recording to transcribe."
    exit 0
fi
model="$(read_state "$spool/model.id")"
if [ -z "$model" ]; then
    set_status "No speech model can run on this Mac yet."
    exit 0
fi
language="$(read_state "$spool/language.tag")"

run="$(new_run_dir "$spool")"
if [ -z "$run" ]; then
    set_status "Could not create a working directory in $spool"
    exit 1
fi
: > "$run/segments.tsv"
write_state "$run/state" running

printf '' | "$dialog" "$window_uuid" "$TRANSCRIPT_EDITOR" omc_set_value_from_stdin plain
pid="$(spawn_transcribe "$run" "$source_path" "$model" "$language")"
write_state "$run/speech.pid" "$pid"
# The run becomes current only once its pid is on disk. The poller settles a running run whose
# process it cannot find as failed, and a tick can land between the two writes.
activate_run_dir "$spool" "$run"

set_status "Starting $(tsv_field "$spool/models.tsv" "$model" 2)..."
/bin/rm -f "$spool/actions.sig"
refresh_actions "$spool"

exit 0
