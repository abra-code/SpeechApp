# speech.benchmark.add - Add to Queue: the tab's model, corpus and sample size join the benchmark
# queue, which every window shares. A running worker takes it when it reaches it; otherwise Run
# starts measuring.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
pane="$spool/benchmark"
[ -f "$pane/corpus.id" ] || exit 0
use_pane benchmark

corpus="$(read_state "$pane/corpus.id")"
model="$(read_state "$pane/model.id")"
sample="$(read_state "$pane/sample")"
[ -n "$model" ] || exit 0

corpus_is_present "$corpus"
present=$?
if [ "$present" -ne 0 ]; then
    set_status "$(corpus_title "$corpus") is not on this Mac yet, so there is nothing to measure with. Press Download to get it."
    exit 0
fi

add_cell "$model" "$corpus" "$sample"
added=$?
render_queue_table "$spool"
/bin/rm -f "$pane/actions.sig"
refresh_benchmark_actions "$spool"
# A message over the status line stays until the tab's state changes, since refresh_benchmark_actions
# writes the line again only when its signature moves.
if [ "$added" -eq 1 ]; then
    set_status "$(benchmark_model_label "$spool" "$model" plain) on $(corpus_title "$corpus"), $(sample_name "$sample"), is already waiting in the queue."
elif [ "$added" -ne 0 ]; then
    set_status "Could not add to the queue in $BENCHMARKS_DIR."
fi

exit 0
