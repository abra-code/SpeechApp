# speech.benchmark.download - Download: asks before downloading the tab's corpus, with its sizes and
# license; the alert's Download button runs speech.benchmark.download.confirm. Alert buttons carry no
# context of their own, so the corpus asked about waits in the pane's pending.download.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
pane="$spool/benchmark"
[ -f "$pane/corpus.id" ] || exit 0
use_pane benchmark

corpus="$(read_state "$pane/corpus.id")"
[ -n "$(corpus_title "$corpus")" ] || exit 0

refusal="$(corpus_download_refusal "$corpus" "$(corpora_free_bytes)")"
if [ -n "$refusal" ]; then
    set_status "$refusal"
    exit 0
fi

write_state "$pane/pending.download" "$corpus"
"$dialog" "$window_uuid" omc_window omc_present_alert "Download $(corpus_title "$corpus")?" "$(corpus_download_question "$corpus")" \
    "Cancel:cancel:" "Download::speech.benchmark.download.confirm"

exit 0
