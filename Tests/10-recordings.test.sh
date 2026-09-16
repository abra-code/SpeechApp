#!/bin/sh
# 10-recordings.test.sh - the Recordings tab: recordings handed to a window, added and dropped;
# the model and language pickers; a batch transcribed one recording at a time, each transcript
# saved beside its recording under a name that carries the model; the rules for replacing a
# transcript that is already there; failure, stop, remove, export and closing the window.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

rec1="$OMCTEST_WORK/interview take 1.wav"
rec2="$OMCTEST_WORK/second.m4a"
printf 'RIFF not really audio' > "$rec1"
printf 'M4A not really audio either' > "$rec2"
txt1="$OMCTEST_WORK/interview take 1 - apple.transcriber.txt"
txt2="$OMCTEST_WORK/second - apple.transcriber.txt"

# The record Speech keeps on a transcript it saved, by its tag.
record_tag() { /usr/bin/xattr -p com.abracode.speech.transcript "$1" 2>/dev/null | /usr/bin/cut -d' ' -f1; }

# A recording's row in the table: name <TAB> status <TAB> path.
row_of() { ui_rows "$REC_TABLE" | /usr/bin/awk -F'\t' -v path="$1" '$3 == path { print $1 "|" $2 }'; }
# The sentence behind a row's status, which the status line shows when the recording is selected.
detail_of() { pane_call recordings recording_detail "$(rec_pane)" "$1"; }

# ------------------------------------------------------------------------------------------------
section "a window opened for recordings lists them in the Recordings tab and starts the poller"
reset_state
"$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH set "$rec1
$OMCTEST_WORK/not there.wav
$rec2
$rec1"
omc_run speech.window.init
check_status "init exits cleanly" 0
check_exists "the spool exists" "$(spool)"
check "the existing recordings are listed once each, in order" "$rec1|$rec2" "$(/usr/bin/paste -sd '|' "$(rec_pane)/list.tsv")"
check "the table shows them by name, with an empty status" "2" "$(ui_row_count "$REC_TABLE")"
check "the first row" "interview take 1.wav|" "$(row_of "$rec1")"
check "the Recordings tab is brought forward" "1" "$(ui_value "$TAB_VIEW")"
check "the handoff was consumed" "" "$("$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH get)"
check "Transcribe starts disabled" "0" "$(ui_enabled "$REC_TRANSCRIBE_BTN")"
check "the poller was started for this window and spool" \
    "$OMC_ACTIONUI_WINDOW_UUID|$(spool)" \
    "$(omc_wait_for "[ -s \"$OMCTEST_WORK/poller.args\" ]" && /usr/bin/paste -sd '|' "$OMCTEST_WORK/poller.args")"

# ------------------------------------------------------------------------------------------------
section "the model list keeps only rows that can transcribe now, each marked with its engine"
lib_call load_models "$(spool)"
check "the catalog was read" "0" "$?"
check "four runnable rows: two Apple, Whisper, Nemotron" \
    "apple.dictation apple.transcriber ggml.whisper-large-v3-turbo@q8_0 ggml.nemotron-3.5-asr-streaming-0.6b@q8_0" \
    "$(/usr/bin/cut -f1 "$(rec_pane)/models.tsv" | /usr/bin/paste -sd ' ' -)"
check "the engine is the sixth column" "apple apple ggml ggml" "$(/usr/bin/cut -f6 "$(rec_pane)/models.tsv" | /usr/bin/paste -sd ' ' -)"
pane_call recordings populate_model_picker "$(rec_pane)"
check "apple.transcriber is chosen when nothing is saved" "apple.transcriber" "$(/bin/cat "$(rec_pane)/model.id")"
check "the picker points at it" "2" "$(ui_value "$REC_MODEL_PICKER")"
check "labels carry the engine marker, and a quote is escaped" \
    "[\"Apple dictation (built in)\",\"Apple long-form (built in)\",\"Whisper large-v3-turbo (Q8_0) $ggml_mark\",\"Nemotron \\\"streaming\\\" (Q8_0) $ggml_mark\",\"Download Models...\"]" \
    "$(ui_prop "$REC_MODEL_PICKER" options)"
check "Apple needs a language: no Automatic, sorted by name, Spanish by region" \
    '["English","German","Spanish (Latin America)","Spanish (Spain)"]' "$(ui_prop "$REC_LANGUAGE_PICKER" options)"
check "the locale's language is chosen" "en" "$(/bin/cat "$(rec_pane)/language.tag")"
pane_call recordings refresh_recordings_actions "$(rec_pane)"
check "Transcribe is enabled with recordings and a model" "1" "$(ui_enabled "$REC_TRANSCRIBE_BTN")"
check "Stop is not" "0" "$(ui_enabled "$REC_STOP_BTN")"
check "it is hidden, and Record holds its place" "0|1" "$(ui_visible "$REC_STOP_BTN")|$(ui_visible "$REC_RECORD_BTN")"
check "Remove is not, with nothing selected" "0" "$(ui_enabled "$REC_REMOVE_BTN")"
check "the status says what is ready" \
    "Ready to transcribe 2 recordings with Apple long-form (built in)." "$(ui_value "$REC_STATUS")"

# ------------------------------------------------------------------------------------------------
section "a picker change inside the quiet window is an echo and is ignored"
omc_control "$REC_MODEL_PICKER" 3
omc_run speech.recordings.model.changed
check "the model did not change" "apple.transcriber" "$(/bin/cat "$(rec_pane)/model.id")"

section "a model that identifies languages gets Automatic"
end_quiet_window
omc_control "$REC_MODEL_PICKER" 3
omc_run speech.recordings.model.changed
check "Whisper is chosen" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$(rec_pane)/model.id")"
check "and remembered under the Recordings tab's key" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$SPEECH_APP_SUPPORT/Settings/recordings.model" 2>/dev/null)"
check "Automatic comes first, then names, an unknown code by its tag" \
    '["Automatic","English","Javanese","Polish"]' "$(ui_prop "$REC_LANGUAGE_PICKER" options)"
check "Automatic is chosen" "auto" "$(/bin/cat "$(rec_pane)/language.tag")"

section "a region-tagged model shows the tag, and a saved language finds it by primary subtag"
end_quiet_window
omc_control "$REC_LANGUAGE_PICKER" 4
omc_run speech.recordings.language.changed
check "Polish is saved as a tag" "pl" "$(/bin/cat "$SPEECH_APP_SUPPORT/Settings/recordings.language" 2>/dev/null)"
end_quiet_window
omc_control "$REC_MODEL_PICKER" 4
omc_run speech.recordings.model.changed
check "the region tags are shown" '["English (en-US)","Polish (pl-PL)"]' "$(ui_prop "$REC_LANGUAGE_PICKER" options)"
check "saved pl selects pl-PL" "pl-PL" "$(/bin/cat "$(rec_pane)/language.tag")"

section "a picker index that resolves to nothing changes nothing"
end_quiet_window
omc_control "$REC_MODEL_PICKER" 99
omc_run speech.recordings.model.changed
check "the model is unchanged" "ggml.nemotron-3.5-asr-streaming-0.6b@q8_0" "$(/bin/cat "$(rec_pane)/model.id")"
omc_control "$REC_MODEL_PICKER" "Whisper"
omc_run speech.recordings.model.changed
check "a title instead of an index is refused too" "ggml.nemotron-3.5-asr-streaming-0.6b@q8_0" "$(/bin/cat "$(rec_pane)/model.id")"

section "back to Apple for the batches below"
end_quiet_window
omc_control "$REC_MODEL_PICKER" 2
omc_run speech.recordings.model.changed
end_quiet_window
omc_control "$REC_LANGUAGE_PICKER" 1
omc_run speech.recordings.language.changed
check "apple.transcriber in English" "apple.transcriber|en" "$(/bin/cat "$(rec_pane)/model.id")|$(/bin/cat "$(rec_pane)/language.tag")"
end_quiet_window

section "Apple's Spanish is Latin American unless Spain is chosen"
omc_control "$REC_LANGUAGE_PICKER" 3
omc_run speech.recordings.language.changed
check "Spanish (Latin America) is es-MX, saved as such" "es-MX|es-MX" \
    "$(/bin/cat "$(rec_pane)/language.tag")|$(/bin/cat "$SPEECH_APP_SUPPORT/Settings/recordings.language" 2>/dev/null)"
end_quiet_window
omc_control "$REC_LANGUAGE_PICKER" 4
omc_run speech.recordings.language.changed
check "Spanish (Spain) is es-ES" "es-ES" "$(/bin/cat "$(rec_pane)/language.tag")"
end_quiet_window
pane_call recordings populate_language_picker "$(rec_pane)"
check "a saved Spain stays Spain" "es-ES" "$(/bin/cat "$(rec_pane)/language.tag")"
printf 'es' > "$SPEECH_APP_SUPPORT/Settings/recordings.language"
pane_call recordings populate_language_picker "$(rec_pane)"
check "a saved Spanish with no region is Latin American" "es-MX" "$(/bin/cat "$(rec_pane)/language.tag")"

section "a Spanish with no region prefers a Latin American spelling on any engine"
/bin/cp -f "$(rec_pane)/models.tsv" "$OMCTEST_WORK/models.tsv.keep"
printf 'ggml.spanish@q8_0\tSpanish model\tes-ES,es-US\tbatch\t-\tggml\n' >> "$(rec_pane)/models.tsv"
printf 'ggml.spanish@q8_0' > "$(rec_pane)/model.id"
pane_call recordings populate_language_picker "$(rec_pane)"
check "the model's own spellings are offered as they are" '["Spanish (es-ES)","Spanish (es-US)"]' "$(ui_prop "$REC_LANGUAGE_PICKER" options)"
check "saved es selects es-US, not the first listed" "es-US" "$(/bin/cat "$(rec_pane)/language.tag")"
printf 'ggml.whisper-es\tWhisper Spanish\ten,es\tbatch\t-\tggml\n' >> "$(rec_pane)/models.tsv"
printf 'ggml.whisper-es' > "$(rec_pane)/model.id"
printf 'es-MX' > "$SPEECH_APP_SUPPORT/Settings/recordings.language"
pane_call recordings populate_language_picker "$(rec_pane)"
check "a saved es-MX, what Apple's Spanish saves, still finds a model's bare es" "es" "$(/bin/cat "$(rec_pane)/language.tag")"
printf 'ggml.spanish@q8_0' > "$(rec_pane)/model.id"
pane_call recordings populate_language_picker "$(rec_pane)"
check "a saved es-MX on a model with other regions takes the Latin American one" "es-US" "$(/bin/cat "$(rec_pane)/language.tag")"
/bin/mv -f "$OMCTEST_WORK/models.tsv.keep" "$(rec_pane)/models.tsv"
printf 'apple.transcriber' > "$(rec_pane)/model.id"
printf 'en' > "$SPEECH_APP_SUPPORT/Settings/recordings.language"
pane_call recordings populate_language_picker "$(rec_pane)"
check "back in English for the batches below" "apple.transcriber|en" "$(/bin/cat "$(rec_pane)/model.id")|$(/bin/cat "$(rec_pane)/language.tag")"
end_quiet_window

# ------------------------------------------------------------------------------------------------
section "Transcribe queues every recording; the poller transcribes them one at a time"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.recordings.transcribe
check_status "transcribe exits cleanly" 0
check "the batch is running" "running" "$(/bin/cat "$(rec_pane)/batch")"
check "both recordings wait" "interview take 1.wav|Waiting" "$(row_of "$rec1")"
check_absent "the handler started no process: the poller starts each recording" "$FAKE_SPEECH_LOG"
check "Transcribe is disabled" "0" "$(ui_enabled "$REC_TRANSCRIBE_BTN")"
check "Stop is enabled, shown in Record's place" "1|1|0" "$(ui_enabled "$REC_STOP_BTN")|$(ui_visible "$REC_STOP_BTN")|$(ui_visible "$REC_RECORD_BTN")"
check "the pickers are disabled" "0" "$(ui_enabled "$REC_MODEL_PICKER")"
poll_tick
check "the first tick started only the first recording, with its model and language" \
    "--json transcribe $rec1 --model apple.transcriber --language en --format json --output $(item_dir "$rec1")/result.json" \
    "$(omc_wait_for "[ -s \"$FAKE_SPEECH_LOG\" ]" && /usr/bin/paste -sd '|' "$FAKE_SPEECH_LOG")"
check "its row says so" "interview take 1.wav|Transcribing" "$(row_of "$rec1")"
check "the other still waits" "second.m4a|Waiting" "$(row_of "$rec2")"
check "the recording's fingerprint was taken" "yes" "$(/usr/bin/grep -Eq '^[0-9a-f]{16}$' "$(item_dir "$rec1")/recording.fp" && echo yes || echo no)"
run_batch
check "the batch ran to its end" "0" "$?"
check "two recordings were transcribed, one after the other" "2" "$(/usr/bin/grep -c ' transcribe ' "$FAKE_SPEECH_LOG")"
check "the status sums it up" "Done. 2 saved beside the recordings." "$(ui_value "$REC_STATUS")"
check_exists "the first transcript is beside its recording, named after the model" "$txt1"
check_exists "and the second" "$txt2"
check "it is the text export of that recording's transcript" \
    "Transcript from $(item_dir "$rec1")/result.json as txt" "$(/bin/cat "$txt1")"
check "Speech's record is on it" "speech-transcript-v1" "$(record_tag "$txt1")"
check "no hidden temporary file is left behind" "" "$(/bin/ls -A "$OMCTEST_WORK" | /usr/bin/grep '\.speech-')"
check "the row says where it went" "interview take 1.wav|Saved|The transcript of interview take 1.wav is saved beside it as interview take 1 - apple.transcriber.txt." "$(row_of "$rec1")|$(detail_of "$rec1")"
check "Transcribe is available again" "1" "$(ui_enabled "$REC_TRANSCRIBE_BTN")"
check "Stop is disabled again" "0" "$(ui_enabled "$REC_STOP_BTN")"
check "and hidden, with Record back" "0|1" "$(ui_visible "$REC_STOP_BTN")|$(ui_visible "$REC_RECORD_BTN")"
check "the summary stays until something changes" "Done. 2 saved beside the recordings." "$(ui_value "$REC_STATUS")"

section "selecting a recording shows its transcript, and Export and Copy work on it"
omc_table_cell "$REC_TABLE" 3 "$rec1"
omc_run speech.recordings.selected
check "the status line says what Saved stands for" \
    "The transcript of interview take 1.wav is saved beside it as interview take 1 - apple.transcriber.txt." "$(ui_value "$REC_STATUS")"
pane_call recordings set_status "Transcribing second.m4a... 40%"
omc_run speech.recordings.selected
check "the table's own re-selection of the same row says nothing again" "Transcribing second.m4a... 40%" "$(ui_value "$REC_STATUS")"
end_quiet_window
omc_table_cell "$REC_TABLE" 3 ""
omc_run speech.recordings.selected
check "selecting nothing takes the detail away" "no note" "$(/bin/cat "$(rec_pane)/status.note" 2>/dev/null || echo no note)"
omc_table_cell "$REC_TABLE" 3 "$rec1"
omc_run speech.recordings.selected
check "the transcript is one line per segment, trimmed, tabs flattened" \
    "The quick brown fox jumps over the lazy dog.
Speech recognition on a Mac." "$(ui_value "$REC_TRANSCRIPT")"
check "Export is enabled" "1" "$(ui_enabled "$REC_EXPORT_MENU")"
check "Copy is enabled" "1" "$(ui_enabled "$REC_COPY_BTN")"
check "Remove is enabled" "1" "$(ui_enabled "$REC_REMOVE_BTN")"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_dialog_answer save_as "$OMCTEST_WORK/Subtitles"
omc_run speech.recordings.export.srt
check "speech export was asked for srt of that recording, the extension added" \
    "export $(item_dir "$rec1")/result.json --format srt --output $OMCTEST_WORK/Subtitles.srt" "$(/usr/bin/head -1 "$FAKE_SPEECH_LOG" 2>/dev/null)"
check "the status says where" "Exported to Subtitles.srt." "$(ui_value "$REC_STATUS")"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_dialog_answer save_as ""
omc_run speech.recordings.export.txt
check_absent "a canceled Save panel exports nothing" "$FAKE_SPEECH_LOG"

section "a selection that is not in the list is ignored, and an empty one is an echo while quiet"
# The batch's last table render is seconds old; close its quiet window so this acts as the user.
end_quiet_window
omc_table_cell "$REC_TABLE" 3 "$OMCTEST_WORK/elsewhere.wav"
omc_run speech.recordings.selected
check_absent "a path not in the list clears the selection" "$(rec_pane)/selected.key"
omc_table_cell "$REC_TABLE" 3 "$rec1"
omc_run speech.recordings.selected
pane_call recordings quiet_begin "$(rec_pane)" table
omc_table_cell "$REC_TABLE" 3 ""
omc_run speech.recordings.selected
check_exists "an empty selection right after rows were replaced keeps the selection" "$(rec_pane)/selected.key"
end_quiet_window
omc_run speech.recordings.selected
check_absent "the same empty selection later clears it" "$(rec_pane)/selected.key"
check "and the transcript" "" "$(ui_value "$REC_TRANSCRIPT")"

# ------------------------------------------------------------------------------------------------
section "running again with the same model replaces Speech's own untouched transcripts"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.recordings.transcribe
run_batch
check "both were saved again" "Done. 2 saved beside the recordings." "$(ui_value "$REC_STATUS")"
check "the row says so" "interview take 1.wav|Saved|The transcript of interview take 1.wav is saved beside it as interview take 1 - apple.transcriber.txt." "$(row_of "$rec1")|$(detail_of "$rec1")"
check "the record is still on it" "speech-transcript-v1" "$(record_tag "$txt1")"

section "a transcript edited after Speech wrote it is left alone"
printf 'my own correction\n' >> "$txt1"
omc_run speech.recordings.transcribe
run_batch
check "the status points at the reason" \
    "Done. 1 saved beside the recording, 1 not saved - the Status column says why." "$(ui_value "$REC_STATUS")"
check "the row says why" \
    "interview take 1.wav|Not saved|The transcript of interview take 1.wav was not saved: interview take 1 - apple.transcriber.txt was edited after Speech wrote it." "$(row_of "$rec1")|$(detail_of "$rec1")"
check_grep "the edit survives" "my own correction" "$txt1"
check "the other recording was still saved" "second.m4a|Saved|The transcript of second.m4a is saved beside it as second - apple.transcriber.txt." "$(row_of "$rec2")|$(detail_of "$rec2")"
omc_table_cell "$REC_TABLE" 3 "$rec1"
omc_run speech.recordings.selected
check "the unsaved transcript is still in the window" \
    "The quick brown fox jumps over the lazy dog.
Speech recognition on a Mac." "$(ui_value "$REC_TRANSCRIPT")"
check "and can still be exported" "1" "$(ui_enabled "$REC_EXPORT_MENU")"

section "a file of that name that Speech did not write is left alone"
/bin/rm -f "$txt1"
printf 'notes the user wrote\n' > "$txt1"
omc_run speech.recordings.transcribe
run_batch
check "the row says why" \
    "interview take 1.wav|Not saved|The transcript of interview take 1.wav was not saved: interview take 1 - apple.transcriber.txt already exists and was not written by Speech." "$(row_of "$rec1")|$(detail_of "$rec1")"
check "the notes survive" "notes the user wrote" "$(/bin/cat "$txt1")"

section "a transcript of an earlier version of the recording is left alone"
/bin/rm -f "$txt1"
omc_run speech.recordings.transcribe
run_batch
check "saved while nothing is in the way" "interview take 1.wav|Saved|The transcript of interview take 1.wav is saved beside it as interview take 1 - apple.transcriber.txt." "$(row_of "$rec1")|$(detail_of "$rec1")"
printf ' and a longer take' >> "$rec1"
before="$(/bin/cat "$txt1")"
omc_run speech.recordings.transcribe
run_batch
check "the row says why" \
    "interview take 1.wav|Not saved|The transcript of interview take 1.wav was not saved: interview take 1 - apple.transcriber.txt was written from a different version of the recording." "$(row_of "$rec1")|$(detail_of "$rec1")"
check "the old transcript is untouched" "$before" "$(/bin/cat "$txt1")"

section "a recording that changes while it is transcribed is not saved"
/bin/rm -f "$txt1"
FAKE_SPEECH_MODE=hang
export FAKE_SPEECH_MODE
omc_run speech.recordings.transcribe
poll_tick
pid="$(/bin/cat "$(item_dir "$rec1")/speech.pid")"
printf ' edited mid-run' >> "$rec1"
# Settle the hung process as if it had finished: its events and result are the fixture's.
/bin/cat "$FAKE_SPEECH_FIXTURES/transcribe.events.jsonl" > "$(item_dir "$rec1")/events.jsonl"
/bin/cp "$FAKE_SPEECH_FIXTURES/transcribe.result.json" "$(item_dir "$rec1")/result.json"
/bin/kill -KILL "$pid" 2>/dev/null
omc_wait_for "! /bin/kill -0 $pid 2>/dev/null"
unset FAKE_SPEECH_MODE
poll_tick
check "the row says why" "interview take 1.wav|Not saved|The transcript of interview take 1.wav was not saved: the recording changed while it was being transcribed." "$(row_of "$rec1")|$(detail_of "$rec1")"
check_absent "nothing was written" "$txt1"
run_batch
reap_fake

section "another model's transcript sits beside the first"
omc_run speech.recordings.transcribe
run_batch
end_quiet_window
omc_control "$REC_MODEL_PICKER" 3
omc_run speech.recordings.model.changed
check "Whisper is chosen" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$(rec_pane)/model.id")"
check "a model change clears the last summary" "Ready to transcribe 2 recordings with Whisper large-v3-turbo (Q8_0)." "$(ui_value "$REC_STATUS")"
omc_run speech.recordings.transcribe
run_batch
check_exists "Whisper's transcript" "$OMCTEST_WORK/interview take 1 - ggml.whisper-large-v3-turbo@q8_0.txt"
check_exists "beside Apple's" "$txt1"
end_quiet_window
omc_control "$REC_MODEL_PICKER" 2
omc_run speech.recordings.model.changed
end_quiet_window

# ------------------------------------------------------------------------------------------------
section "a recording that fails says why in its row, raises no alert, and the batch goes on"
alerts_reset
present_alerts="$OMCTEST_UI/win-$OMC_ACTIONUI_WINDOW_UUID/present_alerts.log"
: > "$present_alerts"
FAKE_SPEECH_FAIL_FILE="$rec1"
export FAKE_SPEECH_FAIL_FILE
omc_run speech.recordings.transcribe
run_batch
unset FAKE_SPEECH_FAIL_FILE
check "the row carries the error event's message" "interview take 1.wav|Failed|interview take 1.wav could not be transcribed: cannot decode the recording" "$(row_of "$rec1")|$(detail_of "$rec1")"
check "the next recording was still transcribed" "second.m4a|Saved|The transcript of second.m4a is saved beside it as second - apple.transcriber.txt." "$(row_of "$rec2")|$(detail_of "$rec2")"
check "the status counts it" "Done. 1 saved beside the recording, 1 failed - the Status column says why." "$(ui_value "$REC_STATUS")"
check "no alert for one recording among several" "0" "$(/usr/bin/grep -c '^title' "$present_alerts" 2>/dev/null)"

section "a recording that is gone by the time its turn comes fails without starting speech"
rec3="$OMCTEST_WORK/gone soon.wav"
printf 'RIFF' > "$rec3"
omc_drop "$rec3"
omc_run speech.drop
/bin/rm -f "$rec3"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.recordings.transcribe
run_batch
check "its row says so" "gone soon.wav|Failed|gone soon.wav could not be transcribed: The recording is no longer there." "$(row_of "$rec3")|$(detail_of "$rec3")"
check "speech ran for the other two only" "2" "$(/usr/bin/grep -c ' transcribe ' "$FAKE_SPEECH_LOG")"

# ------------------------------------------------------------------------------------------------
section "Stop ends the recording being transcribed and starts no more"
FAKE_SPEECH_MODE=hang
export FAKE_SPEECH_MODE
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.recordings.transcribe
poll_tick
pid="$(/bin/cat "$(item_dir "$rec1")/speech.pid")"
check "speech is running" "alive" "$(omc_wait_for "/bin/kill -0 $pid 2>/dev/null" && echo alive || echo dead)"
omc_wait_for "/bin/ps -p $pid -o args= | /usr/bin/grep -vq transcribe"
omc_run speech.recordings.stop
check "the batch is stopping" "stopping" "$(/bin/cat "$(rec_pane)/batch")"
check "Stop is disabled once pressed" "0" "$(ui_enabled "$REC_STOP_BTN")"
check "the process was signaled" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" && echo dead || echo alive)"
unset FAKE_SPEECH_MODE
poll_tick
check_absent "the batch is over" "$(rec_pane)/batch"
check "the recording being transcribed is marked stopped" "interview take 1.wav|Stopped" "$(row_of "$rec1")"
check "the next one was never started" "second.m4a|" "$(row_of "$rec2")"
check "speech ran once" "1" "$(/usr/bin/grep -c ' transcribe ' "$FAKE_SPEECH_LOG")"
check "the status says it stopped" "Stopped. 0 saved beside the recordings." "$(ui_value "$REC_STATUS")"
reap_fake

section "Stop never signals a process that is not this bundle's speech"
FAKE_SPEECH_MODE=hang
export FAKE_SPEECH_MODE
omc_run speech.recordings.transcribe
poll_tick
fake_pid="$(/bin/cat "$(item_dir "$rec1")/speech.pid")"
# The argv check needs /bin/ps, which a command sandbox denies. Without this positive case the
# stranger below would be "untouched" for the wrong reason and the section could not fail. The
# fake's argv starts with the speech path only once it has replaced itself with sleep.
omc_wait_for "/bin/ps -p $fake_pid -o args= | /usr/bin/grep -vq transcribe"
check "the applet recognizes its own speech process by argv" "0" "$(lib_call speech_pid_is_ours "$fake_pid"; echo $?)"
/bin/sleep 600 &
stranger=$!
printf '%s' "$stranger" > "$(item_dir "$rec1")/speech.pid"
omc_run speech.recordings.stop
/bin/sleep 0.3
check "the stranger is untouched" "alive" "$(/bin/kill -0 "$stranger" 2>/dev/null && echo alive || echo dead)"
/bin/kill -KILL "$stranger" "$fake_pid" 2>/dev/null
wait "$stranger" 2>/dev/null
unset FAKE_SPEECH_MODE
reap_fake
poll_tick
check "once the recorded process is gone, the recording settles as stopped" "interview take 1.wav|Stopped" "$(row_of "$rec1")"

# ------------------------------------------------------------------------------------------------
section "a dropped file URL is decoded and joins the list; anything else is ignored"
dropped="$OMCTEST_WORK/dropped 50% louder.wav"
printf 'RIFF' > "$dropped"
encoded="$(printf '%s' "$dropped" | /usr/bin/sed 's/%/%25/g; s/ /%20/g')"
count_before="$(/usr/bin/awk 'NF' "$(rec_pane)/list.tsv" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
omc_trigger "" "" "{\"items\":[\"file://$encoded\",\"https://example.com/a.wav\",\"$rec2\"],\"location\":{\"x\":0,\"y\":0}}"
omc_run speech.drop
check "the decoded path was added, once" "$((count_before + 1))" "$(/usr/bin/awk 'NF' "$(rec_pane)/list.tsv" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "it is the last in the list" "$dropped" "$(/usr/bin/tail -1 "$(rec_pane)/list.tsv")"
check "and in the table" "dropped 50% louder.wav|" "$(row_of "$dropped")"

section "Add... with several recordings adds them all"
extra1="$OMCTEST_WORK/extra one.wav"
extra2="$OMCTEST_WORK/extra two.wav"
printf 'RIFF' > "$extra1"
printf 'RIFF' > "$extra2"
omc_dialog_answer choose_file "$extra1
$extra2"
omc_run speech.open
check "both were added" "$extra1|$extra2" "$(/usr/bin/tail -2 "$(rec_pane)/list.tsv" | /usr/bin/paste -sd '|' -)"
check "the Recordings tab is brought forward" "1" "$(ui_value "$TAB_VIEW")"

section "a picker change right after the table was refreshed is the user's, not an echo"
# Replacing the table's rows quiets the table's own selection echo; it must not quiet the pickers,
# or a model picked within two seconds of adding a recording would show in the picker and be lost.
omc_control "$REC_MODEL_PICKER" 3
omc_run speech.recordings.model.changed
check "the model changed" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$(rec_pane)/model.id")"
end_quiet_window
omc_control "$REC_MODEL_PICKER" 2
omc_run speech.recordings.model.changed
end_quiet_window

section "Remove takes the selected recording out of the list, and leaves its files alone"
omc_table_cell "$REC_TABLE" 3 "$rec2"
omc_run speech.recordings.selected
omc_run speech.recordings.remove
check "it is no longer listed" "no" "$(/usr/bin/grep -Fxq "$rec2" "$(rec_pane)/list.tsv" && echo yes || echo no)"
check "nor in the table" "" "$(row_of "$rec2")"
check_absent "the selection is gone" "$(rec_pane)/selected.key"
check_exists "the recording itself is still there" "$rec2"
check_exists "and so is its transcript" "$txt2"
check "Remove is disabled with nothing selected" "0" "$(ui_enabled "$REC_REMOVE_BTN")"

section "Remove finds a path with a backslash in it"
slashed="$OMCTEST_WORK/take\\n1.wav"
printf 'RIFF' > "$slashed"
printf '%s\n' "$slashed" >> "$(rec_pane)/list.tsv"
omc_table_cell "$REC_TABLE" 3 "$slashed"
omc_run speech.recordings.selected
omc_run speech.recordings.remove
check "it is no longer listed" "no" "$(/usr/bin/grep -Fxq -- "$slashed" "$(rec_pane)/list.tsv" && echo yes || echo no)"
check "the rest of the list is intact" "yes" "$(/usr/bin/grep -Fxq -- "$rec1" "$(rec_pane)/list.tsv" && echo yes || echo no)"

section "Remove waits while a batch runs"
omc_table_cell "$REC_TABLE" 3 "$rec1"
omc_run speech.recordings.selected
printf 'running' > "$(rec_pane)/batch"
omc_run speech.recordings.remove
check "the recording stays" "yes" "$(/usr/bin/grep -Fxq "$rec1" "$(rec_pane)/list.tsv" && echo yes || echo no)"
check "the status says why" "Stop the transcription before removing a recording from the list." "$(ui_value "$REC_STATUS")"
/bin/rm -f "$(rec_pane)/batch"

# ------------------------------------------------------------------------------------------------
section "a transcript name drops the recording's extension and keeps the model's characters safe"
check "extension dropped, model appended" "take.two - apple.transcriber.txt" "$(lib_call transcript_name_for "/x/take.two.wav" apple.transcriber)"
check "a name without an extension keeps its name" "memo - ggml.whisper-large-v3-turbo@q8_0.txt" "$(lib_call transcript_name_for "/x/memo" ggml.whisper-large-v3-turbo@q8_0)"
check "a slash or colon in a model id cannot leave the folder" ".hidden - a-b-c.txt" "$(lib_call transcript_name_for "/x/.hidden" "a/b:c")"

section "File > Open with no window opens one for the recordings"
chains_reset
saved_uuid="$OMC_ACTIONUI_WINDOW_UUID"
OMC_ACTIONUI_WINDOW_UUID=""
omc_dialog_answer choose_file "$extra1"
omc_run speech.open
OMC_ACTIONUI_WINDOW_UUID="$saved_uuid"
check "a new window was asked for" "1" "$(chain_asked speech.new)"
check "with the recording handed to it" "$extra1" "$("$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH get)"
"$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH set ""

section "closing the window removes its spool"
omc_run speech.window.cancel
check_absent "the spool is gone" "$(spool)"

section "cumulative: the window was only written through ids it declares"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no table clobbered" "" "$(ui_suspect_writes)"
check "no harness misuse" "" "$(ui_errors)"

reap_fake
omctest_end
