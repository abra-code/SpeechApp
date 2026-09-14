#!/bin/sh
# 50-download-route.test.sh - the ways from a Speech window to the Models window: "Download
# Models..." at the end of both Model pickers, which opens the window and leaves the tab's model as
# it was; the status and picker of a tab with no model to offer; and the one offer per app run on a
# Mac with no model this app can run.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

empty_catalog="$OMCTEST_WORK/empty-catalog.json"
/usr/bin/jq '.rows = []' "$OMCTEST_FIXTURES/catalog.json" > "$empty_catalog"

open_window() {   # $1 = catalog to answer from; the fixture when absent
    reset_state
    chains_reset
    alerts_reset
    alert_answers_reset
    if [ -n "${1:-}" ]; then
        FAKE_SPEECH_CATALOG="$1"
        export FAKE_SPEECH_CATALOG
    fi
    omc_run speech.window.init
    load_window_models
    pane_call recordings refresh_recordings_actions "$(rec_pane)"
    pane_call live refresh_live_actions "$(live_pane)"
}

last_option() { ui_prop "$1" options | /usr/bin/jq -r '.[-1]'; }
option_count() { ui_prop "$1" options | /usr/bin/jq -r 'length'; }

# ------------------------------------------------------------------------------------------------
section "both Model pickers end with Download Models..., after their rows"
open_window
check "Recordings ends with it" "Download Models..." "$(last_option "$REC_MODEL_PICKER")"
check "after its four rows" "5" "$(option_count "$REC_MODEL_PICKER")"
check "Live ends with it" "Download Models..." "$(last_option "$LIVE_MODEL_PICKER")"
check "after its three live rows" "4" "$(option_count "$LIVE_MODEL_PICKER")"

section "picking it opens the Models window and keeps the tab's model"
check "Recordings starts on apple.transcriber" "apple.transcriber" "$(/bin/cat "$(rec_pane)/model.id")"
omc_fire speech.recordings.model.changed "$REC_MODEL_PICKER" 5
check "the Models window is asked for" "1" "$(chain_asked speech.models)"
check "the tab's model is unchanged" "apple.transcriber" "$(/bin/cat "$(rec_pane)/model.id")"
check "the picker is put back on it" "2" "$(ui_value "$REC_MODEL_PICKER")"
check_absent "no model preference is saved" "$SPEECH_APP_SUPPORT/Settings/recordings.model"
end_quiet_window
omc_fire speech.model.changed "$LIVE_MODEL_PICKER" 4
check "Live asks for the Models window too" "2" "$(chain_asked speech.models)"
check "and keeps its model" "apple.transcriber" "$(/bin/cat "$(live_pane)/model.id")"
check "with its picker put back" "2" "$(ui_value "$LIVE_MODEL_PICKER")"

section "a real model pick right after it is taken once the quiet window ends"
end_quiet_window
omc_fire speech.recordings.model.changed "$REC_MODEL_PICKER" 3
check "the picked model is taken" "ggml.whisper-large-v3-turbo@q8_0" "$(/bin/cat "$(rec_pane)/model.id")"
check "and no Models window is asked for" "2" "$(chain_asked speech.models)"

# ------------------------------------------------------------------------------------------------
section "a Mac with no model: a placeholder, the route still offered, and the status says how"
open_window "$empty_catalog"
check "Recordings offers the placeholder and the route" '["No models available","Download Models..."]' "$(ui_prop "$REC_MODEL_PICKER" options)"
check "Live too" '["No live models available","Download Models..."]' "$(ui_prop "$LIVE_MODEL_PICKER" options)"
check "the Recordings picker can be opened" "1" "$(ui_enabled "$REC_MODEL_PICKER")"
check "the Live picker can be opened" "1" "$(ui_enabled "$LIVE_MODEL_PICKER")"
check "the Recordings language picker cannot" "0" "$(ui_enabled "$REC_LANGUAGE_PICKER")"
check "the Recordings status says how to get a model" \
    "No speech model can run on this Mac yet. Choose Download Models... in the Model picker to get one." "$(ui_value "$REC_STATUS")"
check "the Live status too" \
    "No speech model on this Mac can transcribe live yet. Choose Download Models... in the Model picker to get one." "$(ui_value "$LIVE_STATUS")"
omc_fire speech.recordings.model.changed "$REC_MODEL_PICKER" 1
check "the placeholder does nothing" "0" "$(chain_asked speech.models)"
omc_fire speech.recordings.model.changed "$REC_MODEL_PICKER" 2
check "the route opens the Models window" "1" "$(chain_asked speech.models)"
check_absent "and no model appears" "$(rec_pane)/model.id"

section "the offer to open the Models window comes once per app run"
lib_call offer_models_window "$(spool)"
check "the first window offers it" "No speech models yet" "$(ui_alert_title)"
check "its button opens the Models window" "speech.models" "$(ui_alert_action "Open Models")"
check_exists "the offer is remembered for this run" "$SPEECH_APP_SUPPORT/Sessions/models-offered"
offers="$(ui_calls omc_present_alert)"
omc_window_switch second
omc_run speech.window.init
load_window_models
lib_call offer_models_window "$(spool)"
check "a second window does not offer it again" "$offers" "$(ui_calls omc_present_alert)"
open_window "$empty_catalog"
lib_call offer_models_window "$(spool)"
check "the next app run offers it again" "$((offers + 1))" "$(ui_calls omc_present_alert)"

section "a Mac with a model gets no offer"
open_window
offers="$(ui_calls omc_present_alert)"
lib_call offer_models_window "$(spool)"
check "no alert" "$offers" "$(ui_calls omc_present_alert)"
check_absent "and nothing is remembered" "$SPEECH_APP_SUPPORT/Sessions/models-offered"

check "no writes to undeclared view ids" "" "$(ui_unknown_writes)"
omctest_end
