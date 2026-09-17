# speech.benchmark.reveal - Show: selects the tab's corpus folder in the Finder. A corpus
# that has left this Mac since the tab last looked says so rather than opening a Finder window on
# nothing; the next tick offers Download again.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
pane="$spool/benchmark"
[ -f "$pane/corpus.id" ] || exit 0
use_pane benchmark

corpus="$(read_state "$pane/corpus.id")"
corpus_is_present "$corpus"
present=$?
if [ "$present" -ne 0 ]; then
    set_status "$(corpus_title "$corpus") is not on this Mac."
    exit 0
fi

manifest="$(corpus_manifest "$corpus")"
"$OPEN_BIN" -R "${manifest%/*}"

exit 0
