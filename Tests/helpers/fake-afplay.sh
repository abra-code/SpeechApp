#!/bin/bash
# fake-afplay.sh - stands in for /usr/bin/afplay under test (SPEECH_AFPLAY_BIN). A real one would
# play out of the speakers of whatever Mac runs the suite, so this one records the file it was
# asked for and then waits, the way a long recording would.
#
#   FAKE_AFPLAY_LOG   file each invocation's arguments are appended to, one line per call
#
# It replaces itself with sleep under its own name (exec -a), so its argv is the path the applet
# started, which is what playback_pid_is_ours checks before it signals anything. A test ends a
# playback by killing the process, the way reaching the end of a recording ends the real one.

[ -n "$FAKE_AFPLAY_LOG" ] && printf '%s\n' "$*" >> "$FAKE_AFPLAY_LOG"
exec -a "$0" /bin/sleep 600
