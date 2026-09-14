#!/bin/sh
# 60-apple-languages.test.sh - Apple's engines on this Mac: a row that cannot run here says why in
# the Models window and stays out of the pickers, and a transcription waiting for Apple's language
# files names the language and keeps counting while nothing arrives.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

us="$(printf '\037')"
scripts="$OMCTEST_APP/Contents/Resources/Scripts"
old_mac='{"rows":[{"id":"apple.dictation","label":"Apple dictation (built in)","engine":"apple","role":"transcriber","state":"system_managed","available":false,"installed":true,"languages":["en"],"modes":["batch","live"],"reason":"needs macOS 26 or later (this Mac runs macOS 15.5.0)"}]}'

# A status with its clock replaced, so a check does not depend on the second the tick ran in.
status_without_clock() { ui_value "$REC_STATUS" | /usr/bin/sed 's/[0-9][0-9]*:[0-9][0-9]/M:SS/'; }

# ------------------------------------------------------------------------------------------------
section "an Apple row this Mac cannot run says why on its card, and is not offered to transcribe"
card_line="$(printf '%s' "$old_mac" \
    | /usr/bin/jq -r --argjson base 2000 --argjson builtin 1102 --argjson installed 1202 --argjson available 1302 \
        -f "$scripts/speech.models.jq")"
# A raw line starts with its kind, so each field is one column further along than in cards.list.
check "its state gives speech's reason, with nothing to download or delete" \
    "Not available on this Mac: needs macOS 26 or later (this Mac runs macOS 15.5.0)|0 0" \
    "$(printf '%s\n' "$card_line" | /usr/bin/awk -F"$us" '$1 == "L" { print $10 "|" $11 " " $12; exit }')"
check "it stays in the Built into macOS section" "1102" \
    "$(printf '%s\n' "$card_line" | /usr/bin/awk -F"$us" '$1 == "C" { print $2; exit }')"
check "the pickers leave it out" "" "$(printf '%s' "$old_mac" | /usr/bin/jq -r -f "$scripts/speech.catalog.jq")"

# ------------------------------------------------------------------------------------------------
section "a transcription waiting for Apple's language files names the language"
reset_state
rec="$OMCTEST_WORK/lezione.wav"
printf 'RIFF not really audio' > "$rec"
"$OMC_OMC_SUPPORT_PATH/pasteboard" SPEECH_OPEN_PATH set "$rec"
omc_run speech.window.init
load_window_models
FAKE_SPEECH_MODE=language_files
export FAKE_SPEECH_MODE
omc_run speech.recordings.transcribe
poll_tick
item="$(item_dir "$rec")"
omc_wait_for "/usr/bin/grep -q installing \"$item/events.jsonl\""
poll_tick
check "the status names Italian and the percent" \
    "Downloading Apple's Italian speech files... 0%" "$(ui_value "$REC_STATUS")"
check "the run notes when the download started" "yes" \
    "$(/usr/bin/grep -q '^[0-9][0-9]*$' "$item/language_files.since" 2>/dev/null && echo yes || echo no)"

section "every tick adds the time spent, even when no event arrives"
printf '%s\n' "$(( $(/bin/date +%s) - 15 ))" > "$item/language_files.since"
poll_tick
check "after 15 seconds the time is shown" \
    "Downloading Apple's Italian speech files... 0% (M:SS)" "$(status_without_clock)"
check "and it is the time spent" "0:1" "$(ui_value "$REC_STATUS" | /usr/bin/sed -n 's/.*(\(0:1\)[0-9]).*/\1/p')"

section "a download with nothing received after a minute says it may be held back"
printf '%s\n' "$(( $(/bin/date +%s) - 125 ))" > "$item/language_files.since"
printf '%s\n' "$(( $(/bin/date +%s) - 125 ))" > "$item/language_files.moved"
poll_tick
check "the status says nothing has arrived and what to do" \
    "Downloading Apple's Italian speech files: nothing has arrived after M:SS. A slow or metered connection can hold the download back; press Stop to try again later." \
    "$(status_without_clock)"
check "two minutes have passed" "2:0" "$(ui_value "$REC_STATUS" | /usr/bin/sed -n 's/.*after \(2:0\)[0-9].*/\1/p')"

section "a download that moved and then stopped says so too"
printf '%s\n' '{"file":"it_IT","fraction":0.03,"model":"apple.dictation","phase":"installing","t":200,"type":"model.progress"}' >> "$item/events.jsonl"
poll_tick
check "the new percent restarts the stall clock" "Downloading Apple's Italian speech files... 3% (M:SS)" "$(status_without_clock)"
printf '%s\n' "$(( $(/bin/date +%s) - 95 ))" > "$item/language_files.moved"
poll_tick
check "after a minute and a half at 3% the status says nothing more has arrived" \
    "Downloading Apple's Italian speech files... 3%, and nothing more for M:SS. A slow or metered connection can hold the download back; press Stop to try again later." \
    "$(status_without_clock)"
check "the stall is counted from the last movement" "1:3" "$(ui_value "$REC_STATUS" | /usr/bin/sed -n 's/.*more for \(1:3\)[0-9].*/\1/p')"

section "when the engine is ready, the waiting is over"
printf '%s\n' '{"engine":"apple.dictation","load_seconds":130,"locale":"it_IT","model":"apple.dictation","t":131,"type":"engine.ready"}' >> "$item/events.jsonl"
poll_tick
check_absent "the start time is gone" "$item/language_files.since"
check "the status is the transcription's again" "Transcribing" "$(ui_value "$REC_STATUS" | /usr/bin/cut -c1-12)"
shown_before="$(ui_value "$REC_STATUS")"
poll_tick
check "a later tick does not bring the download status back" "$shown_before" "$(ui_value "$REC_STATUS")"

omc_run speech.recordings.stop
reap_fake

check "no writes to undeclared view ids" "" "$(ui_unknown_writes)"
omctest_end
