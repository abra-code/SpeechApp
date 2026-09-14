# speech.stop - stop the live session. The run is marked as stopping first, so the poller, seeing
# the process gone without a result, reports a stop rather than a failure. What was transcribed
# so far stays in the window.
#
# A live session is asked, not signaled: Stop leaves a request for the stdin holder
# (speech.live.stdin.sh), which sends "q" and waits for speech to finalize its last utterance and
# report `done`. A signal sent after that would kill the session instead of letting it finish
# (speech's docs/live.md).

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" live)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane live

run="$(current_run_dir "$pane")"
[ -n "$run" ] || exit 0
[ "$(read_state "$run/state")" = running ] || exit 0

write_state "$run/state" stopping
: > "$run/stop.request"
set_status "Stopping..."
/bin/rm -f "$pane/actions.sig"
refresh_live_actions "$pane"

exit 0
