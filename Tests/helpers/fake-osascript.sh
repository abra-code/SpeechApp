#!/bin/sh
# fake-osascript.sh - stands in for /usr/bin/osascript under test (SPEECH_OSASCRIPT_BIN). The only
# script the applet runs through it is speech.trash.applescript, which asks the Finder to move a
# recording to the Trash: a real one would move the test's scratch recordings to the Trash of
# whoever is running the suite, and would ask them for permission to control the Finder first.
#
# It is called the way the applet calls osascript: the script first, then the file. Its errors are
# shaped the way the real one shapes them, script path and position first, since the applet has
# to take those off before showing the Finder's words.
#
#   FAKE_OSASCRIPT_LOG    file each invocation's arguments are appended to, one line per call
#   FAKE_TRASH_DIR        directory to move the file into, standing in for the Trash (required
#                         in ok mode)
#   FAKE_OSASCRIPT_MODE   ok (default), or refused - the Finder's own words when the user has not
#                         allowed this app to control it, on stderr with a non-zero status

[ -n "$FAKE_OSASCRIPT_LOG" ] && printf '%s\n' "$*" >> "$FAKE_OSASCRIPT_LOG"

target="$2"   # $1 is the AppleScript, which this fake stands in for rather than runs

if [ "$FAKE_OSASCRIPT_MODE" = refused ]; then
    printf '%s:74:79: execution error: Not authorized to send Apple events to Finder. (-1743)\n' "$1" >&2
    exit 1
fi

if [ ! -e "$target" ]; then
    printf '%s:74:79: execution error: File %s wasn'"'"'t found. (-43)\n' "$1" "$target" >&2
    exit 1
fi

/bin/mkdir -p "$FAKE_TRASH_DIR" 2>/dev/null
/bin/mv -f "$target" "$FAKE_TRASH_DIR/"
move_status=$?
if [ "$move_status" -ne 0 ]; then
    printf '%s:74:79: execution error: The operation could not be completed. (-1728)\n' "$1" >&2
    exit 1
fi

exit 0
