#!/bin/sh
# 12-transcript-size.test.sh - the size pickers of the Live and Recordings tabs: a window opens with
# the size last picked, a pick in either tab sizes both transcripts and moves the other picker, the
# size is kept for the next window, and an echo or a value that is not an option changes nothing.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

saved_size() { /bin/cat "$SPEECH_APP_SUPPORT/Settings/transcript.size" 2>/dev/null; }
# Both transcripts' fonts, then both pickers' values, as one line.
shown_sizes() {
    printf '%s|%s|%s|%s' "$(ui_prop "$LIVE_TRANSCRIPT" font)" "$(ui_prop "$REC_TRANSCRIPT" font)" \
        "$(ui_value "$LIVE_SIZE_PICKER")" "$(ui_value "$REC_SIZE_PICKER")"
}
font_of() { printf '{"size":%s,"design":"default"}' "$1"; }

# ------------------------------------------------------------------------------------------------
section "a first window shows both transcripts at the standard size"
reset_state
omc_run speech.window.init
check_status "init exits cleanly" 0
check "13 pt in both tabs, both pickers on the first option" "$(font_of 13)|$(font_of 13)|1|1" "$(shown_sizes)"
check "the window records its size" "13" "$(/bin/cat "$(spool)/transcript.size" 2>/dev/null)"
check "nothing is saved until the user picks" "" "$(saved_size)"

# ------------------------------------------------------------------------------------------------
section "a pick in either tab sizes both transcripts and is kept"
omc_fire speech.transcript.size.changed "$REC_SIZE_PICKER" 5
check_status "the Recordings pick exits cleanly" 0
check "32 pt in both tabs, the Live picker follows" "$(font_of 32)|$(font_of 32)|5|5" "$(shown_sizes)"
check "the window records it" "32" "$(/bin/cat "$(spool)/transcript.size" 2>/dev/null)"
check "and it is saved for the next window" "32" "$(saved_size)"

omc_fire speech.transcript.size.changed "$LIVE_SIZE_PICKER" 8
check "a Live pick of the last option: 64 pt everywhere" "$(font_of 64)|$(font_of 64)|8|8" "$(shown_sizes)"
check "saved" "64" "$(saved_size)"

# ------------------------------------------------------------------------------------------------
section "a pick of the size the window already has, and values that are not options, change nothing"
/bin/rm -f "$SPEECH_APP_SUPPORT/Settings/transcript.size"
omc_fire speech.transcript.size.changed "$REC_SIZE_PICKER" 8
check "the size the window already has ends the handler before it saves" "" "$(saved_size)"
for bogus in 0 9 "" "3.5" "18 pt"; do
    omc_fire speech.transcript.size.changed "$LIVE_SIZE_PICKER" "$bogus"
    check "picker value '$bogus' is ignored" "$(font_of 64)|$(font_of 64)|8|8|" "$(shown_sizes)|$(saved_size)"
done
omc_control "$REC_SIZE_PICKER" 2
omc_fire speech.transcript.size.changed "$REC_TRANSCRIPT"
check "a trigger that is not a size picker is ignored" "$(font_of 64)|$(font_of 64)|8|8|" "$(shown_sizes)|$(saved_size)"

# ------------------------------------------------------------------------------------------------
section "the next window opens at the saved size; a size no longer offered falls back"
reset_state
/bin/mkdir -p "$SPEECH_APP_SUPPORT/Settings"
printf '48' > "$SPEECH_APP_SUPPORT/Settings/transcript.size"
omc_run speech.window.init
check "48 pt in both tabs, both pickers on its option" "$(font_of 48)|$(font_of 48)|7|7" "$(shown_sizes)"

reset_state
/bin/mkdir -p "$SPEECH_APP_SUPPORT/Settings"
printf '14' > "$SPEECH_APP_SUPPORT/Settings/transcript.size"
omc_run speech.window.init
check "an unoffered 14 pt opens at the standard size" "$(font_of 13)|$(font_of 13)|1|1" "$(shown_sizes)"

check "no writes to undeclared view ids" "" "$(ui_unknown_writes)"
omctest_end
