#!/bin/sh
# 41-suggest.test.sh - the Models window's "Best for <language>" box: the picks speech.suggest.awk
# makes from the measurements, and the box that shows them.
#
# Two layers. The rules are checked against files this test writes, so a rule is exercised by
# itself and no fixture has to carry every case at once: the metric that follows the language, the
# tie that goes to the much smaller model, a second corpus that disagrees, and a language nothing
# was measured in. The box is then checked against the shared catalog fixture, for the language
# list, the wording, what it remembers and what a quiet tick pushes.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.speech.sh"

SPEECH_REFERENCE_MEASUREMENTS="$OMCTEST_FIXTURES/suggest-reference.tsv"
export SPEECH_REFERENCE_MEASUREMENTS

catalog_copy="$OMCTEST_WORK/catalog.json"
tab="$(printf '\t')"

suggest_awk() {   # $1 = language, $2 = models.tsv, $3 = results.tsv, $4 = reference.tsv, $5 = live.tsv
    /usr/bin/awk -F"$tab" -v language="$1" \
        -v mlx="$mlx_mark" -v ggml="$ggml_mark" -v fluid="$fluid_mark" \
        -f "$OMCTEST_APP/Contents/Resources/Scripts/speech.suggest.awk" \
        role=models "$2" role=results "$3" role=reference "$4" role=live "$5"
}

# One field of the record for a mode and kind: 3 = id, 6 = figure, 7 = the second figure.
pick_field() {   # $1 = picks output, $2 = mode, $3 = kind, $4 = field
    printf '%s\n' "$1" | /usr/bin/awk -F"$tab" -v mode="$2" -v kind="$3" -v field="$4" \
        '$1 == mode && $2 == kind { print $field; exit }'
}

# omctest has check and check_grep; a substring of a pushed line needs this, the same one-liner
# 40-models.test.sh uses for the information sheet.
check_contains() { case "$3" in *"$2"*) check "$1" yes yes ;; *) check "$1" "$2" "$3" ;; esac; }

write_models() { /bin/cat > "$OMCTEST_WORK/models.tsv"; }
write_reference() { /bin/cat > "$OMCTEST_WORK/reference.tsv"; }
write_live() { /bin/cat > "$OMCTEST_WORK/live.tsv"; }

open_models_window() {
    reset_state
    /bin/cp -f "$OMCTEST_FIXTURES/catalog.json" "$catalog_copy"
    FAKE_SPEECH_CATALOG="$catalog_copy"
    export FAKE_SPEECH_CATALOG
    omc_run speech.models.init
}

tick() { models_call poll_models_window "$(spool)"; }

# ------------------------------------------------------------------------------------------------
section "The pick is the lowest error rate, with the faster row named beside it"

write_models <<EOF
one${tab}One${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
two${tab}Two${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
three${tab}Three${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
one${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
two${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.50${tab}2.20${tab}90.0${tab}1000000000${tab}2026-09-08T00:00:00Z
three${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}20.00${tab}9.00${tab}200.0${tab}1000000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the most accurate row is the pick" "one" "$(pick_field "$picks" recordings accurate 3)"
check "and its error rate is its own" "4.00" "$(pick_field "$picks" recordings accurate 6)"
check "the faster row close behind it is named" "two" "$(pick_field "$picks" recordings fast 3)"
check "a row far less accurate is not named however fast it is" "" \
    "$(printf '%s\n' "$picks" | /usr/bin/grep -c "	three	" | /usr/bin/sed 's/^0$//')"

section "A row only counts as faster when it is clearly faster"

write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
one${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
two${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.50${tab}2.20${tab}12.0${tab}1000000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the pick is still the accurate row" "one" "$(pick_field "$picks" recordings accurate 3)"
check "a fifth faster is not worth a sentence" "" "$(pick_field "$picks" recordings fast 3)"

section "Two rows a fraction apart: the much smaller one takes the pick"

write_models <<EOF
big${tab}Big${tab}en${tab}batch${tab}ggml${tab}installed${tab}2000000000
small${tab}Small${tab}en${tab}batch${tab}ggml${tab}installed${tab}500000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
big${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}2000000000${tab}2026-09-08T00:00:00Z
small${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.30${tab}2.10${tab}10.0${tab}500000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "a quarter of the size for three tenths of a point wins" "small" \
    "$(pick_field "$picks" recordings accurate 3)"

write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
big${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}2000000000${tab}2026-09-08T00:00:00Z
small${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}5.00${tab}2.60${tab}10.0${tab}500000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "a whole point is too much to trade for size" "big" \
    "$(pick_field "$picks" recordings accurate 3)"

section "The pick does not drift: every row is compared with the best, not with the last winner"

# Four rows, each a third of a point behind the one before and slightly smaller. Comparing each
# against the current winner would walk the pick to the last of them; the answer is the first.
write_models <<EOF
a${tab}A${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
b${tab}B${tab}en${tab}batch${tab}ggml${tab}installed${tab}999000000
c${tab}C${tab}en${tab}batch${tab}ggml${tab}installed${tab}998000000
d${tab}D${tab}en${tab}batch${tab}ggml${tab}installed${tab}997000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
a${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}2.00${tab}1.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
b${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}2.30${tab}1.10${tab}10.0${tab}999000000${tab}2026-09-08T00:00:00Z
c${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}2.60${tab}1.20${tab}10.0${tab}998000000${tab}2026-09-08T00:00:00Z
d${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}2.90${tab}1.30${tab}10.0${tab}997000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the best row keeps the pick" "a" "$(pick_field "$picks" recordings accurate 3)"

section "A language that writes no spaces is judged on characters, not words"

write_models <<EOF
one${tab}One${tab}zh${tab}batch${tab}ggml${tab}installed${tab}1000000000
two${tab}Two${tab}zh${tab}batch${tab}ggml${tab}installed${tab}1000000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
one${tab}cmn_hans_cn${tab}26.6.2${tab}zh-CN${tab}100${tab}99.80${tab}7.20${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
two${tab}cmn_hans_cn${tab}26.6.2${tab}zh-CN${tab}100${tab}99.70${tab}12.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk zh "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the lower character error rate wins, not the lower word error rate" "one" \
    "$(pick_field "$picks" recordings accurate 3)"
check "and the record says which metric it used" "cer" "$(pick_field "$picks" recordings accurate 5)"

section "This Mac's own measurement beats the published one for the same model and corpus"

write_models <<EOF
one${tab}One${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
two${tab}Two${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
one${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
two${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}6.00${tab}3.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
EOF
/bin/cat > "$OMCTEST_WORK/results.tsv" <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date${tab}machine${tab}sample${tab}status${tab}note
one${tab}en_us${tab}26.7.0${tab}en-US${tab}100${tab}9.00${tab}4.00${tab}10.0${tab}1000000000${tab}2026-09-17T00:00:00Z${tab}Apple M5${tab}100${tab}ok${tab}
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" "$OMCTEST_WORK/results.tsv" "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the row this Mac measured worse is no longer the pick" "two" \
    "$(pick_field "$picks" recordings accurate 3)"
check "and the pick says where its figure came from" "reference" \
    "$(pick_field "$picks" recordings accurate 10)"

/bin/cat > "$OMCTEST_WORK/results.tsv" <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date${tab}machine${tab}sample${tab}status${tab}note
one${tab}en_us${tab}26.7.0${tab}en-US${tab}100${tab}9.00${tab}4.00${tab}10.0${tab}1000000000${tab}2026-09-17T00:00:00Z${tab}Apple M5${tab}100${tab}failed${tab}out of memory
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" "$OMCTEST_WORK/results.tsv" "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "a failed measurement of this Mac's is not a figure at all" "one" \
    "$(pick_field "$picks" recordings accurate 3)"

section "Among the models much smaller than the best, the most accurate one is named"

# Two rows within the tie band and both far smaller than the best. Naming the very smallest would
# trade accuracy for a size difference the rule does not care about.
write_models <<EOF
best${tab}Best${tab}en${tab}batch${tab}ggml${tab}installed${tab}2000000000
middle${tab}Middle${tab}en${tab}batch${tab}ggml${tab}installed${tab}700000000
tiny${tab}Tiny${tab}en${tab}batch${tab}ggml${tab}installed${tab}600000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
best${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}2000000000${tab}2026-09-08T00:00:00Z
middle${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.20${tab}2.10${tab}10.0${tab}700000000${tab}2026-09-08T00:00:00Z
tiny${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.35${tab}2.20${tab}10.0${tab}600000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the more accurate of the two small rows wins" "middle" \
    "$(pick_field "$picks" recordings accurate 3)"

section "Half a point is not close when the best row is already excellent"

# The LibriSpeech case: 1.41% against 1.75% is inside half a point and a quarter more errors. The
# relative margin is what keeps the accurate row named there while a fifth of a point at 6% still
# goes to the smaller model.
write_models <<EOF
accurate${tab}Accurate${tab}en${tab}batch${tab}ggml${tab}installed${tab}2500000000
small${tab}Small${tab}en${tab}batch${tab}ggml${tab}installed${tab}600000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
accurate${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}1.41${tab}0.70${tab}10.0${tab}2500000000${tab}2026-09-08T00:00:00Z
small${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}1.75${tab}0.80${tab}10.0${tab}600000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "a quarter more errors is not a tie, whatever the size" "accurate" \
    "$(pick_field "$picks" recordings accurate 3)"

section "Two splits of one corpus are never compared with each other"

# test-clean and test-other are different recordings. Taking the lower of the two numbers would
# make the easier split decide, and would name a model that is not the best on either.
write_models <<EOF
read${tab}Read${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
clean${tab}Clean${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
other${tab}Other${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
read${tab}en_us${tab}26.6.2${tab}en-US${tab}647${tab}5.00${tab}2.50${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
clean${tab}librispeech-test-clean${tab}26.6.2${tab}en-US${tab}2620${tab}2.00${tab}1.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
other${tab}librispeech-test-other${tab}26.6.2${tab}en-US${tab}2939${tab}4.00${tab}2.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the language's own split answers first, whatever the other numbers are" "read" \
    "$(pick_field "$picks" recordings accurate 3)"
check "one other corpus answers too, and a third does not" "2" \
    "$(printf '%s\n' "$picks" | /usr/bin/grep -c "^recordings	accurate")"
check "and the second answer is a split of its own, not the two of them merged" "clean" \
    "$(printf '%s\n' "$picks" | /usr/bin/awk -F"$tab" '$1 == "recordings" && $2 == "accurate" { last = $3 } END { print last }')"

section "A model already named is not offered again as another corpus's answer"

write_models <<EOF
one${tab}One${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
two${tab}Two${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
one${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
two${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.30${tab}2.10${tab}90.0${tab}1000000000${tab}2026-09-08T00:00:00Z
two${tab}librispeech-test-clean${tab}26.6.2${tab}en-US${tab}2620${tab}1.40${tab}0.70${tab}90.0${tab}1000000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the row named as the faster one is not repeated for the other corpus" "1" \
    "$(printf '%s\n' "$picks" | /usr/bin/grep -c "^recordings	accurate")"

section "A live row that shows no text until a sentence closes says so"

write_models <<EOF
blocks${tab}Blocks${tab}en${tab}batch,live${tab}fluid${tab}installed${tab}500000000
EOF
write_live <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}pace${tab}wer_pct${tab}cer_pct${tab}peak_memory_bytes${tab}load_seconds${tab}first_partial_median_s${tab}final_lag_median_s${tab}final_lag_worst_s${tab}finish_median_s${tab}trailing_words_lost${tab}rows_without_partials${tab}dropped_buffers${tab}date
blocks${tab}librispeech-continuous-test-clean${tab}26.6.2${tab}en-US${tab}20${tab}1.00${tab}5.00${tab}2.00${tab}500000000${tab}0.50${tab}${tab}1.30${tab}2.00${tab}0.10${tab}0${tab}20${tab}0${tab}2026-09-13T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null /dev/null "$OMCTEST_WORK/live.tsv")"
check "the record says the figure is a final, not a first partial" "final" \
    "$(pick_field "$picks" live accurate 13)"

section "A second corpus that picks another model is reported, not hidden"

write_models <<EOF
one${tab}One${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
two${tab}Two${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
one${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
two${tab}librispeech-test-clean${tab}26.6.2${tab}en-US${tab}2620${tab}1.40${tab}0.70${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "each corpus family gives its own answer" "2" \
    "$(printf '%s\n' "$picks" | /usr/bin/grep -c "^recordings	accurate")"
check "the second answer names its corpus" "librispeech-test-clean" \
    "$(printf '%s\n' "$picks" | /usr/bin/awk -F"$tab" '$1 == "recordings" && $2 == "accurate" { last = $9 } END { print last }')"

write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
one${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
one${tab}librispeech-test-clean${tab}26.6.2${tab}en-US${tab}2620${tab}1.40${tab}0.70${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the same winner twice is said once" "1" \
    "$(printf '%s\n' "$picks" | /usr/bin/grep -c "^recordings	accurate")"

section "Live is judged on continuous speech where there is any, and sentences are said to be that"

write_models <<EOF
one${tab}One${tab}en${tab}batch,live${tab}ggml${tab}installed${tab}1000000000
two${tab}Two${tab}en${tab}batch,live${tab}ggml${tab}installed${tab}1000000000
EOF
write_live <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}pace${tab}wer_pct${tab}cer_pct${tab}peak_memory_bytes${tab}load_seconds${tab}first_partial_median_s${tab}final_lag_median_s${tab}final_lag_worst_s${tab}finish_median_s${tab}trailing_words_lost${tab}rows_without_partials${tab}dropped_buffers${tab}date
one${tab}librispeech-continuous-test-clean${tab}26.6.2${tab}en-US${tab}20${tab}1.00${tab}3.00${tab}1.00${tab}1000000000${tab}0.50${tab}2.00${tab}1.00${tab}2.00${tab}0.10${tab}0${tab}0${tab}0${tab}2026-09-13T00:00:00Z
two${tab}en_us${tab}26.6.2${tab}en-US${tab}6${tab}1.00${tab}1.00${tab}0.50${tab}1000000000${tab}0.50${tab}1.00${tab}0.50${tab}1.00${tab}0.10${tab}0${tab}0${tab}0${tab}2026-09-13T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null /dev/null "$OMCTEST_WORK/live.tsv")"
check "the continuous cell decides, although the sentence cell scores better" "one" \
    "$(pick_field "$picks" live accurate 3)"
check "and the sentence row is not offered as an alternative" "" "$(pick_field "$picks" live fast 3)"

write_live <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}pace${tab}wer_pct${tab}cer_pct${tab}peak_memory_bytes${tab}load_seconds${tab}first_partial_median_s${tab}final_lag_median_s${tab}final_lag_worst_s${tab}finish_median_s${tab}trailing_words_lost${tab}rows_without_partials${tab}dropped_buffers${tab}date
two${tab}en_us${tab}26.6.2${tab}en-US${tab}6${tab}1.00${tab}1.00${tab}0.50${tab}1000000000${tab}0.50${tab}${tab}0.80${tab}1.00${tab}0.10${tab}0${tab}6${tab}0${tab}2026-09-13T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null /dev/null "$OMCTEST_WORK/live.tsv")"
check "sentences are used when they are all there is" "two" "$(pick_field "$picks" live accurate 3)"
check "a row with no partials is timed by its finals" "0.80" "$(pick_field "$picks" live accurate 7)"

section "A language nothing was measured in says so, and counts the models that claim it"

write_models <<EOF
one${tab}One${tab}uk${tab}batch${tab}ggml${tab}installed${tab}1000000000
two${tab}Two${tab}uk,en${tab}batch,live${tab}ggml${tab}installed${tab}1000000000
EOF
picks="$(suggest_awk uk "$OMCTEST_WORK/models.tsv" /dev/null /dev/null /dev/null)"
check "recordings report no measurement" "unmeasured" "$(pick_field "$picks" recordings none 3)"
check "with the number of models that list the language" "2" \
    "$(pick_field "$picks" recordings none 6)"
check "live reports its own count" "1" "$(pick_field "$picks" live none 6)"

write_models <<EOF
one${tab}One${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
EOF
picks="$(suggest_awk sw "$OMCTEST_WORK/models.tsv" /dev/null /dev/null /dev/null)"
check "a language no model claims is unsupported, not unmeasured" "unsupported" \
    "$(pick_field "$picks" recordings none 3)"

section "A model the catalog does not list is never suggested"

write_models <<EOF
one${tab}One${tab}en${tab}batch${tab}ggml${tab}installed${tab}1000000000
EOF
write_reference <<EOF
model${tab}corpus${tab}macos${tab}language${tab}rows${tab}wer_pct${tab}cer_pct${tab}rtfx${tab}peak_memory_bytes${tab}date
gone${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}1.00${tab}0.50${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
one${tab}en_us${tab}26.6.2${tab}en-US${tab}100${tab}4.00${tab}2.00${tab}10.0${tab}1000000000${tab}2026-09-08T00:00:00Z
EOF
picks="$(suggest_awk en "$OMCTEST_WORK/models.tsv" /dev/null "$OMCTEST_WORK/reference.tsv" /dev/null)"
check "the measured row nobody can select is skipped" "one" \
    "$(pick_field "$picks" recordings accurate 3)"

section "The box offers the measured languages, English first"

open_models_window
tick
check "the picker holds the languages something was measured in" "English
German
Polish" "$(ui_prop "$MODELS_BEST_LANG" options | /usr/bin/tr -d '"[]' | /usr/bin/tr ',' '\n')"
check "English is the one selected" "en" "$(/bin/cat "$(spool)/suggest/language.tag" 2>/dev/null)"
check "the box is shown" "1" "$(ui_visible "$MODELS_BEST_BOX")"

section "The lines name the picks, their figures and where they came from"

recordings_line="$(ui_value "$MODELS_BEST_RECORDINGS")"
live_line="$(ui_value "$MODELS_BEST_LIVE")"
check_contains "recordings name the most accurate English row" "Whisper large-v3-turbo" "$recordings_line"
check_contains "with its error rate" "4.00% word errors" "$recordings_line"
check_contains "and its speed" "12.0x real time" "$recordings_line"
check_contains "the faster row is named too" "Faster:" "$recordings_line"
check_contains "the label is bold, so the line reads as a label and an answer" "**Recordings:**" "$recordings_line"
check "no bracketed provenance is jammed into the line" "" \
    "$(printf '%s' "$recordings_line" | /usr/bin/grep -c '\[' | /usr/bin/sed 's/^0$//')"
check "the faster pick is on its own line" "1" \
    "$(printf '%s' "$recordings_line" | /usr/bin/grep -c '^\*\*Faster:\*\*')"
check_contains "the other corpus is reported as another answer" "On other recordings:" "$recordings_line"
check_contains "live names the row measured on continuous speech" "Nemotron" "$live_line"
check_contains "and when its text first appears" "first text after 0.91 s" "$live_line"

section "Choosing another language repaints the box and is remembered"

polish_position="$(/usr/bin/awk -F'\t' '$1 == "pl" { print NR; exit }' "$(spool)/suggest/languages.tsv")"
OMC_ACTIONUI_VIEW_1010_VALUE="$polish_position"
export OMC_ACTIONUI_VIEW_1010_VALUE
/bin/rm -f "$(spool)/suggest/picker_quiet"
omc_run speech.models.language.changed
check_status "the handler exits cleanly" 0
check "the box remembers the language" "pl" "$(/bin/cat "$(spool)/suggest/language.tag" 2>/dev/null)"
check "and the setting keeps it for the next window" "pl" \
    "$(/bin/cat "$SPEECH_APP_SUPPORT/Settings/models.best.language" 2>/dev/null)"
polish_line="$(ui_value "$MODELS_BEST_RECORDINGS")"
check_contains "the Polish pick is the smaller model half a point behind" "Parakeet v3" "$polish_line"
check_contains "and it says the download is still to come" "(not downloaded)" "$polish_line"
check_contains "Polish live is the row measured on Polish" "Parakeet v3" "$(ui_value "$MODELS_BEST_LIVE")"
check_contains "and it says its text arrives a sentence at a time" "whole sentences 0.50 s behind you" \
    "$(ui_value "$MODELS_BEST_LIVE")"

section "An echo from filling the picker changes nothing"

/bin/rm -f "$(spool)/suggest/language.tag"
models_call populate_suggest_languages "$(spool)" > /dev/null 2>&1
OMC_ACTIONUI_VIEW_1010_VALUE=99
export OMC_ACTIONUI_VIEW_1010_VALUE
omc_run speech.models.language.changed
check "a position no option has is ignored" "pl" \
    "$(/bin/cat "$SPEECH_APP_SUPPORT/Settings/models.best.language" 2>/dev/null)"

section "A language measured for recordings only says so on its live line"

german_position="$(/usr/bin/awk -F'\t' '$1 == "de" { print NR; exit }' "$(spool)/suggest/languages.tsv")"
OMC_ACTIONUI_VIEW_1010_VALUE="$german_position"
export OMC_ACTIONUI_VIEW_1010_VALUE
/bin/rm -f "$(spool)/suggest/picker_quiet"
omc_run speech.models.language.changed
check_contains "recordings name the one German row" "Apple long-form (built in) - 8.50% word errors" \
    "$(ui_value "$MODELS_BEST_RECORDINGS")"
check "live is unmeasured, and counts the models that list German" \
    "**Live:** not measured in German yet - 2 models list it." "$(ui_value "$MODELS_BEST_LIVE")"

section "A tick with nothing changed pushes no line"

open_models_window
tick
ui_reset
# A second later, so a signature that leaned on a clock (the modification time of /dev/null,
# which every write on the Mac advances) would differ.
/bin/sleep 1
tick
check "the recordings line was not pushed again" "" "$(ui_value "$MODELS_BEST_RECORDINGS")"
check "nor the live line" "" "$(ui_value "$MODELS_BEST_LIVE")"

check "no writes to undeclared view ids" "" "$(ui_unknown_writes)"
omctest_end
