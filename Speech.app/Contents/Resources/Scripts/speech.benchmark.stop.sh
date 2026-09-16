# speech.benchmark.stop - Stop: the measurement in progress is stopped and stays in the queue, with
# everything after it; nothing is recorded for it (stop_benchmark in lib.speech.benchmark.sh).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
pane="$spool/benchmark"
[ -f "$pane/corpus.id" ] || exit 0
use_pane benchmark

stop_benchmark
/bin/rm -f "$pane/actions.sig"
render_queue_table "$spool"
refresh_benchmark_actions "$spool"

exit 0
