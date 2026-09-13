#!/bin/sh
# 10-transcribe.test.sh - the Transcribe tab with a recorded file: opening a window for a file,
# the model and language pickers, a transcription from start to rendered transcript, the event
# reader's edge cases, failure, stop, export, drop, and closing the window.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

recording="$OMCTEST_WORK/interview take 1.wav"
printf 'RIFF not really audio' > "$recording"

# ------------------------------------------------------------------------------------------------
section "a window opened for a file takes over the handoff and starts the poller"
reset_state
"$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH set "$recording"
omc_run speech.window.init
check_status "init exits cleanly" 0
check_exists "the spool exists" "$(spool)"
check "the recording is recorded" "$recording" "$(/bin/cat "$(spool)/source.path" 2>/dev/null)"
check "its name is shown" "interview take 1.wav" "$(ui_value "$SOURCE_TEXT")"
check "the window is titled after it" "interview take 1.wav - Speech" "$(ui_title)"
check "the handoff was consumed" "" "$("$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH get)"
check "Transcribe starts disabled" "0" "$(ui_enabled "$TRANSCRIBE_BTN")"
check "the poller was started for this window and spool" \
    "$OMC_ACTIONUI_WINDOW_UUID|$(spool)" \
    "$(omc_wait_for "[ -s \"$OMCTEST_WORK/poller.args\" ]" && /usr/bin/paste -sd '|' "$OMCTEST_WORK/poller.args")"

# ------------------------------------------------------------------------------------------------
section "the model list keeps only rows that can transcribe now"
lib_call load_models "$(spool)"
check "the catalog was read" "0" "$?"
check "four runnable rows: two Apple, Whisper, Nemotron" \
    "apple.dictation apple.transcriber ggml.whisper-large-v3-turbo@q8_0 ggml.nemotron-3.5-asr-streaming-0.6b@q8_0" \
    "$(/usr/bin/cut -f1 "$(spool)/models.tsv" | /usr/bin/paste -sd ' ' -)"
lib_call populate_model_picker "$(spool)"
check "apple.transcriber is chosen when nothing is saved" "apple.transcriber" "$(/bin/cat "$(spool)/model.id")"
check "the picker points at it" "2" "$(ui_value "$MODEL_PICKER")"
check "a quote in a label is escaped in the options" \
    '["Apple dictation (built in)","Apple long-form (built in)","Whisper large-v3-turbo (Q8_0)","Nemotron \"streaming\" (Q8_0)"]' \
    "$(ui_prop "$MODEL_PICKER" options)"
check "Apple needs a language: no Automatic, sorted by name" \
    '["English","German","Spanish"]' "$(ui_prop "$LANGUAGE_PICKER" options)"
check "the locale's language is chosen" "en" "$(/bin/cat "$(spool)/language.tag")"
lib_call refresh_actions "$(spool)"
check "Transcribe is enabled with a file and a model" "1" "$(ui_enabled "$TRANSCRIBE_BTN")"
check "Stop is not" "0" "$(ui_enabled "$STOP_BTN")"
check "Export is not, with nothing transcribed" "0" "$(ui_enabled "$EXPORT_MENU")"
check "the status says what is ready" \
    "Ready to transcribe interview take 1.wav with Apple long-form (built in)." "$(ui_value "$STATUS_TEXT")"

# ------------------------------------------------------------------------------------------------
section "a picker change inside the quiet window is an echo and is ignored"
omc_control "$MODEL_PICKER" 3
omc_run speech.model.changed
check "the model did not change" "apple.transcriber" "$(/bin/cat "$(spool)/model.id")"

section "a model that identifies languages gets Automatic"
end_quiet_window
omc_control "$MODEL_PICKER" 3
omc_run speech.model.changed
check "Whisper is chosen" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$(spool)/model.id")"
check "and remembered" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$SPEECH_APP_SUPPORT/Settings/model" 2>/dev/null)"
check "Automatic comes first, then names, an unknown code by its tag" \
    '["Automatic","English","Javanese","Polish"]' "$(ui_prop "$LANGUAGE_PICKER" options)"
check "Automatic is chosen" "auto" "$(/bin/cat "$(spool)/language.tag")"

section "a region-tagged model shows the tag, and a saved language finds it by primary subtag"
end_quiet_window
omc_control "$LANGUAGE_PICKER" 4
omc_run speech.language.changed
check "Polish is saved as a tag" "pl" "$(/bin/cat "$SPEECH_APP_SUPPORT/Settings/language" 2>/dev/null)"
end_quiet_window
omc_control "$MODEL_PICKER" 4
omc_run speech.model.changed
check "the region tags are shown" '["English (en-US)","Polish (pl-PL)"]' "$(ui_prop "$LANGUAGE_PICKER" options)"
check "saved pl selects pl-PL" "pl-PL" "$(/bin/cat "$(spool)/language.tag")"

section "a picker index that resolves to nothing changes nothing"
end_quiet_window
omc_control "$MODEL_PICKER" 99
omc_run speech.model.changed
check "the model is unchanged" "ggml.nemotron-3.5-asr-streaming-0.6b@q8_0" "$(/bin/cat "$(spool)/model.id")"
omc_control "$MODEL_PICKER" "Whisper"
omc_run speech.model.changed
check "a title instead of an index is refused too" "ggml.nemotron-3.5-asr-streaming-0.6b@q8_0" "$(/bin/cat "$(spool)/model.id")"

# ------------------------------------------------------------------------------------------------
section "a saved language beats Automatic when the next model offers it"
end_quiet_window
omc_control "$MODEL_PICKER" 3
omc_run speech.model.changed
check "Whisper starts on the saved Polish, not Automatic" "pl" "$(/bin/cat "$(spool)/language.tag")"

section "Transcribe runs speech with the file, model and language, and the poller renders it"
end_quiet_window
omc_control "$LANGUAGE_PICKER" 1
omc_run speech.language.changed
check "Automatic is chosen by the user" "auto" "$(/bin/cat "$(spool)/language.tag")"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.transcribe
check_status "transcribe exits cleanly" 0
check "speech was asked to transcribe the file with Whisper, no language flag for Automatic" \
    "--json transcribe $recording --model ggml.whisper-large-v3-turbo@q8_0 --format json --output $(run_dir)/result.json" \
    "$(omc_wait_for "[ -s \"$FAKE_SPEECH_LOG\" ]" && /usr/bin/head -1 "$FAKE_SPEECH_LOG")"
check "the run is marked running" "running" "$(/bin/cat "$(run_dir)/state")"
check "the run recorded a pid" "yes" "$(/usr/bin/grep -Eq '^[0-9]+$' "$(run_dir)/speech.pid" && echo yes || echo no)"
omc_wait_for "/usr/bin/grep -q '\"type\":\"done\"' \"$(run_dir)/events.jsonl\""
omc_wait_for "! /bin/kill -0 \$(/bin/cat \"$(run_dir)/speech.pid\") 2>/dev/null"
poll_tick
check "the transcript is one line per segment, trimmed, tabs flattened" \
    "The quick brown fox jumps over the lazy dog.
Speech recognition on a Mac." "$(ui_value "$TRANSCRIPT_EDITOR")"
check "the run finished" "done" "$(/bin/cat "$(run_dir)/state")"
check "every complete event line was consumed, the unknown one included" "8" "$(/bin/cat "$(run_dir)/events.lines")"
check "the status reports the result" \
    "Done: 2 segments, 4.4 s of audio in 0.3 s (16x real time)." "$(ui_value "$STATUS_TEXT")"
check "Export is enabled" "1" "$(ui_enabled "$EXPORT_MENU")"
check "Copy is enabled" "1" "$(ui_enabled "$COPY_BTN")"
check "Stop is disabled again" "0" "$(ui_enabled "$STOP_BTN")"

# ------------------------------------------------------------------------------------------------
section "export converts the finished transcript, adding the extension a name lacks"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_dialog_answer save_as "$OMCTEST_WORK/Subtitles"
omc_run speech.export.srt
check "speech export was asked for srt" \
    "export $(run_dir)/result.json --format srt --output $OMCTEST_WORK/Subtitles.srt" "$(/usr/bin/head -1 "$FAKE_SPEECH_LOG" 2>/dev/null)"
check_exists "the file was written with its extension" "$OMCTEST_WORK/Subtitles.srt"
check "the status says where" "Exported to Subtitles.srt." "$(ui_value "$STATUS_TEXT")"

section "a canceled Save panel exports nothing"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_dialog_answer save_as ""
omc_run speech.export.txt
check_absent "speech was not run" "$FAKE_SPEECH_LOG"

# ------------------------------------------------------------------------------------------------
section "the event reader leaves a half-written line for the next tick"
run="$(run_dir)"
: > "$run/segments.tsv"
/bin/rm -f "$run/events.lines" "$run/reflected"
printf '%s\n' '{"id":0,"text":"first draft","type":"segment.partial"}' > "$run/events.jsonl"
printf '%s' '{"id":0,"text":"first dr' >> "$run/events.jsonl"
lib_call process_events "$(spool)"
check "only the complete line was consumed" "1" "$(/bin/cat "$run/events.lines")"
check "its segment is in the table" "0	partial	first draft" "$(/bin/cat "$run/segments.tsv")"
printf '%s\n' 'aft","type":"segment.final"}' >> "$run/events.jsonl"
printf '%s\n' '{"id":0,"refined_by":"apple.dictation","text":"first draft, refined","type":"segment.refined"}' >> "$run/events.jsonl"
lib_call process_events "$(spool)"
check "the completed line and the next were consumed" "3" "$(/bin/cat "$run/events.lines")"
check "the refinement replaced the final, which replaced the partial" "0	refined	first draft, refined" "$(/bin/cat "$run/segments.tsv")"

section "an unreadable line costs only itself"
printf '%s\n' 'this is not json' '{"id":1,"text":"after the bad line","type":"segment.final"}' >> "$run/events.jsonl"
lib_call process_events "$(spool)"
check "both lines were consumed" "5" "$(/bin/cat "$run/events.lines")"
check "the good line still landed" "after the bad line" "$(/usr/bin/awk -F'\t' '$1 == 1 { print $3 }' "$run/segments.tsv")"
check_grep "the bad line was kept for inspection" "this is not json" "$run/events.unreadable"

# ------------------------------------------------------------------------------------------------
section "a failed transcription says why, once"
alerts_reset
# omc_present_alert is journaled per window, two lines (title, message) per alert; alerts_reset
# does not touch that history.
present_alerts="$OMCTEST_UI/win-$OMC_ACTIONUI_WINDOW_UUID/present_alerts.log"
: > "$present_alerts"
FAKE_SPEECH_MODE=fail
export FAKE_SPEECH_MODE
omc_run speech.transcribe
omc_wait_for "! /bin/kill -0 \$(/bin/cat \"$(run_dir)/speech.pid\") 2>/dev/null"
poll_tick
poll_tick
check "the run failed" "failed" "$(/bin/cat "$(run_dir)/state")"
check "the reason is the error event's message" "cannot decode the recording" "$(/bin/cat "$(run_dir)/error.txt")"
check "the status carries it" "Transcription failed: cannot decode the recording" "$(ui_value "$STATUS_TEXT")"
check "an alert was raised" "Transcription failed" "$(ui_alert_title)"
check "once, not on every tick" "1" "$(/usr/bin/grep -c '^title' "$present_alerts" 2>/dev/null)"
check "Export stays disabled" "0" "$(ui_enabled "$EXPORT_MENU")"
check "Transcribe is available again" "1" "$(ui_enabled "$TRANSCRIBE_BTN")"
unset FAKE_SPEECH_MODE

# ------------------------------------------------------------------------------------------------
section "Stop signals speech and the run ends as stopped, not failed"
FAKE_SPEECH_MODE=hang
export FAKE_SPEECH_MODE
omc_run speech.transcribe
pid="$(/bin/cat "$(run_dir)/speech.pid")"
check "speech is running" "alive" "$(omc_wait_for "/bin/kill -0 $pid 2>/dev/null" && echo alive || echo dead)"
poll_tick
check "Stop is enabled while it runs" "1" "$(ui_enabled "$STOP_BTN")"
check "the model picker is disabled while it runs" "0" "$(ui_enabled "$MODEL_PICKER")"
omc_run speech.stop
check "the process was signaled" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"
poll_tick
check "the run is stopped" "stopped" "$(/bin/cat "$(run_dir)/state")"
check "the status says the transcript is kept" "Stopped. The transcript so far is kept." "$(ui_value "$STATUS_TEXT")"
unset FAKE_SPEECH_MODE
reap_fake

section "Stop never signals a process that is not this bundle's speech"
FAKE_SPEECH_MODE=hang
export FAKE_SPEECH_MODE
omc_run speech.transcribe
fake_pid="$(/bin/cat "$(run_dir)/speech.pid")"
# The argv check needs /bin/ps, which a command sandbox denies. Without this positive case the
# stranger below would be "untouched" for the wrong reason and the section could not fail. The
# fake's argv starts with the speech path only once it has replaced itself with sleep.
omc_wait_for "/bin/ps -p $fake_pid -o args= | /usr/bin/grep -vq transcribe"
check "the applet recognizes its own speech process by argv" "0" "$(lib_call speech_pid_is_ours "$fake_pid"; echo $?)"
/bin/sleep 600 &
stranger=$!
printf '%s' "$stranger" > "$(run_dir)/speech.pid"
omc_run speech.stop
/bin/sleep 0.3
check "the stranger is untouched" "alive" "$(/bin/kill -0 "$stranger" 2>/dev/null && echo alive || echo dead)"
/bin/kill -KILL "$stranger" "$fake_pid" 2>/dev/null
wait "$stranger" 2>/dev/null
unset FAKE_SPEECH_MODE
reap_fake
poll_tick
check "once the recorded process is gone, the run settles as stopped" "stopped" "$(/bin/cat "$(run_dir)/state")"

# ------------------------------------------------------------------------------------------------
section "a dropped file URL is decoded and becomes the recording"
dropped="$OMCTEST_WORK/dropped 50% louder.wav"
printf 'RIFF' > "$dropped"
encoded="$(printf '%s' "$dropped" | /usr/bin/sed 's/%/%25/g; s/ /%20/g')"
omc_trigger "" "" "{\"items\":[\"file://$encoded\"],\"location\":{\"x\":0,\"y\":0}}"
omc_run speech.drop
check "the decoded path is the recording" "$dropped" "$(/bin/cat "$(spool)/source.path")"
check "the previous transcript is gone" "" "$(ui_value "$TRANSCRIPT_EDITOR")"
check_absent "and so is its run" "$(spool)/current"

section "a drop of something that is not a file changes nothing"
omc_trigger "" "" '{"items":["https://example.com/a.wav"],"location":{"x":0,"y":0}}'
omc_run speech.drop
check "the recording is unchanged" "$dropped" "$(/bin/cat "$(spool)/source.path")"

# ------------------------------------------------------------------------------------------------
section "closing the window removes its spool"
omc_run speech.window.cancel
check_absent "the spool is gone" "$(spool)"

section "cumulative: the window was only written through ids it declares"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no table clobbered" "" "$(ui_suspect_writes)"
check "no harness misuse" "" "$(ui_errors)"

reap_fake
omctest_end
