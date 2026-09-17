# speech.benchmark.sample.changed - the Benchmarks tab's sample size changed: a quick sample or the
# full set (handle_sample_changed in lib.speech.benchmark.sh).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
[ -f "$spool/benchmark/corpus.id" ] || exit 0
use_pane benchmark

handle_sample_changed "$spool" "${OMC_ACTIONUI_VIEW_426_VALUE:-}"
refresh_benchmark_actions "$spool"

exit 0
