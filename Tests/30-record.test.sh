#!/bin/sh
# 30-record.test.sh - Record in the Recordings tab: `speech record` into a new file in the
# recordings folder, with the stdin holder; the clock and the microphone while it runs, and a warning
# when the microphone hears nothing; Record turning into Stop; Stop with "q"; the finished
# file joining the list, selected; a failure that leaves no file; and what Record waits for. The
# fake speech (helpers/fake-speech.sh) plays the recording; the real stdin holder runs.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

export SPEECH_RECORDINGS_DIR
# Record turns into Stop a moment after it was pressed even if the microphone has not opened. A
# long grace keeps that clock out of every check but the ones about it.
SPEECH_STOP_GRACE=600
export SPEECH_STOP_GRACE

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
section "Record is offered with no recording and no model needed, and the clock is hidden"
open_window
check "Record is enabled" "1" "$(ui_enabled "$REC_RECORD_BTN")"
check "the clock is hidden" "0" "$(ui_visible "$REC_CLOCK")"
check "the status mentions Record" \
    "Drop recordings here or add them, or press Record, then Transcribe. Each transcript is saved beside its recording." \
    "$(ui_value "$REC_STATUS")"

section "Record starts speech record into a new file in the recordings folder, with its holder"
existing="$OMCTEST_WORK/existing.wav"
printf 'RIFF' > "$existing"
printf '%s\n' "$existing" > "$(rec_pane)/list.tsv"
pane_call recordings refresh_recordings_actions "$(rec_pane)"
check "with a recording listed, Transcribe is enabled before recording starts" "1" "$(ui_enabled "$REC_TRANSCRIBE_BTN")"
omc_table_cell "$REC_TABLE" 4 "$existing"
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
check "Record already reads Stop, as a prominent button" "Stop|stop.circle.fill|borderedProminent" \
    "$(ui_prop "$REC_RECORD_BTN" title)|$(ui_prop "$REC_RECORD_BTN" systemImage)|$(ui_prop "$REC_RECORD_BTN" buttonStyle)"
check "but stays disabled until the microphone is open" "0" "$(ui_enabled "$REC_RECORD_BTN")"
check "Transcribe is disabled while recording" "0" "$(ui_enabled "$REC_TRANSCRIBE_BTN")"
# The model handler ignores a change while the pane is busy, so the picker must not offer one: an
# enabled picker would show the new choice while the pane kept the old.
check "the pickers are disabled while recording" "0|0" "$(ui_enabled "$REC_MODEL_PICKER")|$(ui_enabled "$REC_LANGUAGE_PICKER")"
check "Remove is disabled while recording" "0" "$(ui_enabled "$REC_REMOVE_BTN")"
check "the batch Stop stays hidden: Record is the only Stop" "0|1" "$(ui_visible "$REC_STOP_BTN")|$(ui_visible "$REC_RECORD_BTN")"
check "the clock is shown" "1|0:00" "$(ui_visible "$REC_CLOCK")|$(ui_value "$REC_CLOCK")"
omc_run speech.record
check "a second Record before the microphone is open starts nothing and stops nothing" "1|running" \
    "$(/usr/bin/wc -l < "$FAKE_SPEECH_LOG" | /usr/bin/tr -d ' ')|$(/bin/cat "$dir/state")"
omc_wait_for "/usr/bin/grep -q 'recording.level' \"$dir/events.jsonl\""
poll_tick
check "the clock shows the elapsed time" "1:05" "$(ui_value "$REC_CLOCK")"
check "the status names the microphone and the file" \
    "Recording from Test Microphone into $(/usr/bin/basename "$output")." "$(ui_value "$REC_STATUS")"
check "the microphone is open: Record, reading Stop, is enabled" "1" "$(ui_enabled "$REC_RECORD_BTN")"

section "a recording keeps Live from starting, and says why"
pane_call live refresh_live_actions "$(live_pane)"
check "Live is disabled" "0" "$(ui_enabled "$LIVE_BTN")"
check "the Live status names the recording" \
    "A recording is being made in the Recordings tab. Live is available when it is done." "$(ui_value "$LIVE_STATUS")"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.live
check_absent "a Live that arrives anyway starts nothing" "$FAKE_SPEECH_LOG"

section "a Transcribe while recording starts nothing"
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
check "the table lists it" "$(/usr/bin/basename "$output")" "$(ui_rows "$REC_TABLE" | /usr/bin/awk -F'\t' -v p="$output" '$4 == p { print $1 }')"
check "the status says so" \
    "Recorded $(/usr/bin/basename "$output") (2.0 s). It is in the list, ready to transcribe." "$(ui_value "$REC_STATUS")"
check "the clock is hidden again" "0" "$(ui_visible "$REC_CLOCK")"
check "Record reads Record again" "Record|record.circle|bordered" \
    "$(ui_prop "$REC_RECORD_BTN" title)|$(ui_prop "$REC_RECORD_BTN" systemImage)|$(ui_prop "$REC_RECORD_BTN" buttonStyle)"
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

section "Record pressed again stops the recording, the way Stop does"
/bin/rm -f "$FAKE_SPEECH_LOG" "$stop_log"
omc_run speech.record
dir="$(capture)"
pid="$(/bin/cat "$dir/speech.pid")"
omc_wait_for "/usr/bin/grep -q 'recording.level' \"$dir/events.jsonl\""
poll_tick
check "Record reads Stop and is enabled" "Stop|1" "$(ui_prop "$REC_RECORD_BTN" title)|$(ui_enabled "$REC_RECORD_BTN")"
omc_run speech.record
check "the recording is stopping" "stopping" "$(/bin/cat "$dir/state")"
check "speech was told with q" "q" "$(omc_wait_for "[ -s \"$stop_log\" ]" && /bin/cat "$stop_log")"
check "no second recording was started" "1" "$(/usr/bin/wc -l < "$FAKE_SPEECH_LOG" | /usr/bin/tr -d ' ')"
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"
poll_tick
check "the recording ended as done" "done" "$(/bin/cat "$dir/state")"
check "Record reads Record again" "Record|1" "$(ui_prop "$REC_RECORD_BTN" title)|$(ui_enabled "$REC_RECORD_BTN")"

section "Record stops a recording whose microphone has not opened, once the grace has passed"
/bin/rm -f "$FAKE_SPEECH_LOG" "$stop_log"
SPEECH_STOP_GRACE=0
omc_run speech.record
dir="$(capture)"
pid="$(/bin/cat "$dir/speech.pid")"
check_absent "no tick has read recording.started" "$dir/started"
check "Record, reading Stop, is enabled anyway" "Stop|1" "$(ui_prop "$REC_RECORD_BTN" title)|$(ui_enabled "$REC_RECORD_BTN")"
omc_run speech.record
check "the recording is stopping" "stopping" "$(/bin/cat "$dir/state")"
check "speech was told with q" "q" "$(omc_wait_for "[ -s \"$stop_log\" ]" && /bin/cat "$stop_log")"
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"
poll_tick
SPEECH_STOP_GRACE=600

section "when Record may stop a recording: the microphone open, or the grace passed"
grace="$OMCTEST_WORK/grace"
now="$(/bin/date +%s)"
for name in "capture-$now-1" "capture-$((now - 5))-2" "capture-$now-3" "capture-$((now - 5))-4"; do
    /bin/mkdir -p "$grace/$name"
    printf 'running' > "$grace/$name/state"
done
: > "$grace/capture-$now-3/started"
printf 'stopping' > "$grace/capture-$((now - 5))-4/state"
can_stop() { SPEECH_STOP_GRACE=2 lib_call capture_can_stop "$1"; printf '%s' "$?"; }
check "just pressed, microphone not open: not yet" "1" "$(can_stop "$grace/capture-$now-1")"
check "five seconds on, microphone still not open: yes" "0" "$(can_stop "$grace/capture-$((now - 5))-2")"
check "just pressed, microphone open: yes" "0" "$(can_stop "$grace/capture-$now-3")"
check "already stopping: no" "1" "$(can_stop "$grace/capture-$((now - 5))-4")"
check "no recording: no" "1" "$(can_stop "")"

# ------------------------------------------------------------------------------------------------
# The fake says one level; these sequences are played straight into the reader of a recording
# that looks running, so the seconds and levels are exactly the ones under test.
section "the status warns when the microphone hears nothing for five seconds of the recording"
open_window
quiet="$(rec_pane)/capture-quiet"
/bin/mkdir -p "$quiet"
printf 'running' > "$quiet/state"
printf '%s' "$OMCTEST_WORK/Recording quiet.m4a" > "$quiet/output.path"
printf 'capture-quiet' > "$(rec_pane)/capture"
level() { printf '{"peak_db":%s,"rms_db":%s,"seconds":%s,"t":%s,"type":"recording.level"}\n' "$2" "$2" "$1" "$1" >> "$quiet/events.jsonl"; }
printf '%s\n' '{"channels":1,"device":"Test Microphone","output":"x","sample_rate":48000,"t":0.1,"type":"recording.started"}' > "$quiet/events.jsonl"
level 1.2 -30.5
level 2.4 -85.25
pane_call recordings process_capture_events "$(rec_pane)"
check "sound, then quiet from 2 s: still just recording" "Recording from Test Microphone into Recording quiet.m4a.|0:02" \
    "$(ui_value "$REC_STATUS")|$(ui_value "$REC_CLOCK")"
level 6.8 -100
pane_call recordings process_capture_events "$(rec_pane)"
check "four seconds of quiet is not yet a warning" "Recording from Test Microphone into Recording quiet.m4a." "$(ui_value "$REC_STATUS")"
level 7.1 -70.5
pane_call recordings process_capture_events "$(rec_pane)"
check "five seconds is, and names the microphone" \
    "No sound from Test Microphone for 0:05. If you are speaking, check that it is the microphone you want and that it is not muted." \
    "$(ui_value "$REC_STATUS")"
level 8 -69.9
pane_call recordings process_capture_events "$(rec_pane)"
check "sound again, just above -70 dB, ends the warning" "Recording from Test Microphone into Recording quiet.m4a.|0:08" \
    "$(ui_value "$REC_STATUS")|$(ui_value "$REC_CLOCK")"
level 9 -90
level 13.9 -90
pane_call recordings process_capture_events "$(rec_pane)"
check "quiet counts again from where it began" "Recording from Test Microphone into Recording quiet.m4a." "$(ui_value "$REC_STATUS")"
level 14 '"nonsense"'
pane_call recordings process_capture_events "$(rec_pane)"
check "a level that is not a number counts as quiet" \
    "No sound from Test Microphone for 0:05. If you are speaking, check that it is the microphone you want and that it is not muted." \
    "$(ui_value "$REC_STATUS")"
/bin/rm -rf "$quiet" "$(rec_pane)/capture"

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
