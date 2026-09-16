# speech.benchmark.queue.selected - the selection in the queue table changed. The table keeps each
# measurement's name in a hidden fourth column.
#
# Replacing the table's rows can report an empty selection that no one made; inside the quiet window
# after a programmatic update, an empty selection is taken for that echo and ignored.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
pane="$spool/benchmark"
[ -f "$pane/corpus.id" ] || exit 0
use_pane benchmark

name="${OMC_ACTIONUI_TABLE_470_COLUMN_4_VALUE:-}"
case "$name" in *[!0-9-]*) name="" ;; esac
[ -n "$name" ] && [ ! -f "$BENCHMARKS_DIR/queue/$name.cell" ] && name=""

if [ -z "$name" ]; then
    quiet_active "$pane" table
    quiet=$?
    [ "$quiet" -eq 0 ] && exit 0
    /bin/rm -f "$pane/queue.selected"
else
    write_state "$pane/queue.selected" "$name"
fi

refresh_benchmark_actions "$spool"

exit 0
