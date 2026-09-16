#!/bin/sh
# 91-corpus-download.test.sh - downloading a standard corpus from the Benchmark tab: the Download
# button and its alert, the worker running speech's fetch tool into the app's Corpora directory, the
# corpus arriving in the picker, a failed download's reason, progress while the archive grows, a
# stopped download ending the tool and what it waits for, the free-space refusal, and a download
# counting as work that competes with a measurement. The fake fetch tools (helpers/fetch-tools) stand
# in for speech's; the real download worker runs.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

corpora="$SPEECH_APP_SUPPORT/Corpora"
downloads="$SPEECH_APP_SUPPORT/CorpusDownloads"

bench_pane() { printf '%s/benchmark' "$(spool)"; }
tick() { bench_call poll_benchmark "$(spool)"; }
end_bench_quiet() { /bin/rm -f "$(bench_pane)/picker_quiet" "$(bench_pane)/table_quiet"; }
fetch_lines() { /bin/cat "$FAKE_FETCH_LOG" 2>/dev/null | /usr/bin/awk 'END { print NR }'; }
check_contains() { case "$3" in *"$2"*) check "$1" yes yes ;; *) check "$1" "$2" "$3" ;; esac; }   # $1 = description, $2 = expected part, $3 = actual
download_gone() { omc_wait_for "[ ! -d \"$downloads/$1\" ]" && echo yes || echo no; }   # $1 = corpus id
download_failed() { omc_wait_for "[ \"\$(/bin/cat \"$downloads/$1/state\" 2>/dev/null)\" = failed ]" && echo yes || echo no; }

open_window() {
    reset_state
    alerts_reset
    alert_answers_reset
    /bin/rm -f "$FAKE_FETCH_LOG"
    omc_run speech.window.init
    load_window_models
    bench_call setup_benchmark "$(spool)"
    end_bench_quiet
}

choose() {   # $1 = picker, $2 = 1-based option, $3 = handler
    end_bench_quiet
    omc_control "$1" "$2"
    omc_run "$3"
}

# ------------------------------------------------------------------------------------------------
section "Download asks first, with the sizes, why the full set comes, and the license"
open_window
choose "$BENCH_CORPUS_PICKER" 5 speech.benchmark.corpus.changed
tick
check "Download is enabled for Polish, which is not here" "1" "$(ui_enabled "$BENCH_DOWNLOAD_BTN")"
omc_run speech.benchmark.download
check_status "download exits cleanly" 0
check "the alert names the corpus" "Download FLEURS Polish?" "$(ui_alert_title)"
check "and says what it costs, why, and whose it is" \
    "About 355 MB to download, and 474 MB on this Mac once unpacked. The full set is downloaded even for a quick sample, because it is published as one archive. FLEURS is published by Google on Hugging Face under the CC BY 4.0 license." \
    "$(ui_alert_message)"
check "Download confirms" "speech.benchmark.download.confirm" "$(ui_alert_action Download)"
check "the corpus waits for the answer" "pl_pl" "$(/bin/cat "$(bench_pane)/pending.download" 2>/dev/null)"
check "nothing is fetched before the answer" "0" "$(fetch_lines)"

section "Confirming runs speech's fetch tool into the app's Corpora directory"
omc_run speech.benchmark.download.confirm
check_status "confirm exits cleanly" 0
check "the question is answered" "" "$(/bin/cat "$(bench_pane)/pending.download" 2>/dev/null)"
check "the download finished and left nothing behind" "yes" "$(download_gone pl_pl)"
check "the FLEURS tool fetched Polish into Corpora" "fetch-fleurs.sh pl_pl $corpora" "$(/bin/cat "$FAKE_FETCH_LOG" 2>/dev/null)"
check "the manifest is where the tab looks" "yes" "$([ -s "$corpora/fleurs/pl_pl/manifest.tsv" ] && echo yes || echo no)"
tick
check_contains "Polish is on this Mac now" '"FLEURS Polish",' "$(ui_prop "$BENCH_CORPUS_PICKER" options)"
check "Download is disabled" "0" "$(ui_enabled "$BENCH_DOWNLOAD_BTN")"
check "Add is enabled" "1" "$(ui_enabled "$BENCH_ADD_BTN")"
omc_run speech.benchmark.download
check "a second Download says it is here" "FLEURS Polish is already on this Mac." "$(ui_value "$BENCH_STATUS")"
check "and fetches nothing" "1" "$(fetch_lines)"

section "A LibriSpeech split uses its own tool"
choose "$BENCH_CORPUS_PICKER" 8 speech.benchmark.corpus.changed
omc_run speech.benchmark.download
check "the alert credits OpenSLR" \
    "About 329 MB to download, and 359 MB on this Mac once unpacked. The full set is downloaded even for a quick sample, because it is published as one archive. LibriSpeech is published on OpenSLR under the CC BY 4.0 license." \
    "$(ui_alert_message)"
omc_run speech.benchmark.download.confirm
check "the download finished" "yes" "$(download_gone librispeech-test-other)"
check "the LibriSpeech tool fetched test-other" "fetch-librispeech.sh test-other $corpora" "$(/usr/bin/tail -1 "$FAKE_FETCH_LOG" 2>/dev/null)"
check "its manifest is where the tab looks" "yes" "$([ -s "$corpora/LibriSpeech/test-other/manifest.tsv" ] && echo yes || echo no)"

# ------------------------------------------------------------------------------------------------
section "A failed download keeps the tool's reason, in words, and offers Download again"
open_window
choose "$BENCH_CORPUS_PICKER" 2 speech.benchmark.corpus.changed
FAKE_FETCH_MODE=fail
export FAKE_FETCH_MODE
omc_run speech.benchmark.download.confirm
check "confirm without a question does nothing" "0" "$(fetch_lines)"
omc_run speech.benchmark.download
omc_run speech.benchmark.download.confirm
check "the download failed" "yes" "$(download_failed en_us)"
check "the reason is the tool's, with curl's code put in words" \
    "The server could not be reached. Check the network connection. The download tool said: could not download the audio for en_us (curl 6); re-run to resume the partial download, or delete $corpora/fleurs/en_us/test.tar.gz to start over." \
    "$(/bin/cat "$downloads/en_us/message" 2>/dev/null)"
tick
check_contains "the status says so" \
    "Could not download FLEURS English (US). The server could not be reached." "$(ui_value "$BENCH_STATUS")"
check_contains "and what to do" "Press Download to try again." "$(ui_value "$BENCH_STATUS")"
check "Download is enabled again" "1" "$(ui_enabled "$BENCH_DOWNLOAD_BTN")"
check_contains "the picker still marks it as not here" "\"FLEURS English (US)$download_mark\"" "$(ui_prop "$BENCH_CORPUS_PICKER" options)"

section "A tool that finishes without a manifest is a failure, not a corpus"
FAKE_FETCH_MODE=empty
omc_run speech.benchmark.download
omc_run speech.benchmark.download.confirm
check "the download failed" "yes" "$(download_failed en_us)"
check "and says the list of recordings is missing" \
    "The download tool finished but left no list of recordings at $corpora/fleurs/en_us/manifest.tsv." \
    "$(/bin/cat "$downloads/en_us/message" 2>/dev/null)"

# ------------------------------------------------------------------------------------------------
section "While the archive grows, every window sees the download, and a second Download does nothing"
open_window
choose "$BENCH_CORPUS_PICKER" 4 speech.benchmark.corpus.changed
FAKE_FETCH_MODE=hang
FAKE_FETCH_BYTES=142000000
export FAKE_FETCH_BYTES
omc_run speech.benchmark.download
omc_run speech.benchmark.download.confirm
check "the tool started" "yes" "$(omc_wait_for "[ -s \"$corpora/fake-fetch.child\" ]" && echo yes || echo no)"
worker="$(/bin/cat "$downloads/de_de/worker.pid" 2>/dev/null)"
tool="$(/bin/cat "$downloads/de_de/fetch.pid" 2>/dev/null)"
child="$(/bin/cat "$corpora/fake-fetch.child" 2>/dev/null)"
check "the worker is running" "yes" "$(/bin/kill -0 "$worker" 2>/dev/null && echo yes || echo no)"
/bin/rm -f "$(bench_pane)/actions.sig" "$(bench_pane)/corpora.sig"
tick
check "the status counts the archive" "Downloading FLEURS German: 142 MB of 569 MB (24%)." "$(ui_value "$BENCH_STATUS")"
check_contains "the picker says it is downloading" '"FLEURS German (downloading)"' "$(ui_prop "$BENCH_CORPUS_PICKER" options)"
check "Download is disabled" "0" "$(ui_enabled "$BENCH_DOWNLOAD_BTN")"
check "Add waits for the corpus" "0" "$(ui_enabled "$BENCH_ADD_BTN")"
omc_run speech.benchmark.download
check "a second Download says it is downloading" "FLEURS German is already downloading." "$(ui_value "$BENCH_STATUS")"
check "and starts no second tool" "1" "$(/usr/bin/grep -c "fetch-fleurs.sh de_de" "$FAKE_FETCH_LOG")"
check "a download competes with a measurement" "0" "$(bench_call competing_work_busy; echo $?)"

section "A whole archive reads as unpacking, and its going as listing the recordings"
/bin/dd if=/dev/zero of="$corpora/fleurs/de_de/test.tar.gz" bs=568734559 count=0 seek=1 2>/dev/null
tick
check "the status says it is unpacking" "Unpacking FLEURS German..." "$(ui_value "$BENCH_STATUS")"
/bin/mv "$corpora/fleurs/de_de/test.tar.gz" "$OMCTEST_WORK/de_de.tar.gz"
tick
check "then listing the recordings" "Listing the recordings of FLEURS German..." "$(ui_value "$BENCH_STATUS")"
/bin/mv "$OMCTEST_WORK/de_de.tar.gz" "$corpora/fleurs/de_de/test.tar.gz"

section "Quitting stops the tool and the process it waits for, and keeps the partial archive"
/bin/kill -TERM "$worker" 2>/dev/null
check "the worker ended" "yes" "$(omc_wait_for "! /bin/kill -0 $worker 2>/dev/null" && echo yes || echo no)"
check "the tool ended" "yes" "$(omc_wait_for "! /bin/kill -0 $tool 2>/dev/null" && echo yes || echo no)"
check "and the process it waited for" "yes" "$(omc_wait_for "! /bin/kill -0 $child 2>/dev/null" && echo yes || echo no)"
check "a stopped download is not a failure" "yes" "$(download_gone de_de)"
check "the partial archive stays for Download to resume" "yes" "$([ -f "$corpora/fleurs/de_de/test.tar.gz" ] && echo yes || echo no)"
tick
check "Download is enabled again" "1" "$(ui_enabled "$BENCH_DOWNLOAD_BTN")"
check "the status offers it" "FLEURS German is not on this Mac yet. Press Download to get it (569 MB)." "$(ui_value "$BENCH_STATUS")"

section "app.will.terminate stops a download too"
omc_run speech.benchmark.download
omc_run speech.benchmark.download.confirm
/bin/rm -f "$corpora/fake-fetch.child"
omc_wait_for "[ -s \"$corpora/fake-fetch.child\" ]"
worker="$(/bin/cat "$downloads/de_de/worker.pid" 2>/dev/null)"
child="$(/bin/cat "$corpora/fake-fetch.child" 2>/dev/null)"
omc_run app.will.terminate
check "the worker ended" "yes" "$(omc_wait_for "! /bin/kill -0 $worker 2>/dev/null" && echo yes || echo no)"
check "and the process the tool waited for" "yes" "$(omc_wait_for "! /bin/kill -0 $child 2>/dev/null" && echo yes || echo no)"
check "nothing is left downloading" "yes" "$(download_gone de_de)"
unset FAKE_FETCH_MODE FAKE_FETCH_BYTES

# ------------------------------------------------------------------------------------------------
section "A corpus that does not fit is refused before the alert, counting what is already here"
check "enough space, no refusal" "" "$(bench_call corpus_download_refusal fr_fr 2000000000)"
check "too little space is refused with both sizes" \
    "FLEURS French needs about 800 MB free while it downloads and unpacks, and this Mac has 500 MB free." \
    "$(bench_call corpus_download_refusal fr_fr 500000000)"
/bin/mkdir -p "$corpora/fleurs/fr_fr"
/bin/dd if=/dev/zero of="$corpora/fleurs/fr_fr/test.tar.gz" bs=300000000 count=0 seek=1 2>/dev/null
check "a partial archive already here counts" \
    "FLEURS French needs about 500 MB free while it downloads and unpacks, and this Mac has 400 MB free." \
    "$(bench_call corpus_download_refusal fr_fr 400000000)"
free="$(bench_call corpora_free_bytes)"
free_is_number=yes
case "$free" in ''|*[!0-9]*) free_is_number=no ;; esac
check "df reports this volume's free space" "yes" "$free_is_number"

omctest_end
