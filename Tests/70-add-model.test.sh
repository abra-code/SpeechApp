#!/bin/sh
# 70-add-model.test.sh - Add Model... in the Models window: what the sheet accepts as a repository
# and a quantization, the add under its worker with progress on the status line, the new model's
# card, a failed add with speech's reason in the app's words, one add at a time, a stopped add, and
# a window opened later that does not repeat an old result. The fake speech (helpers/fake-speech.sh)
# answers `models add`; the real add worker runs.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

us="$(printf '\037')"
catalog_copy="$OMCTEST_WORK/catalog.json"
adding_dir="$SPEECH_APP_SUPPORT/Adding"

# The ids the Models window mints at run time: eight cards once a model is added - the fixture's
# seven transcriber rows, its helper row being left out, and the new one - each with its parts.
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
    omc_run speech.models.init
}

tick() { models_call poll_models_window "$(spool)"; }
row_count() { /usr/bin/awk 'END { print NR }' "$(spool)/cards.list"; }
card_container() { /usr/bin/awk -F"$us" -v row="$1" 'NR == row { print $1; exit }' "$(spool)/cards.json"; }
add_lines() { /bin/cat "$FAKE_SPEECH_LOG" 2>/dev/null | /usr/bin/grep -c -- "--json models add"; }
wait_add_state() {   # $1 = state; prints yes once the add is in it
    omc_wait_for "[ \"\$(/bin/cat \"$adding_dir/state\" 2>/dev/null)\" = $1 ]" && echo yes || echo no
}
start_add() {   # $1 = the Repository field, $2 = the Quantization field
    omc_control "$MODEL_ADD_REPO" "$1"
    omc_control "$MODEL_ADD_QUANT" "$2"
    omc_run speech.models.add.start
}
quant_status() { models_call quant_from_input "$1" > /dev/null; echo $?; }

# ------------------------------------------------------------------------------------------------
section "The Repository field takes owner/name or a Hugging Face address"
check "owner/name" "ggml-org/whisper-gguf" "$(models_call repo_from_input 'ggml-org/whisper-gguf')"
check "with spaces around it" "a/b" "$(models_call repo_from_input '  a/b  ')"
check "the repository's address" "someone/Model_1.2-gguf" "$(models_call repo_from_input 'https://huggingface.co/someone/Model_1.2-gguf')"
check "a page inside it" "someone/model" "$(models_call repo_from_input 'https://huggingface.co/someone/model/tree/main')"
check "the short address with a query" "someone/model" "$(models_call repo_from_input 'hf.co/someone/model?library=gguf')"
check "an address without its scheme" "someone/model" "$(models_call repo_from_input 'huggingface.co/someone/model')"
check "a git address" "someone/model" "$(models_call repo_from_input 'https://huggingface.co/someone/model.git')"
check "a name alone is not one" "" "$(models_call repo_from_input 'model')"
check "nor an owner with no name" "" "$(models_call repo_from_input 'someone/')"
check "nor a parent directory" "" "$(models_call repo_from_input '../model')"
check "nor a name with a space" "" "$(models_call repo_from_input 'someone/my model')"
check "nor an owner that speech would take for an option" "" "$(models_call repo_from_input '-quant/model')"
check "nor another website's address" "" "$(models_call repo_from_input 'https://example.com/someone/model')"

section "The Quantization field is optional, and letters, digits and underscores"
check "a quantization, trimmed" "Q4_K_M" "$(models_call quant_from_input ' Q4_K_M ')"
check "empty is fine" "0" "$(quant_status '')"
check "a space is not" "1" "$(quant_status 'Q4 K')"
check "nor a path" "1" "$(quant_status '../q8')"

# ------------------------------------------------------------------------------------------------
section "Add Model... presents the sheet, which refuses what it cannot add and stays open"
open_models_window
tick
omc_run speech.models.add
check_status "add exits cleanly" 0
check "the sheet is presented" "1" "$(ui_calls 'omc_present_modal speech.model.add')"
check "with nothing to refuse" "" "$(ui_value "$MODEL_ADD_ERROR")"
start_add "whisper" ""
check "a name alone asks for the repository" "Enter the model's Hugging Face repository as owner/name, or paste its address." "$(ui_value "$MODEL_ADD_ERROR")"
start_add "someone/model" "Q4 K"
check "a bad quantization says what one is" "A quantization is letters, digits and underscores, such as Q4_K_M." "$(ui_value "$MODEL_ADD_ERROR")"
check "the sheet stays open" "0" "$(ui_calls omc_dismiss_modal)"
check "speech was not asked" "0" "$(add_lines)"

section "An add runs under its worker, and the new model gets a card"
start_add "https://huggingface.co/someone/Test-ASR-gguf" "Q4_K_M"
check_status "start exits cleanly" 0
check "the sheet closes" "1" "$(ui_calls omc_dismiss_modal)"
check "the status names the repository" "Adding someone/Test-ASR-gguf..." "$(ui_value "$MODELS_STATUS")"
check "Add Model... waits" "0" "$(ui_enabled "$MODELS_ADD_BTN")"
check "the add finished" "yes" "$(wait_add_state done)"
check "speech was asked for the repository and the quantization" "1" \
    "$(/bin/cat "$FAKE_SPEECH_LOG" 2>/dev/null | /usr/bin/grep -c -- '^--json models add someone/Test-ASR-gguf --quant Q4_K_M$')"
check_exists "every window was told the models changed" "$SPEECH_APP_SUPPORT/models.changed"
tick
check "the new model has a card" "8" "$(row_count)"
check "under Downloaded" "$MODELS_INSTALLED_LIST" "$(card_container 8)"
check "the status names what was added" "Added test-asr (Q4_K_M) from someone/Test-ASR-gguf. It is listed under Downloaded." "$(ui_value "$MODELS_STATUS")"
check "Add Model... is offered again" "1" "$(ui_enabled "$MODELS_ADD_BTN")"
tick
check "an unchanged tick says it once" "1" "$(ui_calls 'Added test-asr')"

section "A Models window opened later does not repeat an add that has ended"
omc_run speech.models.cancel
omc_run speech.models.init
tick
check "its status is clear" "" "$(ui_value "$MODELS_STATUS")"
check "and it lists the added model" "8" "$(row_count)"

# ------------------------------------------------------------------------------------------------
section "A failed add gives speech's reason in the app's words"
open_models_window
tick
FAKE_SPEECH_ADD=fail
export FAKE_SPEECH_ADD
start_add "someone/model-gguf" ""
check "the add failed" "yes" "$(wait_add_state failed)"
check "speech was asked without a quantization" "1" \
    "$(/bin/cat "$FAKE_SPEECH_LOG" 2>/dev/null | /usr/bin/grep -c -- '^--json models add someone/model-gguf$')"
tick
check "the status gives the reason" "Could not add someone/model-gguf: someone/model-gguf has several .gguf files; enter the quantization of the one you want (have: a-F16.gguf, a-Q4_K_M.gguf)" "$(ui_value "$MODELS_STATUS")"
check "Add Model... is offered" "1" "$(ui_enabled "$MODELS_ADD_BTN")"
check_absent "no window is told the models changed" "$SPEECH_APP_SUPPORT/models.changed"
unset FAKE_SPEECH_ADD

section "A model already in the list says so"
open_models_window
tick
FAKE_SPEECH_ADD=exists
export FAKE_SPEECH_ADD
start_add "someone/model-gguf" ""
check "the add ended" "yes" "$(wait_add_state done)"
tick
check "the status says it is listed" "someone/model-gguf is already in the model list." "$(ui_value "$MODELS_STATUS")"
FAKE_SPEECH_ADD=finish
start_add "someone/Whisper-large-v3-turbo-gguf" ""
check "an add that finished a download ended" "yes" "$(omc_wait_for "[ \"\$(/bin/cat \"$adding_dir/how\" 2>/dev/null)\" = downloaded ]" && echo yes || echo no)"
tick
check "the status says the download was finished" "Whisper large-v3-turbo (Q8_0) was already in the model list. Speech finished downloading it." "$(ui_value "$MODELS_STATUS")"
unset FAKE_SPEECH_ADD

# ------------------------------------------------------------------------------------------------
section "One add at a time, with its progress; a stopped add clears the status"
open_models_window
tick
FAKE_SPEECH_ADD=hang
export FAKE_SPEECH_ADD
start_add "someone/big-gguf" ""
check "the fake reported progress" "yes" \
    "$(omc_wait_for "[ -s \"$adding_dir/events.jsonl\" ]" && echo yes || echo no)"
tick
check "the status shows the download" "Adding someone/big-gguf: Downloading 120 MB of 480 MB (25%)" "$(ui_value "$MODELS_STATUS")"
check "Add Model... waits" "0" "$(ui_enabled "$MODELS_ADD_BTN")"
omc_run speech.models.add
check "the sheet says an add is running" "Speech is still adding someone/big-gguf. Wait for it to finish, then add another." "$(ui_value "$MODEL_ADD_ERROR")"
omc_control "$MODEL_ADD_ERROR" ""
start_add "someone/other-gguf" ""
check "and so does Add" "Speech is still adding someone/big-gguf. Wait for it to finish, then add another." "$(ui_value "$MODEL_ADD_ERROR")"
check "no second add started" "1" "$(add_lines)"
worker_pid="$(/bin/cat "$adding_dir/worker.pid" 2>/dev/null)"
/bin/kill -TERM "$worker_pid" 2>/dev/null
check "a signaled worker stops speech and records the add as stopped" "yes" "$(wait_add_state stopped)"
check "no fake speech is left running" "0" "$(/usr/bin/pgrep -f "$SPEECH_BIN" 2>/dev/null | /usr/bin/awk 'END { print NR }')"
tick
check "the status is cleared" "" "$(ui_value "$MODELS_STATUS")"
check "Add Model... is offered again" "1" "$(ui_enabled "$MODELS_ADD_BTN")"
unset FAKE_SPEECH_ADD
reap_fake

section "An add whose worker died without a word does not hold Add Model... back"
open_models_window
/bin/mkdir -p "$adding_dir"
printf 'someone/lost-gguf' > "$adding_dir/repo"
printf '1 1' > "$adding_dir/token"
printf 'running' > "$adding_dir/state"
printf '999999' > "$adding_dir/worker.pid"
tick
check "the status says nothing about it" "" "$(ui_value "$MODELS_STATUS")"
check "Add Model... is offered" "1" "$(ui_enabled "$MODELS_ADD_BTN")"
check "the sheet refuses nothing" "" "$(models_call add_refusal)"

check "no writes to undeclared view ids" "" "$(ui_unknown_writes)"
reap_fake
omctest_end
