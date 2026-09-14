#!/bin/sh
# 40-models.test.sh - the Models window: a card per catalog row in three sections, a download
# through its worker with progress on the card, a failed and a stopped download, delete with its
# alert and its refusals, the information sheet, and a Speech window taking the new model list.
# The fake speech (helpers/fake-speech.sh) answers catalog and models from a writable catalog copy;
# the real download worker runs.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

us="$(printf '\037')"
catalog_copy="$OMCTEST_WORK/catalog.json"

# The ids the Models window mints at run time: eight cards, each with its parts.
card_ids=""
for row in 1 2 3 4 5 6 7 8; do
    for offset in 0 1 2 3 4 5 6; do
        card_ids="$card_ids $((2000 + row * 10 + offset))"
    done
done
ui_declare_ids $card_ids

open_models_window() {
    reset_state
    /bin/cp -f "$OMCTEST_FIXTURES/catalog.json" "$catalog_copy"
    FAKE_SPEECH_CATALOG="$catalog_copy"
    export FAKE_SPEECH_CATALOG
    alerts_reset
    alert_answers_reset
    omc_run speech.models.init
}

tick() { models_call poll_models_window "$(spool)"; }

list_field() { /usr/bin/awk -F"$us" -v row="$1" -v col="$2" 'NR == row { print $col; exit }' "$(spool)/cards.list"; }   # $1 = row, $2 = field
card_container() { /usr/bin/awk -F"$us" -v row="$1" 'NR == row { print $1; exit }' "$(spool)/cards.json"; }
card_json() { /usr/bin/awk -F"$us" -v row="$1" 'NR == row { print $3; exit }' "$(spool)/cards.json"; }
download_dir() { printf '%s/Downloads/%s' "$SPEECH_APP_SUPPORT" "$(/sbin/md5 -q -s "$1")"; }
download_lines() { /bin/cat "$FAKE_SPEECH_LOG" 2>/dev/null | /usr/bin/grep -c -- "--json models download $1"; }

# ------------------------------------------------------------------------------------------------
section "Opening the Models window makes its spool and starts its poller"
open_models_window
check_status "init exits cleanly" 0
check_exists "the window's spool exists" "$(spool)"
check "the spool is a Models window's" "models" "$(/bin/cat "$(spool)/kind" 2>/dev/null)"
check "the status says the list is being read" "Reading the model list..." "$(ui_value "$MODELS_STATUS")"
check "the poller got the window and the spool" "$OMC_ACTIONUI_WINDOW_UUID
$(spool)" "$(/bin/cat "$SPEECH_TEST_RECORD_DIR/poller.args" 2>/dev/null)"

section "A card id maps back to its row, and nothing else does"
check "a card's download button is row 3" "3" "$(models_call card_row_of 2034)"
check "the card base itself is not a row" "" "$(models_call card_row_of 2000)"
check "the information sheet's text is not a row" "" "$(models_call card_row_of 4010)"
check "a malformed id is not a row" "" "$(models_call card_row_of 20x4)"

section "The first tick builds one card per catalog row, in three sections"
tick
check "eight cards were inserted" "8" "$(ui_calls 'omc_insert_element')"
check "their ids are tracked for removal" "8" "$(/usr/bin/awk 'END { print NR }' "$(spool)/cards.ids")"
check "the status is cleared" "" "$(ui_value "$MODELS_STATUS")"
check "Built into macOS is shown" "1" "$(ui_visible "$MODELS_BUILTIN_BOX")"
check "Downloaded is shown" "1" "$(ui_visible "$MODELS_INSTALLED_BOX")"
check "Available to download is shown" "1" "$(ui_visible "$MODELS_AVAILABLE_BOX")"
check "Apple's row is built in" "$MODELS_BUILTIN_LIST" "$(card_container 1)"
check "a missing row is available to download" "$MODELS_AVAILABLE_LIST" "$(card_container 3)"
check "an installed row is downloaded" "$MODELS_INSTALLED_LIST" "$(card_container 6)"
check "a partial download is available to download" "$MODELS_AVAILABLE_LIST" "$(card_container 8)"
check "every card is valid JSON with its id" "2010 2020 2030 2040 2050 2060 2070 2080" \
    "$(for r in 1 2 3 4 5 6 7 8; do card_json "$r" | /usr/bin/jq -r '.id'; done | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "Apple's title carries the Apple logo" "Apple dictation (built in) $apple_logo" \
    "$(card_json 1 | /usr/bin/jq -r '.children[0].children[0].children[0].properties.text')"
check "a label with quotes survives" "Nemotron \"streaming\" (Q8_0) [G]" \
    "$(card_json 7 | /usr/bin/jq -r '.children[0].children[0].children[0].properties.text')"
check "the detail line counts languages and says what it transcribes" "2 languages - Recordings and live" \
    "$(card_json 3 | /usr/bin/jq -r '.children[0].children[1].properties.text')"
check "a helper says so" "1 language - Used by other models, not for transcribing on its own" \
    "$(card_json 5 | /usr/bin/jq -r '.children[0].children[1].properties.text')"
check "built in" "Built into macOS" "$(list_field 1 9)"
check "not downloaded, with its size" "Not downloaded - 483 MB" "$(list_field 3 9)"
check "installed, with its size" "Installed - 886 MB" "$(list_field 6 9)"
check "installed but not runnable here" "Installed - 2.5 GB. This Mac cannot run it with this version of Speech." "$(list_field 4 9)"
check "a partial download" "Download interrupted - 300 MB of 1.1 GB kept. Download again to resume." "$(list_field 8 9)"
check "a partial download offers Resume" "Resume" \
    "$(card_json 8 | /usr/bin/jq -r '.children[0].children[2].children[3].properties.title')"
check "a missing row can be downloaded, not deleted" "1 0" "$(list_field 3 10) $(list_field 3 11)"
check "a partial row can be resumed and deleted" "1 1" "$(list_field 8 10) $(list_field 8 11)"
check "an installed row can be deleted, not downloaded" "0 1" "$(list_field 6 10) $(list_field 6 11)"
check "an installed row hides Download" "true" \
    "$(card_json 6 | /usr/bin/jq -r '.children[0].children[2].children[3].properties.hidden')"
check "Apple's row can be neither" "0 0" "$(list_field 1 10) $(list_field 1 11)"
check "Apple's row hides the trash button" "true" \
    "$(card_json 1 | /usr/bin/jq -r '.children[0].children[2].children[2].properties.hidden')"

section "A missing row with files on disk offers delete, not download"
# A raw line still starts with L, so each cards.list field is one column further along.
incomplete="$(printf '%s' '{"rows":[{"id":"ggml.x@q8_0","label":"X","engine":"ggml","state":"missing","available":true,"installed_bytes":5000,"size_bytes":900000}]}' \
    | /usr/bin/jq -r --argjson base 2000 --argjson builtin 1102 --argjson installed 1202 --argjson available 1302 \
        -f "$OMCTEST_APP/Contents/Resources/Scripts/speech.models.jq" \
    | /usr/bin/awk -F"$us" '$1 == "L" { print $10 "|" $11 " " $12; exit }')"
check "its state says to delete it first, with download off and delete on" \
    "Incomplete - 5 KB on disk that cannot be used. Delete it, then download again.|0 1" "$incomplete"

section "A tick with nothing changed touches no card"
tick
check "no more cards were inserted" "8" "$(ui_calls 'omc_insert_element')"
check "none were removed" "0" "$(ui_calls 'omc_remove_element')"

# ------------------------------------------------------------------------------------------------
section "Download runs the worker, and the finished download moves the card"
omc_trigger 2034
omc_run speech.models.download
check_status "download exits cleanly" 0
check "the card says it is starting" "Starting the download..." "$(ui_value 2033)"
check "its Download button is disabled" "0" "$(ui_enabled 2034)"
dl="$(download_dir fluid.parakeet-v3@int8)"
check "the worker finished and removed its directory" "yes" \
    "$(omc_wait_for "[ ! -d \"$dl\" ]" && echo yes || echo no)"
check "speech was asked to download the row" "1" "$(download_lines fluid.parakeet-v3@int8)"
check_exists "every window was told the models changed" "$SPEECH_APP_SUPPORT/models.changed"
tick
check "the old cards were removed" "8" "$(ui_calls 'omc_remove_element')"
check "and new ones inserted" "16" "$(ui_calls 'omc_insert_element')"
check "the row is now downloaded" "$MODELS_INSTALLED_LIST" "$(card_container 3)"
check "with its size" "Installed - 483 MB" "$(list_field 3 9)"

section "A failed download keeps speech's reason on its card"
open_models_window
tick
FAKE_SPEECH_DOWNLOAD=fail
export FAKE_SPEECH_DOWNLOAD
omc_trigger 2034
omc_run speech.models.download
dl="$(download_dir fluid.parakeet-v3@int8)"
check "the worker recorded a failure" "yes" \
    "$(omc_wait_for "[ \"\$(/bin/cat \"$dl/state\" 2>/dev/null)\" = failed ]" && echo yes || echo no)"
tick
check "the card shows the reason" "Download failed: The network connection was lost." "$(ui_value 2033)"
check "and Download is offered again" "1" "$(ui_enabled 2034)"
check "the row is still available to download" "$MODELS_AVAILABLE_LIST" "$(card_container 3)"
unset FAKE_SPEECH_DOWNLOAD
omc_trigger 2034
omc_run speech.models.download
check "the retry succeeds and clears the failure" "yes" \
    "$(omc_wait_for "[ ! -d \"$dl\" ]" && echo yes || echo no)"

section "Progress while downloading; a second click and delete wait for it; a stopped download says nothing"
open_models_window
tick
FAKE_SPEECH_DOWNLOAD=hang
export FAKE_SPEECH_DOWNLOAD
dl="$(download_dir ggml.canary-1b-v2@q8_0)"
omc_trigger 2084
omc_run speech.models.download
check "the fake reported progress" "yes" \
    "$(omc_wait_for "[ -s \"$dl/events.jsonl\" ]" && echo yes || echo no)"
tick
check "the card shows the progress" "Downloading 120 MB of 480 MB (25%)" "$(ui_value 2083)"
check "Resume is disabled" "0" "$(ui_enabled 2084)"
check "delete is disabled" "0" "$(ui_enabled 2085)"
tick
check "an unchanged tick writes the progress once" "1" "$(ui_calls 'Downloading 120 MB of 480 MB (25%)')"
omc_trigger 2084
omc_run speech.models.download
check "a second click starts no second download" "1" "$(download_lines ggml.canary-1b-v2@q8_0)"
alerts_before="$(ui_calls omc_present_alert)"
omc_trigger 2085
omc_run speech.models.delete
check "delete says to wait" "Canary 1B v2 (Q8_0) is downloading. Wait for the download to end, then delete it." "$(ui_value "$MODELS_STATUS")"
check "and asks nothing" "$alerts_before" "$(ui_calls omc_present_alert)"
worker_pid="$(/bin/cat "$dl/worker.pid" 2>/dev/null)"
/bin/kill -TERM "$worker_pid" 2>/dev/null
check "a signaled worker stops speech and removes its directory" "yes" \
    "$(omc_wait_for "[ ! -d \"$dl\" ]" && echo yes || echo no)"
check "no fake speech is left running" "0" "$(/usr/bin/pgrep -f "$SPEECH_BIN" 2>/dev/null | /usr/bin/awk 'END { print NR }')"
# The catalog did not change (the fake got no further), so no card is rebuilt: the card itself has
# to get its catalog state back.
tick
check "the card gets its catalog state back" "Download interrupted - 300 MB of 1.1 GB kept. Download again to resume." "$(ui_value 2083)"
check "Resume is offered again" "1" "$(ui_enabled 2084)"
check "and so is delete" "1" "$(ui_enabled 2085)"
unset FAKE_SPEECH_DOWNLOAD
reap_fake

# ------------------------------------------------------------------------------------------------
section "Delete asks first, then deletes, and the card moves"
open_models_window
tick
omc_trigger 2065
omc_run speech.models.delete
check "the alert names the model" "Delete Whisper large-v3-turbo (Q8_0)?" "$(ui_alert_title)"
check "and the space" "This removes 886 MB from this Mac. You can download it again later." "$(ui_alert_message)"
check "Delete confirms" "speech.models.delete.confirm" "$(ui_alert_action Delete)"
check "the model waits in pending.delete" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$(spool)/pending.delete" 2>/dev/null)"
check "speech was not asked yet" "0" "$(/bin/cat "$FAKE_SPEECH_LOG" 2>/dev/null | /usr/bin/grep -c 'models delete')"
omc_run speech.models.delete.confirm
check_status "confirm exits cleanly" 0
check "speech deleted the row" "1" "$(/bin/cat "$FAKE_SPEECH_LOG" 2>/dev/null | /usr/bin/grep -c -- '--json models delete ggml.whisper-large-v3-turbo@q8_0')"
check "the status says so" "Deleted Whisper large-v3-turbo (Q8_0)." "$(ui_value "$MODELS_STATUS")"
check_absent "the pending model is consumed" "$(spool)/pending.delete"
tick
check "the row is available to download again" "$MODELS_AVAILABLE_LIST" "$(card_container 6)"
check "the status survives the tick" "Deleted Whisper large-v3-turbo (Q8_0)." "$(ui_value "$MODELS_STATUS")"

section "A confirm with nothing pending does nothing"
/bin/rm -f "$FAKE_SPEECH_LOG"
omc_run speech.models.delete.confirm
check "speech was not asked" "0" "$(/bin/cat "$FAKE_SPEECH_LOG" 2>/dev/null | /usr/bin/grep -c 'models delete')"

section "Delete is refused while a window transcribes with the model"
open_models_window
tick
other="$SPEECH_APP_SUPPORT/Sessions/another-window"
/bin/mkdir -p "$other/recordings" "$other/live/run-1"
printf 'running' > "$other/recordings/batch"
printf 'ggml.nemotron-3.5-asr-streaming-0.6b@q8_0' > "$other/recordings/batch.model"
printf 'run-1' > "$other/live/current"
printf 'running' > "$other/live/run-1/state"
printf 'ggml.whisper-large-v3-turbo@q8_0' > "$other/live/run-1/model"
alerts_before="$(ui_calls omc_present_alert)"
omc_trigger 2075
omc_run speech.models.delete
check "a batch using the model refuses" "Nemotron \"streaming\" (Q8_0) is transcribing in a Speech window. Stop it there, then delete it." "$(ui_value "$MODELS_STATUS")"
check "without asking" "$alerts_before" "$(ui_calls omc_present_alert)"
omc_trigger 2065
omc_run speech.models.delete
check "a live run using the model refuses" "Whisper large-v3-turbo (Q8_0) is transcribing in a Speech window. Stop it there, then delete it." "$(ui_value "$MODELS_STATUS")"
printf 'ggml.whisper-large-v3-turbo@q8_0' > "$(spool)/pending.delete"
omc_run speech.models.delete.confirm
check "a confirm that finds the model in use refuses too" "0" "$(/bin/cat "$FAKE_SPEECH_LOG" 2>/dev/null | /usr/bin/grep -c 'models delete')"
printf 'done' > "$other/live/run-1/state"
omc_trigger 2065
omc_run speech.models.delete
check "a finished run no longer refuses" "Delete Whisper large-v3-turbo (Q8_0)?" "$(ui_alert_title)"
/bin/rm -rf "$other"

section "A delete that fails says why"
open_models_window
tick
FAKE_SPEECH_DELETE=fail
export FAKE_SPEECH_DELETE
printf 'fluid.parakeet-ctc-110m' > "$(spool)/pending.delete"
omc_run speech.models.delete.confirm
check_status "confirm reports the failure" 1
check "the status carries speech's reason" "Could not delete Parakeet CTC 110M (vocabulary spotter): error: cannot remove the model files: permission denied" "$(ui_value "$MODELS_STATUS")"
check_absent "no window is told the models changed" "$SPEECH_APP_SUPPORT/models.changed"
unset FAKE_SPEECH_DELETE

# ------------------------------------------------------------------------------------------------
section "The information sheet shows the catalog's details and the family's page"
open_models_window
tick
omc_trigger 2066
omc_run speech.models.info
check "the sheet is presented" "1" "$(ui_calls 'omc_present_modal speech.model.info')"
info="$(ui_value "$MODEL_INFO_TEXT")"
check "as Markdown" "markdown" "$(ui_content_type "$MODEL_INFO_TEXT")"
check_contains() { case "$3" in *"$2"*) check "$1" yes yes ;; *) check "$1" "$2" "$3" ;; esac; }
check_contains "the title" "### Whisper large-v3-turbo (Q8_0)" "$info"
check_contains "the engine" "- **Engine:** transcribe.cpp (ggml)" "$info"
check_contains "the status" "- **Status:** Installed - 886 MB" "$info"
check_contains "the languages by name" "- **Languages:** English, Polish" "$info"
check_contains "the parameters" "- **Parameters:** 809 million" "$info"
check_contains "the source as a link" "- **Source:** [ggml-org/whisper-large-v3-turbo](https://huggingface.co/ggml-org/whisper-large-v3-turbo)" "$info"
check_contains "where its files are" "- **Location:** /nonexistent/Models/ggml.whisper-large-v3-turbo@q8_0" "$info"
check_contains "the family page" "$(/usr/bin/head -1 "$OMCTEST_APP/Contents/Resources/Reference/models/whisper.md")" "$info"
omc_trigger 2016
omc_run speech.models.info
info="$(ui_value "$MODEL_INFO_TEXT")"
case "$info" in *Location*|*"Downloads to"*) location=yes ;; *) location=no ;; esac
check "Apple's row has no location" "no" "$location"
omc_run speech.models.info.close
check "Close dismisses the sheet" "1" "$(ui_calls 'omc_dismiss_modal')"

# ------------------------------------------------------------------------------------------------
section "Done closes the window, and closing it removes the spool"
omc_run speech.models.done
check "Done ends the window" "1" "$(ui_calls 'omc_terminate_cancel')"
omc_run speech.models.cancel
check_absent "the spool is gone" "$(spool)"

section "A Speech window takes the new model list, and a busy tab waits for its run to end"
open_models_window
omc_window_switch main
omc_run speech.window.init
load_window_models
check "Live does not offer the missing model" "" "$(/usr/bin/grep -F 'fluid.parakeet-v3@int8' "$(live_pane)/models.tsv")"
printf 'running' > "$(rec_pane)/batch"
printf 'apple.transcriber' > "$(rec_pane)/batch.model"
FAKE_SPEECH_DOWNLOAD=ok
/usr/bin/jq '(.rows[] | select(.id == "fluid.parakeet-v3@int8")) |= (.state = "installed")' "$catalog_copy" > "$catalog_copy.tmp"
/bin/mv -f "$catalog_copy.tmp" "$catalog_copy"
lib_call bump_models_stamp
lib_call reload_models_if_changed "$(spool)"
check "the idle Live tab offers the new model" "fluid.parakeet-v3@int8" "$(/usr/bin/cut -f1 "$(live_pane)/models.tsv" | /usr/bin/grep -F 'fluid.parakeet-v3@int8')"
case "$(ui_prop "$LIVE_MODEL_PICKER" options)" in *"Parakeet v3 (int8) [F]"*) offered=yes ;; *) offered=no ;; esac
check "in its picker" "yes" "$offered"
check "the busy Recordings tab keeps its list" "" "$(/usr/bin/grep -F 'fluid.parakeet-v3@int8' "$(rec_pane)/models.tsv")"
check_exists "and waits to take the new one" "$(rec_pane)/models.pending"
lib_call reload_models_if_changed "$(spool)"
check "a second tick still waits while the batch runs" "" "$(/usr/bin/grep -F 'fluid.parakeet-v3@int8' "$(rec_pane)/models.tsv")"
/bin/rm -f "$(rec_pane)/batch"
lib_call reload_models_if_changed "$(spool)"
check "once the batch ends, Recordings offers it" "fluid.parakeet-v3@int8" "$(/usr/bin/cut -f1 "$(rec_pane)/models.tsv" | /usr/bin/grep -F 'fluid.parakeet-v3@int8')"
check_absent "and nothing is pending" "$(rec_pane)/models.pending"
unset FAKE_SPEECH_DOWNLOAD

check "no writes to undeclared view ids" "" "$(ui_unknown_writes)"
reap_fake
omctest_end
