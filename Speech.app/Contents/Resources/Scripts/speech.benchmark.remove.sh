# speech.benchmark.remove - take the selected measurement out of the queue. Not the one being
# measured: Stop it first.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
pane="$spool/benchmark"
[ -f "$pane/corpus.id" ] || exit 0
use_pane benchmark

name="$(read_state "$pane/queue.selected")"
[ -n "$name" ] || exit 0

remove_cell "$name"
removed=$?
if [ "$removed" -ne 0 ]; then
    set_status "That measurement is in progress. Stop it before removing it from the queue."
    exit 0
fi

/bin/rm -f "$pane/queue.selected" "$pane/actions.sig"
render_queue_table "$spool"
"$dialog" "$window_uuid" "$BENCH_QUEUE_TABLE" omc_deselect
refresh_benchmark_actions "$spool"

exit 0
