#!/bin/sh
# 90-benchmark.test.sh - the Benchmark tab: the corpus, sample and model pickers, the reference
# results for a corpus, a corpus that arrives on disk, the shared queue, the worker measuring it with
# each result or failure recorded, progress and Stop, removing a waiting measurement, and a
# measurement taken while a window was transcribing. The fake speech (helpers/fake-speech.sh) answers
# `eval`; the real benchmark worker runs.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

benchmarks="$SPEECH_APP_SUPPORT/Benchmarks"
results="$benchmarks/results.tsv"

bench_pane() { printf '%s/benchmark' "$(spool)"; }
tick() { bench_call poll_benchmark "$(spool)"; }
end_bench_quiet() { /bin/rm -f "$(bench_pane)/picker_quiet" "$(bench_pane)/table_quiet"; }
label_of() { /usr/bin/jq -r --arg id "$1" '.rows[] | select(.id == $id) | .label' "$OMCTEST_FIXTURES/catalog.json"; }
queued() { /bin/ls "$benchmarks/queue" 2>/dev/null | /usr/bin/sed 's/\.cell$//'; }
queued_count() { queued | /usr/bin/awk 'END { print NR }'; }
eval_lines() { /bin/cat "$FAKE_SPEECH_LOG" 2>/dev/null | /usr/bin/grep -c -- "--json eval"; }
result_field() { /usr/bin/awk -F'\t' -v line="$1" -v col="$2" 'NR == line { print $col; exit }' "$results"; }   # $1 = line, $2 = column
result_lines() { /usr/bin/awk 'END { print NR }' "$results" 2>/dev/null; }
table_row() { ui_rows "$1" | /usr/bin/sed -n "${2}p"; }   # $1 = table, $2 = row
table_cell() { table_row "$1" "$2" | /usr/bin/awk -F'\t' -v col="$3" '{ print $col }'; }   # $1 = table, $2 = row, $3 = column
worker_done() { omc_wait_for "[ ! -f \"$benchmarks/worker/state\" ]" && echo yes || echo no; }
check_contains() { case "$3" in *"$2"*) check "$1" yes yes ;; *) check "$1" "$2" "$3" ;; esac; }   # $1 = description, $2 = expected part, $3 = actual

open_window() {
    reset_state
    omc_run speech.window.init
    load_window_models
    bench_call setup_benchmark "$(spool)"
    end_bench_quiet
}

put_polish_corpus() {
    /bin/mkdir -p "$SPEECH_APP_SUPPORT/Corpora/fleurs/pl_pl"
    printf 'a.wav\tala ma kota\tpl-PL\nb.wav\tto jest test\tpl-PL\nc.wav\tdzien dobry\tpl-PL\n' \
        > "$SPEECH_APP_SUPPORT/Corpora/fleurs/pl_pl/manifest.tsv"
}

choose() {   # $1 = picker, $2 = 1-based option, $3 = handler
    end_bench_quiet
    omc_control "$1" "$2"
    omc_run "$3"
}

this_macos="$(/usr/bin/sw_vers -productVersion)"
this_chip="$(/usr/sbin/sysctl -n machdep.cpu.brand_string)"
today="$(/bin/date -u +%Y-%m-%d)"
ggml_whisper="$(label_of ggml.whisper-large-v3-turbo@q8_0) $ggml_mark"
ggml_nemotron="$(label_of ggml.nemotron-3.5-asr-streaming-0.6b@q8_0) $ggml_mark"
dictation="$(label_of apple.dictation)"

# ------------------------------------------------------------------------------------------------
section "With no corpus on this Mac, the tab starts on the first one and says where it looks"
open_window
tick
check "the first corpus is chosen" "cmn_hans_cn" "$(/bin/cat "$(bench_pane)/corpus.id" 2>/dev/null)"
corpus_options="$(ui_prop "$BENCH_CORPUS_PICKER" options)"
check_contains "the corpora with reference results come first, each marked as not on this Mac" \
    "[\"FLEURS Chinese (Mandarin)$download_mark\",\"FLEURS English (US)$download_mark\",\"FLEURS French$download_mark\",\"FLEURS German$download_mark\",\"FLEURS Polish$download_mark\",\"FLEURS Spanish (Latin America)$download_mark\",\"LibriSpeech test-clean (English, clear speech)$download_mark\",\"LibriSpeech test-other (English, harder speech)$download_mark\"," \
    "$corpus_options"
check_contains "and the rest of the FLEURS languages follow, by name" \
    "\"FLEURS Afrikaans$download_mark\",\"FLEURS Amharic$download_mark\",\"FLEURS Arabic (Egypt)$download_mark\"," \
    "$corpus_options"
check "every FLEURS language FLEURS has a test split for is offered" "102" \
    "$(printf '%s' "$corpus_options" | /usr/bin/grep -o '"FLEURS ' | /usr/bin/grep -c .)"
check "and both LibriSpeech splits" "2" \
    "$(printf '%s' "$corpus_options" | /usr/bin/grep -o '"LibriSpeech ' | /usr/bin/grep -c .)"
check "a quick sample is the default size" "100" "$(/bin/cat "$(bench_pane)/sample" 2>/dev/null)"
check "the sizes name the corpus's recordings" '["Quick sample (100 recordings)","Full set (945 recordings)"]' "$(ui_prop "$BENCH_SAMPLE_PICKER" options)"
check "no model here transcribes Chinese" '["No models for this language","Download Models..."]' "$(ui_prop "$BENCH_MODEL_PICKER" options)"
check "Add is disabled" "0" "$(ui_enabled "$BENCH_ADD_BTN")"
check "Run is disabled" "0" "$(ui_enabled "$BENCH_RUN_BTN")"
check "the pickers are enabled" "1 1 1" "$(ui_enabled "$BENCH_CORPUS_PICKER") $(ui_enabled "$BENCH_SAMPLE_PICKER") $(ui_enabled "$BENCH_MODEL_PICKER")"
check "the status offers the download, with its size" \
    "FLEURS Chinese (Mandarin) is not on this Mac yet. Press Download to get it (525 MB)." \
    "$(ui_value "$BENCH_STATUS")"
check "Download is enabled" "1" "$(ui_enabled "$BENCH_DOWNLOAD_BTN")"
check "the reference has nothing for it" "0" "$(ui_row_count "$BENCH_RESULTS_TABLE")"

section "Choosing Polish offers the models that speak it, and the reference results for it"
choose "$BENCH_CORPUS_PICKER" 5 speech.benchmark.corpus.changed
check_status "the handler exits cleanly" 0
check "the corpus is Polish" "pl_pl" "$(/bin/cat "$(bench_pane)/corpus.id" 2>/dev/null)"
check "and saved" "pl_pl" "$(/bin/cat "$SPEECH_APP_SUPPORT/Settings/benchmark.corpus" 2>/dev/null)"
check "the full set is Polish's size" '["Quick sample (100 recordings)","Full set (758 recordings)"]' "$(ui_prop "$BENCH_SAMPLE_PICKER" options)"
check "the models that transcribe Polish files, whatever region they spell" \
    "apple.dictation ggml.whisper-large-v3-turbo@q8_0 ggml.nemotron-3.5-asr-streaming-0.6b@q8_0" \
    "$(/usr/bin/cut -f1 "$(bench_pane)/models.tsv" | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "the first is selected" "apple.dictation" "$(/bin/cat "$(bench_pane)/model.id" 2>/dev/null)"
check "three reference rows for Polish" "3" "$(ui_row_count "$BENCH_RESULTS_TABLE")"
check "the lowest error rate first, with the engine's mark" \
    "$ggml_nemotron	9.50%	4.00%	110.4x	1.3 GB	758 (2 skipped)	Reference, Reference Mac, macOS 26.6.2, 2026-09-09	" \
    "$(table_row "$BENCH_RESULTS_TABLE" 1)"
check "Apple's row for this macOS has no note" "" "$(table_cell "$BENCH_RESULTS_TABLE" 2 8)"
check "Apple's row for another macOS says so" \
    "Measured on macOS 25.1. Apple's engines change with macOS, and this Mac runs 26.6.2." \
    "$(table_cell "$BENCH_RESULTS_TABLE" 3 8)"
check "Add waits for the corpus" "0" "$(ui_enabled "$BENCH_ADD_BTN")"

section "A corpus that arrives on disk is noticed on the next tick"
put_polish_corpus
tick
check_contains "Polish is on this Mac now" '"FLEURS Polish",' "$(ui_prop "$BENCH_CORPUS_PICKER" options)"
check "Add is enabled" "1" "$(ui_enabled "$BENCH_ADD_BTN")"
check "Download is disabled for a corpus on this Mac" "0" "$(ui_enabled "$BENCH_DOWNLOAD_BTN")"
check "the status says what to do" \
    "Add models to the queue, then press Run. Results from this Mac are listed above the reference results." \
    "$(ui_value "$BENCH_STATUS")"

# ------------------------------------------------------------------------------------------------
section "Add to Queue queues the tab's model, corpus and size, once each"
omc_run speech.benchmark.add
check_status "add exits cleanly" 0
check "one measurement is waiting" "1" "$(queued_count)"
check "it names the model, the corpus and the size" "apple.dictation	pl_pl	100" "$(/bin/cat "$benchmarks/queue/$(queued).cell" 2>/dev/null)"
check "the queue table shows it waiting" "$dictation	FLEURS Polish, quick sample	Waiting" \
    "$(table_row "$BENCH_QUEUE_TABLE" 1 | /usr/bin/cut -f1-3)"
check "Run is enabled" "1" "$(ui_enabled "$BENCH_RUN_BTN")"
check "the status counts it" "1 measurement is waiting. Press Run to measure it." "$(ui_value "$BENCH_STATUS")"
omc_run speech.benchmark.add
check "the same one is not queued twice" "1" "$(queued_count)"
check "and the status says so" "$dictation on FLEURS Polish, quick sample, is already waiting in the queue." "$(ui_value "$BENCH_STATUS")"
tick
check "which the next tick leaves in place" "$dictation on FLEURS Polish, quick sample, is already waiting in the queue." "$(ui_value "$BENCH_STATUS")"
choose "$BENCH_SAMPLE_PICKER" 2 speech.benchmark.sample.changed
check "the full set is chosen and saved" "all all" "$(/bin/cat "$(bench_pane)/sample") $(/bin/cat "$SPEECH_APP_SUPPORT/Settings/benchmark.sample")"
omc_run speech.benchmark.add
check "the full set is another measurement" "2" "$(queued_count)"
check "in the order they were added" "100 all" \
    "$(for name in $(queued); do /usr/bin/cut -f3 "$benchmarks/queue/$name.cell"; done | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "the status counts both" "2 measurements are waiting. Press Run to measure them one after another." "$(ui_value "$BENCH_STATUS")"

section "Run measures the queue in order and records each result"
omc_run speech.benchmark.run
check_status "run exits cleanly" 0
check "the worker finished" "yes" "$(worker_done)"
check "the queue is empty" "0" "$(queued_count)"
check "speech measured twice" "2" "$(eval_lines)"
check "the quick sample is the first 100 recordings, in the corpus's language" "1" \
    "$(/usr/bin/grep -c -- "--json eval --model apple.dictation --manifest $SPEECH_APP_SUPPORT/Corpora/fleurs/pl_pl/manifest.tsv --language pl-PL --limit 100 --report" "$FAKE_SPEECH_LOG")"
check "the full set has no limit" "1" "$(/usr/bin/grep -- "--json eval" "$FAKE_SPEECH_LOG" | /usr/bin/grep -vc -- "--limit")"
check "a header and two results" "3" "$(result_lines)"
check "the header is the reference's columns and then this app's" \
    "model corpus macos language resolved_locales rows skipped wer_pct cer_pct rtfx audio_seconds wall_seconds load_seconds peak_memory_bytes peak_footprint_bytes peak_neural_bytes reference_words reference_characters substitutions deletions insertions character_errors date machine speech_version sample status note" \
    "$(/usr/bin/head -1 "$results" | /usr/bin/tr '\t' ' ')"
check "the first result, from speech's summary" \
    "apple.dictation pl_pl 26.6.2 pl-PL pl_PL 3 0 8.33 5.12 42.4 31.4 0.7 0.07 480000000" \
    "$(/usr/bin/sed -n 2p "$results" | /usr/bin/cut -f1-14 | /usr/bin/tr '\t' ' ')"
check "with its date, machine, speech, size and status" "2026-01-01T10:00:00Z|Apple M5|speech 0.1.0|100|ok|" \
    "$(/usr/bin/sed -n 2p "$results" | /usr/bin/cut -f23-28 | /usr/bin/tr '\t' '|')"
check "the second is the full set" "all" "$(result_field 3 26)"
check "a finished measurement leaves no run behind" "0" "$(/bin/ls "$benchmarks/runs" 2>/dev/null | /usr/bin/awk 'END { print NR }')"
tick
check "this Mac's result is listed above the reference" \
    "$dictation	8.33%	5.12%	42.4x	480 MB	3	Apple M5, macOS 26.6.2, 2026-01-01	" \
    "$(table_row "$BENCH_RESULTS_TABLE" 1)"
check "the reference rows follow" "4" "$(ui_row_count "$BENCH_RESULTS_TABLE")"
check "the queue table is empty" "0" "$(ui_row_count "$BENCH_QUEUE_TABLE")"
check "Run is disabled again" "0" "$(ui_enabled "$BENCH_RUN_BTN")"

section "A failed measurement is recorded with speech's reason, and replaces the model's row"
FAKE_SPEECH_EVAL=fail
export FAKE_SPEECH_EVAL
omc_run speech.benchmark.add
omc_run speech.benchmark.run
check "the worker finished" "yes" "$(worker_done)"
check "the failure left the queue" "0" "$(queued_count)"
check "it is recorded as failed, for the full set" "failed|all" "$(result_field 4 27)|$(result_field 4 26)"
check "with speech's reason" "no rows could be scored, so there is no measurement: cannot decode the recording" "$(result_field 4 28)"
check "and no figures" "||" "$(result_field 4 8)|$(result_field 4 10)|$(result_field 4 14)"
check "but what was asked, where and when" "apple.dictation|pl_pl|$this_macos|pl-PL|speech 0.1.0" \
    "$(result_field 4 1)|$(result_field 4 2)|$(result_field 4 3)|$(result_field 4 4)|$(result_field 4 25)"
check_exists "the failed run is kept for a look" "$benchmarks/runs"
tick
# The failure is stamped with this Mac's real macOS, but the fixture catalog says this Mac runs
# 26.6.2, so on any other macOS the row also carries the note for an Apple row from another version.
failed_note=""
[ "$this_macos" = "26.6.2" ] ||
    failed_note=" Measured on macOS $this_macos. Apple's engines change with macOS, and this Mac runs 26.6.2."
check "the model's newest measurement is the failure, above the reference" \
    "$dictation	Failed	-	-	-	-	$this_chip, macOS $this_macos, $today	no rows could be scored, so there is no measurement: cannot decode the recording$failed_note" \
    "$(table_row "$BENCH_RESULTS_TABLE" 1)"
check "the older result is not listed twice" "4" "$(ui_row_count "$BENCH_RESULTS_TABLE")"
choose "$BENCH_SAMPLE_PICKER" 1 speech.benchmark.sample.changed
check "the quick sample's result is unaffected" "8.33%" "$(table_cell "$BENCH_RESULTS_TABLE" 1 2)"
unset FAKE_SPEECH_EVAL

# ------------------------------------------------------------------------------------------------
section "While measuring: progress in the queue and the status line; Stop keeps it queued"
FAKE_SPEECH_EVAL=hang
export FAKE_SPEECH_EVAL
choose "$BENCH_MODEL_PICKER" 2 speech.benchmark.model.changed
check "Whisper is chosen" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$(bench_pane)/model.id" 2>/dev/null)"
omc_run speech.benchmark.add
name="$(queued)"
omc_run speech.benchmark.run
check "the first recording is scored" "yes" \
    "$(omc_wait_for "/usr/bin/grep -q eval.row \"$benchmarks/runs/$name/events.jsonl\" 2>/dev/null" && echo yes || echo no)"
tick
check "the queue row shows the progress" "1 of 3 recordings, about 50% WER so far" "$(table_cell "$BENCH_QUEUE_TABLE" 1 3)"
check "and so does the status line, with the plain label" \
    "Measuring $(label_of ggml.whisper-large-v3-turbo@q8_0) on FLEURS Polish, quick sample: 1 of 3 recordings, about 50% WER so far." \
    "$(ui_value "$BENCH_STATUS")"
check "Run is disabled and Stop enabled" "0 1" "$(ui_enabled "$BENCH_RUN_BTN") $(ui_enabled "$BENCH_STOP_BTN")"
check "more can still be added" "1" "$(ui_enabled "$BENCH_ADD_BTN")"
end_bench_quiet
omc_table_cell "$BENCH_QUEUE_TABLE" 4 "$name"
omc_run speech.benchmark.queue.selected
check "the running measurement is selected" "$name" "$(/bin/cat "$(bench_pane)/queue.selected" 2>/dev/null)"
check "but cannot be removed" "0" "$(ui_enabled "$BENCH_REMOVE_BTN")"
omc_run speech.benchmark.remove
check "remove refuses it" "That measurement is in progress. Stop it before removing it from the queue." "$(ui_value "$BENCH_STATUS")"
check "it is still queued" "1" "$(queued_count)"
lines_before="$(result_lines)"
omc_run speech.benchmark.stop
check_status "stop exits cleanly" 0
check "Stop disables itself" "0" "$(ui_enabled "$BENCH_STOP_BTN")"
check "the worker ended" "yes" "$(worker_done)"
check "the measurement stays in the queue" "$name" "$(queued)"
check "nothing was recorded for it" "$lines_before" "$(result_lines)"
check "speech was stopped" "no" "$(/usr/bin/pgrep -f "$SPEECH_BIN" > /dev/null && echo yes || echo no)"
tick
check "the queue row is waiting again" "Waiting" "$(table_cell "$BENCH_QUEUE_TABLE" 1 3)"
check "Run is offered again" "1" "$(ui_enabled "$BENCH_RUN_BTN")"
reap_fake

section "A Stop that reached the worker but not its speech process is caught within seconds"
omc_run speech.benchmark.run
check "the first recording is scored" "yes" \
    "$(omc_wait_for "/usr/bin/grep -q eval.row \"$benchmarks/runs/$name/events.jsonl\" 2>/dev/null" && echo yes || echo no)"
# What stop_benchmark leaves when speech.pid was not there yet to signal: the request alone.
: > "$benchmarks/worker/stop.request"
check "the worker ended" "yes" "$(omc_wait_for "[ ! -f \"$benchmarks/worker/state\" ]" 8 && echo yes || echo no)"
check "speech was stopped" "no" "$(/usr/bin/pgrep -f "$SPEECH_BIN" > /dev/null && echo yes || echo no)"
check "the measurement stays in the queue" "$name" "$(queued)"
check "nothing was recorded for it" "$lines_before" "$(result_lines)"
unset FAKE_SPEECH_EVAL
reap_fake

section "Remove takes a waiting measurement out of the queue"
end_bench_quiet
omc_table_cell "$BENCH_QUEUE_TABLE" 4 "$name"
omc_run speech.benchmark.queue.selected
check "Remove is enabled" "1" "$(ui_enabled "$BENCH_REMOVE_BTN")"
omc_run speech.benchmark.remove
check_status "remove exits cleanly" 0
check "the queue is empty" "0" "$(queued_count)"
check "and so is its table" "0" "$(ui_row_count "$BENCH_QUEUE_TABLE")"
check "the selection is forgotten" "no" "$([ -f "$(bench_pane)/queue.selected" ] && echo yes || echo no)"

section "A measurement taken while a window transcribes says its speed may suffer"
/bin/mkdir -p "$SPEECH_APP_SUPPORT/Sessions/other-window/recordings"
printf 'running' > "$SPEECH_APP_SUPPORT/Sessions/other-window/recordings/batch"
omc_run speech.benchmark.add
omc_run speech.benchmark.run
check "the worker finished" "yes" "$(worker_done)"
check "the result carries the note" \
    "Speech was transcribing in a window or downloading a corpus during this measurement, so its speed and memory may be worse than this Mac can do." \
    "$(result_field "$(result_lines)" 28)"
/bin/rm -rf "$SPEECH_APP_SUPPORT/Sessions/other-window"

section "A queue entry for a corpus that is gone fails without running speech"
before="$(eval_lines)"
omc_run speech.benchmark.add
/bin/rm -rf "$SPEECH_APP_SUPPORT/Corpora/fleurs/pl_pl"
omc_run speech.benchmark.run
check "the worker finished" "yes" "$(worker_done)"
check "speech was not asked" "$before" "$(eval_lines)"
check "the failure says why" "failed|FLEURS Polish is not on this Mac." "$(result_field "$(result_lines)" 27)|$(result_field "$(result_lines)" 28)"

section "A speech that crashes is a failure, not a stop to run again"
put_polish_corpus
FAKE_SPEECH_EVAL=crash
export FAKE_SPEECH_EVAL
omc_run speech.benchmark.add
omc_run speech.benchmark.run
check "the worker finished" "yes" "$(worker_done)"
check "the crash left the queue" "0" "$(queued_count)"
check "it is recorded with the signal" "failed|speech ended on signal 6 and did not say why." \
    "$(result_field "$(result_lines)" 27)|$(result_field "$(result_lines)" 28)"
unset FAKE_SPEECH_EVAL

section "A FLEURS language speech has never measured is offered with its own size"
choose "$BENCH_CORPUS_PICKER" 9 speech.benchmark.corpus.changed
check "the ninth corpus is the first FLEURS language by name" "af_za" "$(/bin/cat "$(bench_pane)/corpus.id" 2>/dev/null)"
check "the full set is its own size" '["Quick sample (100 recordings)","Full set (264 recordings)"]' "$(ui_prop "$BENCH_SAMPLE_PICKER" options)"
check "the status offers the download, with its size" \
    "FLEURS Afrikaans is not on this Mac yet. Press Download to get it (156 MB)." \
    "$(ui_value "$BENCH_STATUS")"
check "Download is enabled" "1" "$(ui_enabled "$BENCH_DOWNLOAD_BTN")"

# Spanish rather than one of the new languages: this branch turns on the reference file having no row
# for the corpus, and the fixture reference (en_us and pl_pl) is what the tab reads here. A new FLEURS
# language would also need a fixture model that speaks it, which would rewrite the language picker's
# options in 10-recordings for no gain.
section "A corpus the reference file has no row for says the table is this Mac's alone"
choose "$BENCH_CORPUS_PICKER" 6 speech.benchmark.corpus.changed
/bin/mkdir -p "$SPEECH_APP_SUPPORT/Corpora/fleurs/es_419"
printf 'a.wav\tbuenos dias\tes-419\n' > "$SPEECH_APP_SUPPORT/Corpora/fleurs/es_419/manifest.tsv"
tick
check "the corpus is Spanish" "es_419" "$(/bin/cat "$(bench_pane)/corpus.id" 2>/dev/null)"
check "the reference has no row for it" "0" "$(ui_row_count "$BENCH_RESULTS_TABLE")"
check "and the status says so" \
    "Add models to the queue, then press Run. No reference results are published for FLEURS Spanish (Latin America), so the table shows this Mac's measurements alone." \
    "$(ui_value "$BENCH_STATUS")"

section "With nothing saved, the tab opens on the first corpus that is on this Mac"
reset_state
omc_run speech.window.init
load_window_models
put_polish_corpus
bench_call setup_benchmark "$(spool)"
end_bench_quiet
check "the fifth corpus, not the first" "pl_pl" "$(/bin/cat "$(bench_pane)/corpus.id" 2>/dev/null)"
check "and the picker is on it" "5" "$(ui_value "$BENCH_CORPUS_PICKER")"

omctest_end
