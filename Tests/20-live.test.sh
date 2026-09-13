#!/bin/sh
# 20-live.test.sh - live transcription from the microphone: Record starts `speech stream` with a
# stdin holder, Stop ends the session with "q" and keeps its transcript, and a closed window or
# a dead app ends it through end of input. The fake speech (helpers/fake-speech.sh) plays the
# session; the real stdin holder runs.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

# The poller's first job, done by hand: the model list and pickers.
open_window() {
    reset_state
    omc_run speech.window.init
    lib_call load_models "$(spool)"
    lib_call populate_model_picker "$(spool)"
    end_quiet_window
    lib_call refresh_actions "$(spool)"
}

# How many stdin holders are running for a run directory. The match is on how the command line
# starts, so the process doing the counting - whose own arguments contain the path - is never
# counted with them.
holders_for() {
    /bin/ps -axo args= | /usr/bin/awk -v prefix="/bin/sh $OMCTEST_APP/Contents/Resources/Scripts/speech.live.stdin.sh $1 " \
        'index($0, prefix) == 1 { n++ } END { print n + 0 }'
}

# Wait up to five seconds for a run's stdin holders to be gone. Not omc_wait_for: that runs its
# predicate in a fresh /bin/sh, where a function of this file does not exist.
wait_for_no_holders() {   # $1 = run dir
    local _ticks=0
    local _count
    while [ "$_ticks" -lt 50 ]; do
        _count="$(holders_for "$1")"
        [ "$_count" = 0 ] && return 0
        /bin/sleep 0.1
        _ticks=$((_ticks + 1))
    done
    return 1
}

stop_log="$FAKE_SPEECH_LOG.stop"

# ------------------------------------------------------------------------------------------------
section "Record is offered for a model that can stream, with no recording chosen"
open_window
check "apple.transcriber is selected" "apple.transcriber" "$(/bin/cat "$(spool)/model.id")"
check "Record is enabled" "1" "$(ui_enabled "$RECORD_BTN")"
check "Transcribe is not, with no file" "0" "$(ui_enabled "$TRANSCRIBE_BTN")"
check "the status offers both ways in" \
    "Choose or drop a recording to transcribe, or press Record to transcribe live." "$(ui_value "$STATUS_TEXT")"

section "Record starts speech stream with the model and language, and its stdin holder"
/bin/rm -f "$FAKE_SPEECH_LOG" "$stop_log"
omc_run speech.record
check_status "record exits cleanly" 0
check "speech stream was started with the model and language" \
    "--json stream --model apple.transcriber --language en" \
    "$(omc_wait_for "[ -s \"$FAKE_SPEECH_LOG\" ]" && /usr/bin/head -1 "$FAKE_SPEECH_LOG")"
run="$(run_dir)"
check "the run is live" "live" "$(/bin/cat "$run/kind")"
check "its stdin is a FIFO" "yes" "$([ -p "$run/stdin.fifo" ] && echo yes || echo no)"
check "speech is running" "alive" "$(/bin/kill -0 "$(/bin/cat "$run/speech.pid")" 2>/dev/null && echo alive || echo dead)"
check "one stdin holder is running for the run" "1" "$(holders_for "$run")"
omc_wait_for "/usr/bin/grep -q '\"id\":1' \"$run/events.jsonl\""
poll_tick
check "the finished utterance and the one still spoken are shown, the draft marked" \
    "Hello world.
and more ..." "$(ui_value "$TRANSCRIPT_EDITOR")"
check "the status says to speak" "Recording. Speak now." "$(ui_value "$STATUS_TEXT")"
check "Stop is enabled" "1" "$(ui_enabled "$STOP_BTN")"
check "Record is disabled while recording" "0" "$(ui_enabled "$RECORD_BTN")"
check "the model picker is disabled while recording" "0" "$(ui_enabled "$MODEL_PICKER")"
check "Export waits for the end" "0" "$(ui_enabled "$EXPORT_MENU")"

section "a second Record while recording starts nothing"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.record
check_absent "speech was not started again" "$FAKE_SPEECH_LOG"
check "the same run is current" "$run" "$(run_dir)"

# ------------------------------------------------------------------------------------------------
section "Stop sends q, the session finishes its last utterance, and the transcript is kept"
pid="$(/bin/cat "$run/speech.pid")"
omc_run speech.stop
check "the run is stopping" "stopping" "$(/bin/cat "$run/state")"
check "the holder was asked" "yes" "$([ -f "$run/stop.request" ] && echo yes || echo no)"
check "speech was told with q, not end of input" "q" \
    "$(omc_wait_for "[ -s \"$stop_log\" ]" && /bin/cat "$stop_log")"
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"
poll_tick
check "the session ended as done, not stopped: q is a tidy stop" "done" "$(/bin/cat "$run/state")"
check "the last utterance was finalized" \
    "Hello world.
And more." "$(ui_value "$TRANSCRIPT_EDITOR")"
check "the status carries no speed figure" "Done: 2 segments, 2.4 s of audio." "$(ui_value "$STATUS_TEXT")"
check "a JSON transcript was built from the events" "2|And more.|2" \
    "$(/usr/bin/jq -r '[(.segments | length), .segments[1].text, (.segments[0].words | length)] | map(tostring) | join("|")' "$run/result.json" 2>/dev/null)"
check "the draft partials are not in it" "0" \
    "$(/usr/bin/jq '[.segments[] | select(.text == "hello" or .text == "and more")] | length' "$run/result.json" 2>/dev/null)"
check "Export is enabled" "1" "$(ui_enabled "$EXPORT_MENU")"
check "Record is enabled again" "1" "$(ui_enabled "$RECORD_BTN")"
check "the holder exited with speech" "0" "$(wait_for_no_holders "$run"; holders_for "$run")"

section "a live transcript exports like any other"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_dialog_answer save_as "$OMCTEST_WORK/Dictation.vtt"
omc_run speech.export.vtt
check "speech export was given the built transcript" \
    "export $run/result.json --format vtt --output $OMCTEST_WORK/Dictation.vtt" "$(/usr/bin/head -1 "$FAKE_SPEECH_LOG" 2>/dev/null)"

section "the JSON transcript keeps a segment's last refinement and leaves an unfinished draft out"
# The fake's partials all precede their finals, where last-per-id alone would hide a missing
# filter, so this sequence is played straight into the builder: a final refined afterwards (the
# refinement wins and carries no word timings), and a draft that was never finalized.
draft_run="$OMCTEST_WORK/draft-run"
/bin/rm -rf "$draft_run"
/bin/mkdir -p "$draft_run"
printf 'apple.transcriber' > "$draft_run/model"
printf 'auto' > "$draft_run/language"
printf '%s\n' \
    '{"engine":"apple.transcriber","t":0.1,"type":"engine.ready"}' \
    '{"end":1.5,"id":0,"start":0,"t":1.0,"text":"Hello world.","type":"segment.final","words":[{"end":0.6,"start":0,"text":"Hello"},{"end":1.5,"start":0.6,"text":"world."}]}' \
    '{"end":1.5,"id":0,"refined_by":"apple.dictation","start":0,"t":1.8,"text":"Hello, world.","type":"segment.refined"}' \
    '{"end":2,"id":1,"start":1.6,"t":1.2,"text":"and more","type":"segment.partial"}' \
    '{"audio_seconds":2.4,"rtfx":1,"segments":1,"t":2.1,"type":"done","wall_seconds":2.4}' \
    > "$draft_run/events.jsonl"
lib_call build_live_result "$draft_run"
check "the refinement replaced the final, its draft words dropped, the unfinished draft left out" \
    "1|Hello, world.|no words" \
    "$(/usr/bin/jq -r '[(.segments | length), .segments[0].text, (.segments[0].words // "no words")] | map(tostring) | join("|")' "$draft_run/result.json" 2>/dev/null)"
check "the run's model is recorded and Automatic becomes no language" "apple.transcriber|" \
    "$(/usr/bin/jq -r '[.model, .language] | join("|")' "$draft_run/result.json" 2>/dev/null)"

# ------------------------------------------------------------------------------------------------
section "closing the window mid-session ends it through end of input"
/bin/rm -f "$stop_log"
omc_run speech.record
run="$(run_dir)"
pid="$(/bin/cat "$run/speech.pid")"
omc_wait_for "/usr/bin/grep -q 'engine.ready' \"$run/events.jsonl\""
omc_run speech.window.cancel
check_absent "the spool is gone" "$(spool)"
check "speech was told by end of input" "eof" \
    "$(omc_wait_for "[ -s \"$stop_log\" ]" 10 && /bin/cat "$stop_log")"
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"

section "an app that is gone ends the session through end of input"
open_window
/bin/rm -f "$stop_log"
/bin/sleep 60 &
dead_app=$!
/bin/kill -KILL "$dead_app"
wait "$dead_app" 2>/dev/null
orphan_run="$(spool)/run-orphan"
/bin/mkdir -p "$orphan_run"
# The dead pid goes to this one call only, in a subshell of its own.
pid="$( OMC_APP_PROCESS_ID="$dead_app"; export OMC_APP_PROCESS_ID; lib_call spawn_stream "$orphan_run" apple.transcriber en )"
case "$pid" in ''|*[!0-9]*) started=no ;; *) started=yes ;; esac
check "speech was started" "yes" "$started"
check "speech was told by end of input, with no one asking" "eof" \
    "$(omc_wait_for "[ -s \"$stop_log\" ]" 10 && /bin/cat "$stop_log")"
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"

# ------------------------------------------------------------------------------------------------
section "a model that cannot stream disables Record and says why"
open_window
omc_control "$MODEL_PICKER" 3
omc_run speech.model.changed
check "Whisper is selected" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$(spool)/model.id")"
check "Record is disabled" "0" "$(ui_enabled "$RECORD_BTN")"
check "the status says the model cannot" \
    "Choose or drop a recording to transcribe. Whisper large-v3-turbo (Q8_0) cannot transcribe live." "$(ui_value "$STATUS_TEXT")"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.record
check_absent "a Record that arrives anyway starts nothing" "$FAKE_SPEECH_LOG"
check "and says why" "Whisper large-v3-turbo (Q8_0) cannot transcribe live. Choose a model that can." "$(ui_value "$STATUS_TEXT")"

section "cumulative: the window was only written through ids it declares"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no table clobbered" "" "$(ui_suspect_writes)"
check "no harness misuse" "" "$(ui_errors)"

reap_fake
omctest_end
