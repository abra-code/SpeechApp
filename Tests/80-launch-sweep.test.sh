#!/bin/sh
# 80-launch-sweep.test.sh - app.will.launch removes the window spools of an app that was killed:
# every window names its app in app.pid; a spool whose app is gone, or that names none, is removed,
# one whose app runs is kept, and the first-run marker goes only when no spool is left. After the
# sweep, a batch the killed app recorded as running no longer keeps delete refusing its model.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

sessions="$SPEECH_APP_SUPPORT/Sessions"

# A pid that belonged to a process and no longer does: the harness cannot stage a dead app, so
# this file mints one.
/bin/sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid"

stale_spool() {   # $1 = name, $2 = app pid, or empty for a spool that names no app
    /bin/mkdir -p "$sessions/$1/recordings"
    [ -n "$2" ] && printf '%s' "$2" > "$sessions/$1/app.pid"
    printf 'running' > "$sessions/$1/recordings/batch"
    printf 'ggml.whisper-large-v3-turbo@q8_0' > "$sessions/$1/recordings/batch.model"
}

# ------------------------------------------------------------------------------------------------
section "Both kinds of window name their app in their spool"
reset_state
omc_run speech.window.init
check "a Speech window's spool names the app" "$OMC_APP_PROCESS_ID" "$(/bin/cat "$(spool)/app.pid" 2>/dev/null)"
reset_state
omc_run speech.models.init
check "a Models window's spool names the app" "$OMC_APP_PROCESS_ID" "$(/bin/cat "$(spool)/app.pid" 2>/dev/null)"

section "A launch with no Sessions does nothing"
reset_state
omc_run app.will.launch
check_status "launch exits cleanly" 0
check_absent "and makes no Sessions" "$sessions"

section "A killed app's spools go, a running app's stays, and so does the marker while it does"
reset_state
stale_spool killed-app "$dead_pid"
stale_spool before-app-pid ""
stale_spool running-app "$OMC_APP_PROCESS_ID"
/bin/mkdir -p "$sessions/models-offered"
check "before the sweep, the stale batch keeps delete refusing" "0" \
    "$(models_call model_in_use ggml.whisper-large-v3-turbo@q8_0; echo $?)"
omc_run app.will.launch
check_status "launch exits cleanly" 0
check_absent "the killed app's spool is gone" "$sessions/killed-app"
check_absent "a spool that names no app is gone" "$sessions/before-app-pid"
check_exists "the running app's spool stays" "$sessions/running-app/recordings/batch"
check_exists "and the first-run marker stays with it" "$sessions/models-offered"

section "With no spool left, the first-run marker goes, and delete is no longer refused"
/bin/rm -rf "$sessions/running-app"
stale_spool killed-app "$dead_pid"
omc_run app.will.launch
check_absent "the killed app's spool is gone" "$sessions/killed-app"
check_absent "the first-run marker is gone" "$sessions/models-offered"
check "the model is no longer in use" "1" \
    "$(models_call model_in_use ggml.whisper-large-v3-turbo@q8_0; echo $?)"

section "A killed app's playback is stopped with its spool: nothing else would be left to stop it"
reset_state
stale_spool killed-app "$dead_pid"
"$SPEECH_AFPLAY_BIN" "$OMCTEST_WORK/left-playing.wav" < /dev/null > /dev/null 2>&1 &
afplay_pid=$!
printf '%s' "$afplay_pid" > "$sessions/killed-app/recordings/play.pid"
printf '%s' "$OMCTEST_WORK/left-playing.wav" > "$sessions/killed-app/recordings/play.path"
omc_run app.will.launch
check "the playback stopped" "dead" \
    "$(omc_wait_for "! /bin/kill -0 $afplay_pid 2>/dev/null" > /dev/null; /bin/kill -0 "$afplay_pid" 2>/dev/null && printf 'alive' || printf 'dead')"
check_absent "and the killed app's spool is gone" "$sessions/killed-app"
/bin/kill -KILL "$afplay_pid" 2>/dev/null

check "no writes to undeclared view ids" "" "$(ui_unknown_writes)"
omctest_end
