#!/bin/sh
# fake-open.sh - stands in for /usr/bin/open under test (SPEECH_OPEN_BIN). A real one would bring
# the Finder forward over the suite and open a window on the test's scratch directory.
#
#   FAKE_OPEN_LOG   file each invocation's arguments are appended to, one line per call

[ -n "$FAKE_OPEN_LOG" ] && printf '%s\n' "$*" >> "$FAKE_OPEN_LOG"
exit 0
