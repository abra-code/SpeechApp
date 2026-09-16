# speech.benchmark.run - Run: start the benchmark worker (speech.benchmark.worker.sh), detached, to
# measure everything in the queue one after another. The tab shows its progress from the next tick
# of the window's poller.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
pane="$spool/benchmark"
[ -f "$pane/corpus.id" ] || exit 0
use_pane benchmark

count="$(queue_count)"
[ "${count:-0}" -gt 0 ] || exit 0

start_benchmark_worker
started=$?
/bin/rm -f "$pane/actions.sig"
refresh_benchmark_actions "$spool"
# Stays until the tab's state changes: the signature refresh_benchmark_actions wrote is left as is.
if [ "$started" -ne 0 ]; then
    set_status "Could not start measuring: Speech cannot write into $BENCHMARKS_DIR."
fi

exit 0
