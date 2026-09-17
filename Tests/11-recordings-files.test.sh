#!/bin/sh
# 11-recordings-files.test.sh - the player that plays the selected recording, and the file
# buttons under the recordings list: show in the Finder, and move to the Trash with the alert that
# asks first. Taking a recording out of the list, which is the minus button and touches no file, is
# covered in 10-recordings.test.sh.
#
# open and osascript are fakes here (lib.test.speech.sh): the real ones would bring the Finder
# forward over whatever Mac runs this, and move the scratch recordings to the tester's own Trash.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

rec1="$OMCTEST_WORK/first.wav"
rec2="$OMCTEST_WORK/second.m4a"
gone_note="first.wav is no longer where it was. Take it out of the list, or add it again from its new place."

# A fresh window with both recordings listed, nothing selected and no alert asked.
open_tab() {
    reset_state
    alerts_reset
    /bin/rm -f "$FAKE_OPEN_LOG" "$FAKE_OSASCRIPT_LOG"
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

# ------------------------------------------------------------------------------------------------
section "the player shows a placeholder until a recording is selected, then plays that recording's file URL"
open_tab
placeholder_url="$(lib_call recording_file_url "$OMC_APP_BUNDLE_PATH/Contents/Resources/track-preview.mov")"
check "the placeholder is bundled" "yes" "$([ -s "$OMC_APP_BUNDLE_PATH/Contents/Resources/track-preview.mov" ] && echo yes || echo no)"
check "a new window shows the placeholder" "$placeholder_url" "$(ui_value "$REC_PREVIEW")"
url1="file://$(printf '%s' "$rec1" | /usr/bin/sed 's/ /%20/g')"
url2="file://$(printf '%s' "$rec2" | /usr/bin/sed 's/ /%20/g')"
select_recording "$rec1"
check "selecting a recording loads its file URL" "$url1" "$(ui_value "$REC_PREVIEW")"
select_recording "$rec2"
check "selecting another loads that one" "$url2" "$(ui_value "$REC_PREVIEW")"
check "a path with a space, a hash and a percent sign is encoded" \
    "file:///x/Take%20%232%2050%25.m4a" "$(lib_call recording_file_url "/x/Take #2 50%.m4a")"

section "the table re-selecting the same row does not reload the player, which would stop it playing"
writes_before="$(ui_calls "$url2")"
select_recording "$rec2"
check "no second write of the same recording" "$writes_before" "$(ui_calls "$url2")"

section "clearing the selection, Remove and Move to Trash put the placeholder in the player"
select_recording ""
end_quiet_window
select_recording ""
check "a cleared selection shows the placeholder" "$placeholder_url" "$(ui_value "$REC_PREVIEW")"
select_recording "$rec2"
check "a selection loads it again" "$url2" "$(ui_value "$REC_PREVIEW")"
omc_run speech.recordings.remove
check "Remove shows the placeholder" "$placeholder_url" "$(ui_value "$REC_PREVIEW")"
select_recording "$rec1"
check "a selection loads it again" "$url1" "$(ui_value "$REC_PREVIEW")"
omc_run speech.recordings.trash
omc_run speech.recordings.trash.confirm
check "Move to Trash shows the placeholder" "$placeholder_url" "$(ui_value "$REC_PREVIEW")"

section "starting Live stops the player, by loading the placeholder, and then loads the recording again"
open_tab
select_recording "$rec1"
writes_before="$(ui_calls "$url1")"
omc_run speech.live
check "the recording was loaded once more" "$((writes_before + 1))" "$(ui_calls "$url1")"
check "and it is what the player holds" "$url1" "$(ui_value "$REC_PREVIEW")"
omc_run speech.window.cancel

section "Show in Finder stays open through a batch; Trash waits with Remove"
open_tab
select_recording "$rec1"
printf 'running' > "$(rec_pane)/batch"
pane_call recordings refresh_recordings_actions "$(rec_pane)"
check "Show in Finder changes nothing, so it stays open" "1" "$(ui_enabled "$REC_REVEAL_BTN")"
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
omctest_end
