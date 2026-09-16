# speech.benchmark.download.confirm - the Download button of the download alert. Starts the download
# worker for the corpus named in pending.download (speech.corpus.download.worker.sh), detached, after
# checking again that it did not arrive or start downloading while the alert was open. The tab shows
# the progress from the next tick of the window's poller.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
pane="$spool/benchmark"
[ -f "$pane/corpus.id" ] || exit 0
use_pane benchmark

corpus="$(read_state "$pane/pending.download")"
/bin/rm -f "$pane/pending.download"
[ -n "$corpus" ] || exit 0
[ -n "$(corpus_title "$corpus")" ] || exit 0

refusal="$(corpus_download_refusal "$corpus" "$(corpora_free_bytes)")"
if [ -n "$refusal" ]; then
    set_status "$refusal"
    exit 0
fi

start_corpus_download "$corpus"
started=$?
/bin/rm -f "$pane/corpora.sig" "$pane/actions.sig"
poll_benchmark "$spool"
# Stays until the tab's state changes: the signature refresh_benchmark_actions wrote is left as is.
if [ "$started" -ne 0 ]; then
    set_status "Could not start the download: Speech cannot write into $CORPUS_DOWNLOADS_DIR."
fi

exit 0
