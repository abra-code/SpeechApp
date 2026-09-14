#!/bin/sh
# 30-record.test.sh - Record in the Recordings tab: `speech record` into a new file in the
# recordings folder, with the stdin holder; the level while it runs; Stop with "q"; the finished
# file joining the list, selected; a failure that leaves no file; and what Record waits for. The
# fake speech (helpers/fake-speech.sh) plays the recording; the real stdin holder runs.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

export SPEECH_RECORDINGS_DIR

open_window() {
    reset_state
    /bin/rm -rf "$SPEECH_RECORDINGS_DIR"
    omc_run speech.window.init
    load_window_models
    pane_call recordings refresh_recordings_actions "$(rec_pane)"
    pane_call live refresh_live_actions "$(live_pane)"
}

capture() {
    local _name="$(/bin/cat "$(rec_pane)/capture" 2>/dev/null)"
    [ -n "$_name" ] || return 0
    printf '%s' "$(rec_pane)/$_name"
}

# How many stdin holders are running for a run directory; see 20-live.test.sh.
holders_for() {
    /bin/ps -axo args= | /usr/bin/awk -v prefix="/bin/sh $OMCTEST_APP/Contents/Resources/Scripts/speech.live.stdin.sh $1 " \
        'index($0, prefix) == 1 { n++ } END { print n + 0 }'
}

stop_log="$FAKE_SPEECH_LOG.stop"

# ------------------------------------------------------------------------------------------------
section "Record is offered with no recording and no model needed, and the level is hidden"
open_window
check "Record is enabled" "1" "$(ui_enabled "$REC_RECORD_BTN")"
check "the level gauge is hidden" "0" "$(ui_visible "$REC_LEVEL")"
check "the status mentions Record" \
    "Drop recordings here or add them, or press Record, then Transcribe. Each transcript is saved beside its recording." \
    "$(ui_value "$REC_STATUS")"

section "Record starts speech record into a new file in the recordings folder, with its holder"
existing="$OMCTEST_WORK/existing.wav"
printf 'RIFF' > "$existing"
printf '%s\n' "$existing" > "$(rec_pane)/list.tsv"
pane_call recordings refresh_recordings_actions "$(rec_pane)"
check "with a recording listed, Transcribe is enabled before recording starts" "1" "$(ui_enabled "$REC_TRANSCRIBE_BTN")"
omc_table_cell "$REC_TABLE" 3 "$existing"
omc_run speech.recordings.selected
check "with it selected, Remove is enabled before recording starts" "1" "$(ui_enabled "$REC_REMOVE_BTN")"
check "and so is the model picker" "1" "$(ui_enabled "$REC_MODEL_PICKER")"
/bin/rm -f "$FAKE_SPEECH_LOG" "$stop_log"
omc_run speech.record
check_status "record exits cleanly" 0
check_exists "the recordings folder was created" "$SPEECH_RECORDINGS_DIR"
dir="$(capture)"
output="$(/bin/cat "$dir/output.path")"
case "$output" in
    "$SPEECH_RECORDINGS_DIR/Recording "*" at "*".m4a") named=yes ;;
    *) named=no ;;
esac
check "the file is named after the date and time, as m4a, in the recordings folder" "yes" "$named"
check "speech record was started for that file" "--json record $output" \
    "$(omc_wait_for "[ -s \"$FAKE_SPEECH_LOG\" ]" && /usr/bin/head -1 "$FAKE_SPEECH_LOG")"
check "its stdin is a FIFO" "yes" "$([ -p "$dir/stdin.fifo" ] && echo yes || echo no)"
check "one stdin holder is running for it" "1" "$(holders_for "$dir")"
check "Record is disabled while recording" "0" "$(ui_enabled "$REC_RECORD_BTN")"
check "Transcribe is disabled while recording" "0" "$(ui_enabled "$REC_TRANSCRIBE_BTN")"
# The model handler ignores a change while the pane is busy, so the picker must not offer one: an
# enabled picker would show the new choice while the pane kept the old.
check "the pickers are disabled while recording" "0|0" "$(ui_enabled "$REC_MODEL_PICKER")|$(ui_enabled "$REC_LANGUAGE_PICKER")"
check "Remove is disabled while recording" "0" "$(ui_enabled "$REC_REMOVE_BTN")"
check "Stop is enabled" "1" "$(ui_enabled "$REC_STOP_BTN")"
check "the level gauge is shown" "1" "$(ui_visible "$REC_LEVEL")"
omc_wait_for "/usr/bin/grep -q 'recording.level' \"$dir/events.jsonl\""
poll_tick
check "the status shows the file and the elapsed time" \
    "Recording $(/usr/bin/basename "$output")... 1:05" "$(ui_value "$REC_STATUS")"
check "the gauge shows the level: -30 dB is half way" "0.50" "$(ui_value "$REC_LEVEL")"

section "a recording keeps Live from starting, and says why"
pane_call live refresh_live_actions "$(live_pane)"
check "Live is disabled" "0" "$(ui_enabled "$LIVE_BTN")"
check "the Live status names the recording" \
    "A recording is being made in the Recordings tab. Live is available when it is done." "$(ui_value "$LIVE_STATUS")"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.live
check_absent "a Live that arrives anyway starts nothing" "$FAKE_SPEECH_LOG"

section "a second Record, or a Transcribe, while recording starts nothing"
omc_run speech.record
omc_run speech.recordings.transcribe
check_absent "speech was not started" "$FAKE_SPEECH_LOG"
check_absent "no batch was queued" "$(rec_pane)/batch"
check "the same recording is current" "$dir" "$(capture)"

# ------------------------------------------------------------------------------------------------
section "Stop sends q, the file is finished, and it joins the list, selected"
pid="$(/bin/cat "$dir/speech.pid")"
omc_run speech.recordings.stop
check "the recording is stopping" "stopping" "$(/bin/cat "$dir/state")"
check "speech was told with q" "q" "$(omc_wait_for "[ -s \"$stop_log\" ]" && /bin/cat "$stop_log")"
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"
poll_tick
check "the recording ended as done: q is a tidy stop" "done" "$(/bin/cat "$dir/state")"
check_exists "the file is there" "$output"
check "it is the last in the list" "$output" "$(/usr/bin/tail -1 "$(rec_pane)/list.tsv")"
check "and selected" "$(/sbin/md5 -q -s "$output")" "$(/bin/cat "$(rec_pane)/selected.key" 2>/dev/null)"
check "the table lists it" "$(/usr/bin/basename "$output")" "$(ui_rows "$REC_TABLE" | /usr/bin/awk -F'\t' -v p="$output" '$3 == p { print $1 }')"
check "the status says so" \
    "Recorded $(/usr/bin/basename "$output") (2.0 s). It is in the list, ready to transcribe." "$(ui_value "$REC_STATUS")"
check "the gauge is hidden again" "0" "$(ui_visible "$REC_LEVEL")"
check "Record is enabled again" "1" "$(ui_enabled "$REC_RECORD_BTN")"
check "Transcribe is enabled again" "1" "$(ui_enabled "$REC_TRANSCRIBE_BTN")"
poll_tick
check "a later tick keeps the note rather than the idle text" \
    "Recorded $(/usr/bin/basename "$output") (2.0 s). It is in the list, ready to transcribe." "$(ui_value "$REC_STATUS")"
check "the list was added to only once" "1" "$(/usr/bin/grep -Fxc "$output" "$(rec_pane)/list.tsv")"

section "a new recording's name never takes one already there"
names_dir="$OMCTEST_WORK/names"
/bin/mkdir -p "$names_dir"
printf 'x' > "$names_dir/Recording 2026-09-13 at 14.30.00.m4a"
printf 'x' > "$names_dir/Recording 2026-09-13 at 14.30.00 2.m4a"
check "a free name is used as it is" "$names_dir/Recording 2026-09-13 at 14.30.01.m4a" \
    "$(lib_call recording_path_for "$names_dir" "2026-09-13 at 14.30.01")"
check "a taken name gets the next free number" "$names_dir/Recording 2026-09-13 at 14.30.00 3.m4a" \
    "$(lib_call recording_path_for "$names_dir" "2026-09-13 at 14.30.00")"

section "an input level becomes a gauge value from 0 to 1"
check "-60 dB and quieter is empty" "0.00|0.00" "$(lib_call level_from_db -60)|$(lib_call level_from_db -90)"
check "0 dB is full, louder is clamped" "1.00|1.00" "$(lib_call level_from_db 0)|$(lib_call level_from_db 3)"
check "something that is not a number is silence" "0.00" "$(lib_call level_from_db -inf)"

# ------------------------------------------------------------------------------------------------
section "a recording that fails before writing anything raises an alert and adds nothing"
open_window
FAKE_SPEECH_MODE=record_fail
export FAKE_SPEECH_MODE
omc_run speech.record
dir="$(capture)"
pid="$(/bin/cat "$dir/speech.pid")"
omc_wait_for "! /bin/kill -0 $pid 2>/dev/null"
unset FAKE_SPEECH_MODE
poll_tick
check "the recording failed" "failed" "$(/bin/cat "$dir/state")"
check "an alert was raised" "Recording failed" "$(ui_alert_title)"
check "with speech's reason" "microphone access was refused." "$(ui_alert_message)"
check "the status carries it" "Recording failed: microphone access was refused." "$(ui_value "$REC_STATUS")"
check "nothing joined the list" "0" "$(/usr/bin/awk 'NF' "$(rec_pane)/list.tsv" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "Record is enabled again" "1" "$(ui_enabled "$REC_RECORD_BTN")"

section "Record waits for a batch, and for a live session"
open_window
printf 'running' > "$(rec_pane)/batch"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.record
check_absent "a batch keeps Record from starting" "$FAKE_SPEECH_LOG"
/bin/rm -f "$(rec_pane)/batch"
live_run="$(live_pane)/run-busy"
/bin/mkdir -p "$live_run"
printf 'running' > "$live_run/state"
printf 'run-busy' > "$(live_pane)/current"
omc_run speech.record
check_absent "a live session keeps Record from starting" "$FAKE_SPEECH_LOG"
check "and says why" "A live session is running. Stop it to record." "$(ui_value "$REC_STATUS")"
/bin/rm -rf "$live_run" "$(live_pane)/current"

section "closing the window mid-recording ends it through end of input, and the file is kept"
open_window
/bin/rm -f "$stop_log"
omc_run speech.record
dir="$(capture)"
output="$(/bin/cat "$dir/output.path")"
pid="$(/bin/cat "$dir/speech.pid")"
omc_wait_for "/usr/bin/grep -q 'recording.started' \"$dir/events.jsonl\""
omc_run speech.window.cancel
check_absent "the spool is gone" "$(spool)"
check "speech was told by end of input" "eof" "$(omc_wait_for "[ -s \"$stop_log\" ]" 10 && /bin/cat "$stop_log")"
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"
check_exists "the recording was kept" "$output"

section "cumulative: the window was only written through ids it declares"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no table clobbered" "" "$(ui_suspect_writes)"
check "no harness misuse" "" "$(ui_errors)"

reap_fake
omctest_end
