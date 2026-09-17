# speech.benchmark.model.changed - the Benchmarks tab's Model picker changed (handle_model_changed in
# lib.speech.sh; its last option opens the Models window, as in the other tabs).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
[ -f "$spool/benchmark/corpus.id" ] || exit 0
use_pane benchmark

handle_model_changed "$spool/benchmark" "${OMC_ACTIONUI_VIEW_427_VALUE:-}"
refresh_benchmark_actions "$spool"

exit 0
