#!/bin/sh
# 11-recordings-files.test.sh - the file buttons under the recordings list: play and stop, show in
# the Finder, and move to the Trash with the alert that asks first. Taking a recording out of the
# list, which is the minus button and touches no file, is covered in 10-recordings.test.sh.
#
# afplay, open and osascript are all fakes here (lib.test.speech.sh): the real ones would play out
# of the speakers of whatever Mac runs this, bring the Finder forward over it, and move the scratch
# recordings to the tester's own Trash.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

rec1="$OMCTEST_WORK/first.wav"
rec2="$OMCTEST_WORK/second.m4a"
gone_note="first.wav is no longer where it was. Take it out of the list, or add it again from its new place."

# A fresh window with both recordings listed, nothing selected, nothing playing and no alert asked.
open_tab() {
    reap_fake_afplay
    reset_state
    alerts_reset
    /bin/rm -f "$FAKE_AFPLAY_LOG" "$FAKE_OPEN_LOG" "$FAKE_OSASCRIPT_LOG"
    /bin/rm -rf "$FAKE_TRASH_DIR"
    printf 'RIFF not really audio' > "$rec1"
    printf 'M4A not really audio either' > "$rec2"
    "$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH set "$rec1
$rec2"
    omc_run speech.window.init
    load_window_models
}

select_recording() {   # $1 = path
    omc_table_cell "$REC_TABLE" 4 "$1"
    omc_run speech.recordings.selected
}

# The pid of the playback going on now, which a section kills to stand for reaching the end.
play_pid() { /bin/cat "$(rec_pane)/play.pid" 2>/dev/null; }

alive_or_dead() {   # $1 = pid
    /bin/kill -0 "$1" 2>/dev/null && printf 'alive' || printf 'dead'
}

# ------------------------------------------------------------------------------------------------
section "the three file buttons wait for a selection, and Play starts out offering to play"
open_tab
check "the window opens with all three closed" "0 0 0" \
    "$(ui_enabled "$REC_PLAY_BTN") $(ui_enabled "$REC_REVEAL_BTN") $(ui_enabled "$REC_TRASH_BTN")"
pane_call recordings refresh_recordings_actions "$(rec_pane)"
check "and the poller leaves them closed with nothing selected" "0 0 0" \
    "$(ui_enabled "$REC_PLAY_BTN") $(ui_enabled "$REC_REVEAL_BTN") $(ui_enabled "$REC_TRASH_BTN")"
check "Play shows the play icon" "play.fill" "$(ui_prop "$REC_PLAY_BTN" systemImage)"
check "and says what it does" "Play the selected recording" "$(ui_prop "$REC_PLAY_BTN" help)"
select_recording "$rec1"
check "a selection opens all three" "1 1 1" \
    "$(ui_enabled "$REC_PLAY_BTN") $(ui_enabled "$REC_REVEAL_BTN") $(ui_enabled "$REC_TRASH_BTN")"

# ------------------------------------------------------------------------------------------------
section "Play starts the selected recording, and the button then offers to stop it"
omc_run speech.recordings.play
check_status "play exits cleanly" 0
check "afplay was given the recording" "$rec1" "$(/bin/cat "$FAKE_AFPLAY_LOG" 2>/dev/null)"
check "the pane knows what is playing" "$rec1" "$(/bin/cat "$(rec_pane)/play.path" 2>/dev/null)"
check "the button turns into a stop" "stop.fill" "$(ui_prop "$REC_PLAY_BTN" systemImage)"
check "and says so" "Stop playing this recording" "$(ui_prop "$REC_PLAY_BTN" help)"

section "pressing it again stops the playback"
pid="$(play_pid)"
omc_run speech.recordings.play
check "the process was signaled" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" > /dev/null; alive_or_dead "$pid")"
check_absent "the pane forgot the pid" "$(rec_pane)/play.pid"
check "the button offers to play again" "play.fill" "$(ui_prop "$REC_PLAY_BTN" systemImage)"
check "and afplay was not started a second time" "1" "$(/usr/bin/grep -c . "$FAKE_AFPLAY_LOG")"

section "a playback that reaches the end of the recording turns the button back into Play"
omc_run speech.recordings.play
pid="$(play_pid)"
/bin/kill -KILL "$pid" 2>/dev/null
omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" > /dev/null
poll_tick
check_absent "the poller forgot it" "$(rec_pane)/play.pid"
check "the button offers to play" "play.fill" "$(ui_prop "$REC_PLAY_BTN" systemImage)"

section "playing follows the selection: choosing another recording stops it"
omc_run speech.recordings.play
pid="$(play_pid)"
select_recording "$rec2"
check "the playback stopped" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" > /dev/null; alive_or_dead "$pid")"
check_absent "and nothing is playing" "$(rec_pane)/play.pid"

section "choosing the recording that is already playing leaves it alone"
omc_run speech.recordings.play
pid="$(play_pid)"
select_recording "$rec2"
check "it is still playing" "alive" "$(alive_or_dead "$pid")"
check "and still the one the pane knows about" "$rec2" "$(/bin/cat "$(rec_pane)/play.path" 2>/dev/null)"

section "taking a playing recording out of the list stops it"
select_recording "$rec2"
omc_run speech.recordings.play
pid="$(play_pid)"
omc_run speech.recordings.remove
check "the playback went with it" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" > /dev/null; alive_or_dead "$pid")"
check_absent "nothing is playing" "$(rec_pane)/play.pid"

section "closing the window stops a playback, since nothing would be left to stop it with"
open_tab
select_recording "$rec1"
omc_run speech.recordings.play
pid="$(play_pid)"
omc_run speech.window.cancel
check "the playback stopped" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" > /dev/null; alive_or_dead "$pid")"
check_absent "the spool is gone" "$(spool)"

# ------------------------------------------------------------------------------------------------
section "nothing is played into an open microphone"
open_tab
select_recording "$rec1"
# What the tab calls recording: a capture directory in the running state.
/bin/mkdir -p "$(rec_pane)/capture-test"
printf 'running' > "$(rec_pane)/capture-test/state"
printf 'capture-test' > "$(rec_pane)/capture"
omc_run speech.recordings.play
check "afplay was not started" "" "$(/bin/cat "$FAKE_AFPLAY_LOG" 2>/dev/null)"
check "and the status says why" \
    "Stop the recording before playing one back, or the microphone will hear it." "$(ui_value "$REC_STATUS")"
pane_call recordings refresh_recordings_actions "$(rec_pane)"
check "Play is closed while the microphone is open" "0" "$(ui_enabled "$REC_PLAY_BTN")"
/bin/rm -f "$(rec_pane)/capture"

section "nor into a live session: Live closes Play, and starting one stops a playback"
open_tab
select_recording "$rec1"
omc_run speech.recordings.play
pid="$(play_pid)"
omc_run speech.live
check "starting Live stopped the playback" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" > /dev/null; alive_or_dead "$pid")"
check_absent "and nothing is playing" "$(rec_pane)/play.pid"
pane_call recordings refresh_recordings_actions "$(rec_pane)"
check "Play is closed while the live session runs" "0" "$(ui_enabled "$REC_PLAY_BTN")"
/bin/rm -f "$FAKE_AFPLAY_LOG"
omc_run speech.recordings.play
check "afplay was not started" "" "$(/bin/cat "$FAKE_AFPLAY_LOG" 2>/dev/null)"
check "and the status says why" \
    "Stop the live session before playing a recording back, or the microphone will hear it." "$(ui_value "$REC_STATUS")"
omc_run speech.window.cancel

section "quitting the app stops a playback: its afplay is not a speech process, and the spool goes"
open_tab
select_recording "$rec1"
omc_run speech.recordings.play
pid="$(play_pid)"
omc_run app.will.terminate
check "the playback stopped" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" > /dev/null; alive_or_dead "$pid")"
check_absent "and the spools are gone" "$SPEECH_APP_SUPPORT/Sessions"

section "a press that arrives while another is still being handled is a no-op, not a second afplay"
open_tab
select_recording "$rec1"
/bin/mkdir "$(rec_pane)/play.lock"
omc_run speech.recordings.play
check "afplay was not started" "" "$(/bin/cat "$FAKE_AFPLAY_LOG" 2>/dev/null)"
check_absent "and nothing is playing" "$(rec_pane)/play.pid"
/bin/rmdir "$(rec_pane)/play.lock"
omc_run speech.recordings.play
check "once the first handler is done, a press plays" "$rec1" "$(/bin/cat "$(rec_pane)/play.path" 2>/dev/null)"
check_absent "and the handler left no lock behind" "$(rec_pane)/play.lock"

section "Play and Show in Finder stay open through a batch; Trash waits with Remove"
open_tab
select_recording "$rec1"
printf 'running' > "$(rec_pane)/batch"
pane_call recordings refresh_recordings_actions "$(rec_pane)"
check "Play and Show in Finder change nothing, so they stay open" "1 1" \
    "$(ui_enabled "$REC_PLAY_BTN") $(ui_enabled "$REC_REVEAL_BTN")"
check "Trash and Remove both take the recording out of the list, so both wait" "0 0" \
    "$(ui_enabled "$REC_TRASH_BTN") $(ui_enabled "$REC_REMOVE_BTN")"
/bin/rm -f "$(rec_pane)/batch"

# ------------------------------------------------------------------------------------------------
section "Show in Finder reveals the selected recording"
open_tab
select_recording "$rec1"
omc_run speech.recordings.reveal
check_status "reveal exits cleanly" 0
check "the Finder was asked to reveal it" "-R $rec1" "$(/bin/cat "$FAKE_OPEN_LOG" 2>/dev/null)"

section "a recording that has been moved since it was listed says so, and keeps saying it"
/bin/mv "$rec1" "$OMCTEST_WORK/moved.wav"
/bin/rm -f "$FAKE_OPEN_LOG"
omc_run speech.recordings.reveal
check "the Finder was not asked" "" "$(/bin/cat "$FAKE_OPEN_LOG" 2>/dev/null)"
check "the status says what happened" "$gone_note" "$(ui_value "$REC_STATUS")"
poll_tick
check "and a tick of the poller does not paint over it" "$gone_note" "$(ui_value "$REC_STATUS")"
/bin/mv "$OMCTEST_WORK/moved.wav" "$rec1"

# ------------------------------------------------------------------------------------------------
section "Trash asks first and moves nothing until it is answered"
open_tab
select_recording "$rec1"
omc_run speech.recordings.trash
check_status "trash exits cleanly" 0
check "the alert names the recording" "Move \"first.wav\" to the Trash?" "$(ui_alert_title)"
check "and says what becomes of it" \
    "It leaves the list with it. Any transcript saved beside it stays where it is, and you can put the recording back from the Trash." \
    "$(ui_alert_message)"
check "the destructive button is the one that confirms" \
    "speech.recordings.trash.confirm" "$(ui_alert_action "Move to Trash")"
check "the recording waits in pending.trash" "$rec1" "$(/bin/cat "$(rec_pane)/pending.trash" 2>/dev/null)"
check_exists "and it has not moved" "$rec1"
check "the Finder was not asked" "" "$(/bin/cat "$FAKE_OSASCRIPT_LOG" 2>/dev/null)"

section "Move to Trash moves the recording and takes it out of the list"
omc_run speech.recordings.trash.confirm
check_status "the confirm exits cleanly" 0
check_absent "the recording has left where it was" "$rec1"
check_exists "and is in the Trash" "$FAKE_TRASH_DIR/first.wav"
check "the Finder was asked through the applet's own AppleScript" \
    "$OMCTEST_APP/Contents/Resources/Scripts/speech.trash.applescript $rec1" "$(/bin/cat "$FAKE_OSASCRIPT_LOG")"
check "it is no longer listed" "no" "$(/usr/bin/grep -Fxq -- "$rec1" "$(rec_pane)/list.tsv" && echo yes || echo no)"
check "only the other recording is in the table" "1" "$(ui_row_count "$REC_TABLE")"
check "which is untouched" "yes" "$(/usr/bin/grep -Fxq -- "$rec2" "$(rec_pane)/list.tsv" && echo yes || echo no)"
check_absent "the pending recording is consumed" "$(rec_pane)/pending.trash"
check "the status says what happened" "Moved first.wav to the Trash." "$(ui_value "$REC_STATUS")"
poll_tick
check "and goes on saying it" "Moved first.wav to the Trash." "$(ui_value "$REC_STATUS")"

section "a Finder that will not be controlled keeps the recording and says the Finder's own words"
open_tab
select_recording "$rec1"
omc_run speech.recordings.trash
FAKE_OSASCRIPT_MODE=refused
export FAKE_OSASCRIPT_MODE
omc_run speech.recordings.trash.confirm
unset FAKE_OSASCRIPT_MODE
check_exists "the recording is still there" "$rec1"
check "and still listed" "yes" "$(/usr/bin/grep -Fxq -- "$rec1" "$(rec_pane)/list.tsv" && echo yes || echo no)"
check "the status carries the reason" \
    "Could not move first.wav to the Trash: Not authorized to send Apple events to Finder. (-1743)" \
    "$(ui_value "$REC_STATUS")"

section "a recording that is playing is stopped before it is moved to the Trash"
open_tab
select_recording "$rec1"
omc_run speech.recordings.play
pid="$(play_pid)"
omc_run speech.recordings.trash
omc_run speech.recordings.trash.confirm
check "the playback stopped" "dead" "$(omc_wait_for "! /bin/kill -0 $pid 2>/dev/null" > /dev/null; alive_or_dead "$pid")"
check_exists "and the recording is in the Trash" "$FAKE_TRASH_DIR/first.wav"

section "Trash waits while a batch runs, and so does a confirm that arrives after one started"
open_tab
select_recording "$rec1"
printf 'running' > "$(rec_pane)/batch"
alerts_before="$(ui_calls omc_present_alert)"
omc_run speech.recordings.trash
check "nothing was asked" "$alerts_before" "$(ui_calls omc_present_alert)"
check "the status says why" \
    "Stop the transcription before moving a recording to the Trash." "$(ui_value "$REC_STATUS")"
printf '%s' "$rec1" > "$(rec_pane)/pending.trash"
omc_run speech.recordings.trash.confirm
check "the Finder was not asked" "" "$(/bin/cat "$FAKE_OSASCRIPT_LOG" 2>/dev/null)"
check_exists "and the recording is where it was" "$rec1"
/bin/rm -f "$(rec_pane)/batch"

section "a confirm for a recording that left the list in the meantime does nothing"
open_tab
select_recording "$rec1"
omc_run speech.recordings.trash
omc_run speech.recordings.remove
omc_run speech.recordings.trash.confirm
check "the Finder was not asked" "" "$(/bin/cat "$FAKE_OSASCRIPT_LOG" 2>/dev/null)"
check_exists "and the recording is where it was" "$rec1"

section "a recording listed through a link is refused: the Finder would move the file it points to"
open_tab
link="$OMCTEST_WORK/link.wav"
/bin/ln -sf "$rec2" "$link"
printf '%s\n' "$link" >> "$(rec_pane)/list.tsv"
select_recording "$link"
alerts_before="$(ui_calls omc_present_alert)"
omc_run speech.recordings.trash
check "nothing was asked" "$alerts_before" "$(ui_calls omc_present_alert)"
check "the status says why" \
    "link.wav is a link to another file. Move that file to the Trash from the Finder, or take the link out of the list." \
    "$(ui_value "$REC_STATUS")"
printf '%s' "$link" > "$(rec_pane)/pending.trash"
omc_run speech.recordings.trash.confirm
check "a confirm that names it is refused too" "" "$(/bin/cat "$FAKE_OSASCRIPT_LOG" 2>/dev/null)"
check_exists "the file it points to is where it was" "$rec2"
check "and so is the link" "yes" "$([ -L "$link" ] && echo yes || echo no)"
/bin/rm -f "$link"

# ------------------------------------------------------------------------------------------------
section "a new window starts with the Join checkbox the way it was last left"
open_tab
check "off by default" "absent|" "$([ -f "$(rec_pane)/join" ] && echo present || echo absent)|$(ui_value "$REC_JOIN_TOGGLE")"
/bin/mkdir -p "$SPEECH_APP_SUPPORT/Settings"
printf '1' > "$SPEECH_APP_SUPPORT/Settings/recordings.join"
omc_run speech.window.init
check "on when it was left on" "present|true" "$([ -f "$(rec_pane)/join" ] && echo present || echo absent)|$(ui_value "$REC_JOIN_TOGGLE")"

# ------------------------------------------------------------------------------------------------
section "cumulative: the window was only written through ids it declares"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no table clobbered" "" "$(ui_suspect_writes)"
check "no harness misuse" "" "$(ui_errors)"

reap_fake
reap_fake_afplay
omctest_end
