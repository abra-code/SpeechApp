#!/bin/sh
# 20-live.test.sh - the Live tab: Live starts `speech stream` with a stdin holder, Live reading Stop
# ends the session with "q" and keeps its transcript, and a closed window or a dead app ends it through end
# of input. The fake speech (helpers/fake-speech.sh) plays the session; the real stdin holder runs.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

open_window() {
    reset_state
    omc_run speech.window.init
    load_window_models
    pane_call live refresh_live_actions "$(live_pane)"
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
# Live turns into Stop a moment after it was pressed even if the microphone has not opened. A long
# grace keeps that clock out of every check but the ones about it.
SPEECH_STOP_GRACE=600
export SPEECH_STOP_GRACE

# ------------------------------------------------------------------------------------------------
section "the Live picker offers only models that can stream, each marked with its engine"
open_window
check "only the live rows, Apple's unmarked and ggml's with its squared G" \
    "[\"Apple dictation (built in)\",\"Apple long-form (built in)\",\"Nemotron \\\"streaming\\\" (Q8_0) $ggml_mark\",\"Download Models...\"]" \
    "$(ui_prop "$LIVE_MODEL_PICKER" options)"
check "apple.transcriber is selected" "apple.transcriber" "$(/bin/cat "$(live_pane)/model.id")"
check "Live is enabled" "1" "$(ui_enabled "$LIVE_BTN")"
check "it reads Live, and the clock is hidden" "Live|waveform|0" "$(ui_prop "$LIVE_BTN" title)|$(ui_prop "$LIVE_BTN" systemImage)|$(ui_visible "$LIVE_CLOCK")"
check "the status says what Live does" \
    "Press Live to transcribe the microphone with Apple long-form (built in)." "$(ui_value "$LIVE_STATUS")"

section "a Live model choice is saved under its own key, apart from the Recordings tab's"
omc_control "$LIVE_MODEL_PICKER" 3
omc_run speech.model.changed
check "Nemotron is selected" "ggml.nemotron-3.5-asr-streaming-0.6b@q8_0" "$(/bin/cat "$(live_pane)/model.id")"
check "saved as live.model" "ggml.nemotron-3.5-asr-streaming-0.6b@q8_0" "$(/bin/cat "$SPEECH_APP_SUPPORT/Settings/live.model" 2>/dev/null)"
check_absent "the Recordings tab's choice is untouched" "$SPEECH_APP_SUPPORT/Settings/recordings.model"
end_quiet_window
omc_control "$LIVE_MODEL_PICKER" 2
omc_run speech.model.changed
check "back to apple.transcriber" "apple.transcriber" "$(/bin/cat "$(live_pane)/model.id")"

section "the transcript's placeholder says what the selected live model is like"
notes="$OMC_APP_BUNDLE_PATH/Contents/Resources/live-notes.tsv"
note_for() { /usr/bin/awk -F'\t' -v key="$1" '$1 == key { print $2; exit }' "$notes"; }
check "apple.transcriber's own note" "Press Live and speak. $(note_for apple.transcriber)" "$(ui_prop "$LIVE_TRANSCRIPT" placeholder)"
check "the note is not empty" "yes" "$([ -n "$(note_for apple.transcriber)" ] && echo yes || echo no)"
end_quiet_window
omc_control "$LIVE_MODEL_PICKER" 3
omc_run speech.model.changed
check "a variant without a note of its own takes its family's" \
    "Press Live and speak. $(note_for ggml.nemotron-3.5-asr-streaming-0.6b)" "$(ui_prop "$LIVE_TRANSCRIPT" placeholder)"
check "an exact id wins over its family" "$(note_for fluid.nemotron-multilingual@560)" \
    "$(lib_call live_model_note fluid.nemotron-multilingual@560)"
check "a model with no note gets none" "" "$(lib_call live_model_note ggml.whisper-large-v3-turbo@q8_0)"
check "every live row has a note" "" "$(for id in apple.dictation apple.transcriber fluid.nemotron-multilingual@2240 fluid.nemotron-multilingual@1120 fluid.nemotron-multilingual@560 ggml.nemotron-3.5-asr-streaming-0.6b@q8_0 ggml.nemotron-3.5-asr-streaming-0.6b@q4_k_m fluid.parakeet-v3@int8 fluid.parakeet-v3@int4 fluid.parakeet-unified@stream-2080 fluid.parakeet-unified@stream-1120 fluid.parakeet-unified@stream-640 fluid.parakeet-unified@stream-320 ggml.parakeet-unified-en-0.6b@q8_0; do [ -n "$(lib_call live_model_note "$id")" ] || printf '%s ' "$id"; done)"
end_quiet_window
omc_control "$LIVE_MODEL_PICKER" 2
omc_run speech.model.changed
check "back to apple.transcriber for the sections below" "apple.transcriber" "$(/bin/cat "$(live_pane)/model.id")"
end_quiet_window

# ------------------------------------------------------------------------------------------------
section "Live starts speech stream with the model and language, and its stdin holder"
/bin/rm -f "$FAKE_SPEECH_LOG" "$stop_log"
omc_run speech.live
check_status "live exits cleanly" 0
check "the card is up the moment Live is pressed, saying not to speak yet" "1|Getting ready. Don't speak yet.|Loading Apple long-form (built in)..." \
    "$(ui_visible "$LIVE_CARD")|$(ui_value "$LIVE_CARD_TITLE")|$(ui_value "$LIVE_CARD_DETAIL")"
check "speech stream was started with the model and language" \
    "--json stream --model apple.transcriber --language en" \
    "$(omc_wait_for "[ -s \"$FAKE_SPEECH_LOG\" ]" && /usr/bin/head -1 "$FAKE_SPEECH_LOG")"
run="$(run_dir)"
check "the run is live" "live" "$(/bin/cat "$run/kind")"
check "its stdin is a FIFO" "yes" "$([ -p "$run/stdin.fifo" ] && echo yes || echo no)"
check "speech is running" "alive" "$(/bin/kill -0 "$(/bin/cat "$run/speech.pid")" 2>/dev/null && echo alive || echo dead)"
check "one stdin holder is running for the run" "1" "$(holders_for "$run")"
check "Live already reads Stop, in red" "Stop|stop.circle.fill|red" \
    "$(ui_prop "$LIVE_BTN" title)|$(ui_prop "$LIVE_BTN" systemImage)|$(ui_prop "$LIVE_BTN" tint)"
check "but stays disabled until the microphone is open, and the clock waits for it too" "0|0" "$(ui_enabled "$LIVE_BTN")|$(ui_visible "$LIVE_CLOCK")"
omc_run speech.live
check "a second Live before the microphone is open starts nothing and stops nothing" "1|running|$run" \
    "$(/usr/bin/wc -l < "$FAKE_SPEECH_LOG" | /usr/bin/tr -d ' ')|$(/bin/cat "$run/state")|$(run_dir)"
omc_wait_for "/usr/bin/grep -q '\"id\":1' \"$run/events.jsonl\""
poll_tick
check "the finished utterance and the one still spoken are shown, the draft marked" \
    "Hello world.
and more ..." "$(ui_value "$LIVE_TRANSCRIPT")"
check "the status says to speak" "Listening. Speak now." "$(ui_value "$LIVE_STATUS")"
check "the card is gone: the words are the proof the microphone is open" "0" "$(ui_visible "$LIVE_CARD")"
check "the microphone is open: Live, reading Stop, is enabled" "Stop|1" "$(ui_prop "$LIVE_BTN" title)|$(ui_enabled "$LIVE_BTN")"
case "$(ui_value "$LIVE_CLOCK")" in 0:0[0-9]) clock_start=seconds ;; *) clock_start="$(ui_value "$LIVE_CLOCK")" ;; esac
check "the clock runs from when the microphone opened" "1|seconds" "$(ui_visible "$LIVE_CLOCK")|$clock_start"
printf '%s' "$(($(/bin/date +%s) - 65))" > "$run/listening.since"
poll_tick
check "a minute on, it says so" "1:05" "$(ui_value "$LIVE_CLOCK")"
check "the model picker is disabled while listening" "0" "$(ui_enabled "$LIVE_MODEL_PICKER")"
check "Export waits for the end" "0" "$(ui_enabled "$LIVE_EXPORT_MENU")"

section "a live session keeps the Recordings tab from starting a batch"
recording="$OMCTEST_WORK/memo.wav"
printf 'RIFF' > "$recording"
printf '%s\n' "$recording" > "$(rec_pane)/list.tsv"
omc_run speech.recordings.transcribe
check_absent "no batch was queued" "$(rec_pane)/batch"
check "the Recordings status says why" "A live session is running. Stop it to transcribe recordings." "$(ui_value "$REC_STATUS")"
: > "$(rec_pane)/list.tsv"

# ------------------------------------------------------------------------------------------------
section "Live, reading Stop, sends q, the session finishes its last utterance, and the transcript is kept"
/bin/rm -f "$FAKE_SPEECH_LOG"
pid="$(/bin/cat "$run/speech.pid")"
omc_run speech.live
check_absent "no second session was started" "$FAKE_SPEECH_LOG"
check "the run is stopping" "stopping" "$(/bin/cat "$run/state")"
check "the holder was asked" "yes" "$([ -f "$run/stop.request" ] && echo yes || echo no)"
check "speech was told with q, not end of input" "q" \
    "$(omc_wait_for "[ -s \"$stop_log\" ]" && /bin/cat "$stop_log")"
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"
poll_tick
check "the session ended as done, not stopped: q is a tidy stop" "done" "$(/bin/cat "$run/state")"
check "the last utterance was finalized" \
    "Hello world.
And more." "$(ui_value "$LIVE_TRANSCRIPT")"
check "the status carries no speed figure" "Done: 2 segments, 2.4 s of audio." "$(ui_value "$LIVE_STATUS")"
check "a JSON transcript was built from the events" "2|And more.|2" \
    "$(/usr/bin/jq -r '[(.segments | length), .segments[1].text, (.segments[0].words | length)] | map(tostring) | join("|")' "$run/result.json" 2>/dev/null)"
check "the draft partials are not in it" "0" \
    "$(/usr/bin/jq '[.segments[] | select(.text == "hello" or .text == "and more")] | length' "$run/result.json" 2>/dev/null)"
check "Export is enabled" "1" "$(ui_enabled "$LIVE_EXPORT_MENU")"
check "Live is enabled again" "1" "$(ui_enabled "$LIVE_BTN")"
check "reading Live, with the clock hidden" "Live|accentColor|0" "$(ui_prop "$LIVE_BTN" title)|$(ui_prop "$LIVE_BTN" tint)|$(ui_visible "$LIVE_CLOCK")"
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
section "the event reader leaves a half-written line for the next tick"
: > "$run/segments.tsv"
/bin/rm -f "$run/events.lines" "$run/reflected"
printf '%s\n' '{"id":0,"text":"first draft","type":"segment.partial"}' > "$run/events.jsonl"
printf '%s' '{"id":0,"text":"first dr' >> "$run/events.jsonl"
pane_call live process_events "$(live_pane)"
check "only the complete line was consumed" "1" "$(/bin/cat "$run/events.lines")"
check "its segment is in the table" "0	partial	first draft" "$(/bin/cat "$run/segments.tsv")"
printf '%s\n' 'aft","type":"segment.final"}' >> "$run/events.jsonl"
printf '%s\n' '{"id":0,"refined_by":"apple.dictation","text":"first draft, refined","type":"segment.refined"}' >> "$run/events.jsonl"
pane_call live process_events "$(live_pane)"
check "the completed line and the next were consumed" "3" "$(/bin/cat "$run/events.lines")"
check "the refinement replaced the final, which replaced the partial" "0	refined	first draft, refined" "$(/bin/cat "$run/segments.tsv")"

section "an unreadable line costs only itself"
printf '%s\n' 'this is not json' '{"id":1,"text":"after the bad line","type":"segment.final"}' >> "$run/events.jsonl"
pane_call live process_events "$(live_pane)"
check "both lines were consumed" "5" "$(/bin/cat "$run/events.lines")"
check "the good line still landed" "after the bad line" "$(/usr/bin/awk -F'\t' '$1 == 1 { print $3 }' "$run/segments.tsv")"
check_grep "the bad line was kept for inspection" "this is not json" "$run/events.unreadable"

# ------------------------------------------------------------------------------------------------
section "closing the window mid-session ends it through end of input"
/bin/rm -f "$stop_log"
omc_run speech.live
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
orphan_run="$(live_pane)/run-orphan"
/bin/mkdir -p "$orphan_run"
# The dead pid goes to this one call only, in a subshell of its own.
pid="$( OMC_APP_PROCESS_ID="$dead_app"; export OMC_APP_PROCESS_ID; lib_call spawn_stream "$orphan_run" apple.transcriber en )"
case "$pid" in ''|*[!0-9]*) started=no ;; *) started=yes ;; esac
check "speech was started" "yes" "$started"
check "speech was told by end of input, with no one asking" "eof" \
    "$(omc_wait_for "[ -s \"$stop_log\" ]" 10 && /bin/cat "$stop_log")"
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"

# ------------------------------------------------------------------------------------------------
# The fake holds the session at each moment in turn: loaded but the microphone not open, then
# listening with nothing said.
card() { printf '%s|%s|%s|%s|%s' "$(ui_visible "$LIVE_CARD")" "$(ui_visible "$LIVE_CARD_SPINNER")" \
    "$(ui_visible "$LIVE_CARD_MIC")" "$(ui_value "$LIVE_CARD_TITLE")" "$(ui_value "$LIVE_CARD_DETAIL")"; }
open_gate() { : > "$FAKE_SPEECH_LOG.$1"; }

section "the card says not to speak until the microphone is open, and then to speak"
open_window
/bin/rm -f "$FAKE_SPEECH_LOG" "$FAKE_SPEECH_LOG.open" "$FAKE_SPEECH_LOG.words" "$stop_log"
FAKE_SPEECH_STREAM=gated
export FAKE_SPEECH_STREAM
omc_run speech.live
unset FAKE_SPEECH_STREAM
run="$(run_dir)"
pid="$(/bin/cat "$run/speech.pid")"
check "while the model loads: a spinner, and not to speak yet" \
    "1|1|0|Getting ready. Don't speak yet.|Loading Apple long-form (built in)..." "$(card)"
omc_wait_for "/usr/bin/grep -q 'engine.ready' \"$run/events.jsonl\""
poll_tick
check "the model is loaded but the microphone is not open: still not yet" \
    "1|1|0|Getting ready. Don't speak yet.|Turning on the microphone..." "$(card)"
check "the status line says the same" "Turning on the microphone..." "$(ui_value "$LIVE_STATUS")"
open_gate open
omc_wait_for "/usr/bin/grep -q 'stream.started' \"$run/events.jsonl\""
poll_tick
check "the microphone is open: speak now, into the microphone speech named" \
    "1|0|1|Speak now.|Listening to Test Microphone." "$(card)"
check "the status line says to speak" "Listening. Speak now." "$(ui_value "$LIVE_STATUS")"

section "the speak card goes after a few seconds of silence"
printf '%s' "$(($(/bin/date +%s) - LIVE_SPEAK_SECONDS))" > "$run/listening.since"
poll_tick
check "the card is gone" "0" "$(ui_visible "$LIVE_CARD")"
check "the status line still says to speak" "Listening. Speak now." "$(ui_value "$LIVE_STATUS")"

section "the speak card goes as soon as words arrive"
/bin/date +%s | /usr/bin/tr -d '\n' > "$run/listening.since"
poll_tick
check "back while nothing is said" "1" "$(ui_visible "$LIVE_CARD")"
open_gate words
omc_wait_for "/usr/bin/grep -q '\"id\":1' \"$run/events.jsonl\""
poll_tick
check "the card is gone" "0" "$(ui_visible "$LIVE_CARD")"
check "and the transcript it covered is there" "Hello world.
and more ..." "$(ui_value "$LIVE_TRANSCRIPT")"
omc_run speech.live
omc_wait_for "! /bin/kill -0 $pid 2>/dev/null"
poll_tick

section "Live, reading Stop, stops a session still getting ready once the grace has passed, and takes the card down"
SPEECH_STOP_GRACE=0
/bin/rm -f "$FAKE_SPEECH_LOG.open" "$FAKE_SPEECH_LOG.words"
FAKE_SPEECH_STREAM=gated
export FAKE_SPEECH_STREAM
omc_run speech.live
unset FAKE_SPEECH_STREAM
run="$(run_dir)"
pid="$(/bin/cat "$run/speech.pid")"
check "the card is up" "1" "$(ui_visible "$LIVE_CARD")"
check "Live is enabled though the microphone has not opened" "Stop|1" "$(ui_prop "$LIVE_BTN" title)|$(ui_enabled "$LIVE_BTN")"
omc_run speech.live
check "the session is stopping" "stopping" "$(/bin/cat "$run/state")"
check "Stop took it down at once" "0" "$(ui_visible "$LIVE_CARD")"
open_gate open
open_gate words
check "speech exited" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"
poll_tick
check "and it stays down" "0" "$(ui_visible "$LIVE_CARD")"
/bin/rm -f "$FAKE_SPEECH_LOG.open" "$FAKE_SPEECH_LOG.words"
SPEECH_STOP_GRACE=600

# ------------------------------------------------------------------------------------------------
section "a model that cannot stream is refused, and says why"
open_window
printf 'ggml.whisper-large-v3-turbo@q8_0' > "$(live_pane)/model.id"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.live
check_absent "a Live that arrives anyway starts nothing" "$FAKE_SPEECH_LOG"
check "and names the model" "ggml.whisper-large-v3-turbo@q8_0 cannot transcribe live. Choose a model that can." "$(ui_value "$LIVE_STATUS")"

section "a batch of recordings keeps Live disabled, and says why"
open_window
printf 'running' > "$(rec_pane)/batch"
pane_call live refresh_live_actions "$(live_pane)"
check "Live is disabled" "0" "$(ui_enabled "$LIVE_BTN")"
check "the status says why" "Recordings are being transcribed. Live is available when they are done." "$(ui_value "$LIVE_STATUS")"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.live
check_absent "a Live that arrives anyway starts nothing" "$FAKE_SPEECH_LOG"
/bin/rm -f "$(rec_pane)/batch"

section "cumulative: the window was only written through ids it declares"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no table clobbered" "" "$(ui_suspect_writes)"
check "no harness misuse" "" "$(ui_errors)"

reap_fake
omctest_end
