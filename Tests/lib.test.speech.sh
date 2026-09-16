# lib.test.speech.sh - Speech.app's test vocabulary, sourced by every test file after omctest.sh.

# View ids come from the applet's own lib, never restated here. The guard matters more than the
# pattern: a renamed constant would otherwise expand to empty and every check would fail one by
# one with no hint why.
eval "$(/usr/bin/sed -n 's/^\([A-Z][A-Z_]*\)=\([0-9][0-9]*\)$/\1=\2/p' "$OMCTEST_APP/Contents/Resources/Scripts/lib.speech.sh")"
if [ -z "$LIVE_TRANSCRIPT" ] || [ -z "$LIVE_STATUS" ] || [ -z "$REC_TABLE" ] || [ -z "$REC_STATUS" ]; then
    printf 'lib.test.speech.sh: no view ids imported from lib.speech.sh\n' >&2
    exit 1
fi

# The applet's seams (lib.speech.sh), pointed at fakes and at this file's isolated home. The
# bundled fingerprint tool runs for real: it only reads files, and what it reads is the scratch
# tree.
SPEECH_BIN="$OMCTEST_TESTS/helpers/fake-speech.sh"
SPEECH_POLL_SCRIPT="$OMCTEST_TESTS/helpers/record-poller.sh"
SPEECH_MODELS_POLL_SCRIPT="$OMCTEST_TESTS/helpers/record-poller.sh"
SPEECH_APP_SUPPORT="$OMCTEST_HOME/Library/Application Support/Speech"
SPEECH_RECORDINGS_DIR="$OMCTEST_WORK/Speech Recordings"
FAKE_SPEECH_FIXTURES="$OMCTEST_FIXTURES"
FAKE_SPEECH_LOG="$OMCTEST_WORK/fake-speech.log"
SPEECH_TEST_RECORD_DIR="$OMCTEST_WORK"
# A small reference file instead of the published measurements, whose rows change with every battery.
SPEECH_REFERENCE_MEASUREMENTS="$OMCTEST_FIXTURES/reference.tsv"
# The language picker falls back to the locale's language; pin it so the suite does not depend
# on the machine it runs on.
LANG="en_US.UTF-8"
export SPEECH_BIN SPEECH_POLL_SCRIPT SPEECH_MODELS_POLL_SCRIPT SPEECH_APP_SUPPORT FAKE_SPEECH_FIXTURES FAKE_SPEECH_LOG SPEECH_TEST_RECORD_DIR SPEECH_REFERENCE_MEASUREMENTS LANG

if [ -z "$OMC_ACTIONUI_WINDOW_UUID" ]; then
    printf 'lib.test.speech.sh: no window uuid in the test shell\n' >&2
    exit 1
fi
if [ ! -x "$OMCTEST_APP/Contents/Support/fingerprint" ]; then
    printf 'lib.test.speech.sh: no fingerprint in the bundle - run update_speech.sh first\n' >&2
    exit 1
fi

# The squared letters the applet appends to model labels: M (U+1F13C) MLX, G (U+1F136) ggml,
# F (U+1F135) FluidAudio. Apple's labels get none.
mlx_mark="$(printf '\360\237\204\274')"
ggml_mark="$(printf '\360\237\204\266')"
fluid_mark="$(printf '\360\237\204\265')"

# The window's spool and its two panes, computed the way lib.speech.sh computes them.
spool() { printf '%s' "$SPEECH_APP_SUPPORT/Sessions/$OMC_ACTIONUI_WINDOW_UUID"; }
live_pane() { printf '%s/live' "$(spool)"; }
rec_pane() { printf '%s/recordings' "$(spool)"; }

# The Live tab's current run directory, as the applet names it.
run_dir() {
    local _name="$(/bin/cat "$(live_pane)/current" 2>/dev/null)"
    [ -n "$_name" ] || return 0
    printf '%s' "$(live_pane)/$_name"
}

# A recording's item directory, keyed the way the applet keys it.
item_dir() { printf '%s/items/%s' "$(rec_pane)" "$(/sbin/md5 -q -s "$1")"; }

# Call a lib.speech.sh function in a subshell, the way the poller calls it. The subshell keeps the
# library's state out of the test file and stops a function that exits from ending the suite.
# The same for the Models window's library.
models_call() {
    ( . "$OMCTEST_APP/Contents/Resources/Scripts/lib.speech.models.sh" >/dev/null 2>&1
      "$@" )
}

lib_call() {
    ( . "$OMCTEST_APP/Contents/Resources/Scripts/lib.speech.sh" >/dev/null 2>&1
      "$@" )
}

# The same for the Benchmark tab's library.
bench_call() {
    ( . "$OMCTEST_APP/Contents/Resources/Scripts/lib.speech.benchmark.sh" >/dev/null 2>&1
      "$@" )
}

# The same, with a pane selected first.
pane_call() {   # $1 = live | recordings, then the function and its arguments
    ( . "$OMCTEST_APP/Contents/Resources/Scripts/lib.speech.sh" >/dev/null 2>&1
      use_pane "$1"
      shift
      "$@" )
}

# One pass of the poller's loop body, after the model lists have been loaded.
poll_tick() {
    lib_call poll_live "$(spool)"
    lib_call poll_recordings "$(spool)"
}

# The poller's first job, done by hand: the model lists and both tabs' pickers.
load_window_models() {
    lib_call load_models "$(spool)"
    pane_call live populate_model_picker "$(live_pane)"
    pane_call recordings populate_model_picker "$(rec_pane)"
    end_quiet_window
}

# Close the quiet windows early, so a section can act as the user rather than as an echo.
end_quiet_window() { /bin/rm -f "$(live_pane)/picker_quiet" "$(rec_pane)/picker_quiet" "$(rec_pane)/table_quiet"; }

# Tick until the Recordings batch has ended, waiting for each recording's speech process between
# ticks. Returns non-zero when the batch is still going after twenty ticks.
run_batch() {
    local _ticks=0
    local _current _pid
    while [ "$_ticks" -lt 20 ]; do
        poll_tick
        [ -f "$(rec_pane)/batch" ] || return 0
        _current="$(/bin/cat "$(rec_pane)/current" 2>/dev/null)"
        if [ -n "$_current" ]; then
            _pid="$(/bin/cat "$(rec_pane)/$_current/speech.pid" 2>/dev/null)"
            [ -n "$_pid" ] && omc_wait_for "! /bin/kill -0 $_pid 2>/dev/null"
        fi
        _ticks=$((_ticks + 1))
    done
    return 1
}

# Everything the applet keeps between sections: the spool, the settings, the handoff key.
reset_state() {
    /bin/rm -rf "$SPEECH_APP_SUPPORT"
    /bin/rm -f "$FAKE_SPEECH_LOG" "$SPEECH_TEST_RECORD_DIR/poller.args"
    "$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH set ""
    unset FAKE_SPEECH_MODE FAKE_SPEECH_FAIL_FILE FAKE_SPEECH_CATALOG FAKE_SPEECH_DOWNLOAD FAKE_SPEECH_DELETE FAKE_SPEECH_ADD FAKE_SPEECH_EVAL
    omc_reset_controls
}

# Kill a fake speech process a section left running.
reap_fake() {
    local _pid
    for _pid in $(/usr/bin/pgrep -f "$SPEECH_BIN" 2>/dev/null); do
        /bin/kill -KILL "$_pid" 2>/dev/null
    done
}
