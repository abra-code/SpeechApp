# speech.benchmark.corpus.changed - the Benchmark tab's Corpus picker changed (handle_corpus_changed
# in lib.speech.benchmark.sh).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
[ -f "$spool/benchmark/corpus.id" ] || exit 0
use_pane benchmark

handle_corpus_changed "$spool" "${OMC_ACTIONUI_VIEW_425_VALUE:-}"
refresh_benchmark_actions "$spool"

exit 0
