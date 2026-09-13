# lib.test.speech.sh - Speech.app's test vocabulary, sourced by every test file after omctest.sh.

# View ids come from the applet's own lib, never restated here. The guard matters more than the
# pattern: a renamed constant would otherwise expand to empty and every check would fail one by
# one with no hint why.
eval "$(/usr/bin/sed -n 's/^\([A-Z][A-Z_]*\)=\([0-9][0-9]*\)$/\1=\2/p' "$OMCTEST_APP/Contents/Resources/Scripts/lib.speech.sh")"
if [ -z "$TRANSCRIPT_EDITOR" ] || [ -z "$MODEL_PICKER" ] || [ -z "$STATUS_TEXT" ]; then
    printf 'lib.test.speech.sh: no view ids imported from lib.speech.sh\n' >&2
    exit 1
fi

# The applet's seams (lib.speech.sh), pointed at fakes and at this file's isolated home.
SPEECH_BIN="$OMCTEST_TESTS/helpers/fake-speech.sh"
SPEECH_POLL_SCRIPT="$OMCTEST_TESTS/helpers/record-poller.sh"
SPEECH_APP_SUPPORT="$OMCTEST_HOME/Library/Application Support/Speech"
FAKE_SPEECH_FIXTURES="$OMCTEST_FIXTURES"
FAKE_SPEECH_LOG="$OMCTEST_WORK/fake-speech.log"
SPEECH_TEST_RECORD_DIR="$OMCTEST_WORK"
# The language picker falls back to the locale's language; pin it so the suite does not depend
# on the machine it runs on.
LANG="en_US.UTF-8"
export SPEECH_BIN SPEECH_POLL_SCRIPT SPEECH_APP_SUPPORT FAKE_SPEECH_FIXTURES FAKE_SPEECH_LOG SPEECH_TEST_RECORD_DIR LANG

if [ -z "$OMC_ACTIONUI_WINDOW_UUID" ]; then
    printf 'lib.test.speech.sh: no window uuid in the test shell\n' >&2
    exit 1
fi

# The window's spool, computed the way lib.speech.sh computes it.
spool() { printf '%s' "$SPEECH_APP_SUPPORT/Sessions/$OMC_ACTIONUI_WINDOW_UUID"; }

# The current run directory, as the applet names it.
run_dir() {
    local _name="$(/bin/cat "$(spool)/current" 2>/dev/null)"
    [ -n "$_name" ] || return 0
    printf '%s' "$(spool)/$_name"
}

# Call a lib.speech.sh function in a subshell, the way the poller calls it. The subshell keeps the
# library's state out of the test file and stops a function that exits from ending the suite.
lib_call() {
    ( . "$OMCTEST_APP/Contents/Resources/Scripts/lib.speech.sh" >/dev/null 2>&1
      "$@" )
}

# One pass of the poller's loop body, after the model list has been loaded.
poll_tick() {
    lib_call process_events "$(spool)"
    local _changed=$?
    [ "$_changed" -eq 0 ] && lib_call render_transcript "$(spool)"
    lib_call finish_if_exited "$(spool)"
    lib_call reflect_run_end "$(spool)"
    lib_call refresh_actions "$(spool)"
}

# Open the quiet window's lock early, so a section can act as the user rather than as an echo.
end_quiet_window() { /bin/rm -f "$(spool)/picker_quiet"; }

# Everything the applet keeps between sections: the spool, the settings, the handoff key.
reset_state() {
    /bin/rm -rf "$SPEECH_APP_SUPPORT"
    /bin/rm -f "$FAKE_SPEECH_LOG" "$SPEECH_TEST_RECORD_DIR/poller.args"
    "$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH set ""
    unset FAKE_SPEECH_MODE
    omc_reset_controls
}

# Kill a fake speech process a section left running.
reap_fake() {
    local _pid
    for _pid in $(/usr/bin/pgrep -f "$SPEECH_BIN" 2>/dev/null); do
        /bin/kill -KILL "$_pid" 2>/dev/null
    done
}
