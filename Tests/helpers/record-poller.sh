#!/bin/sh
# record-poller.sh - stands in for speech.poll.sh under test (SPEECH_POLL_SCRIPT). A real poller
# would keep writing into the window while a test reads it back, so this one records the
# arguments it was started with and exits. Tests drive the poller's library functions directly.
printf '%s\n' "$@" > "${SPEECH_TEST_RECORD_DIR:-/tmp}/poller.args"
exit 0
