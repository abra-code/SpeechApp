# speech.recordings.join.changed - the Recordings tab's Join checkbox changed. While it is on,
# Export and Copy take the transcripts of every recording in the list as one. The choice is kept
# for the next window.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

case "${OMC_ACTIONUI_VIEW_156_VALUE:-}" in
    true|1) join=1 ;;
    *) join=0 ;;
esac
if [ "$join" = 1 ]; then
    write_state "$pane/join" 1
else
    /bin/rm -f "$pane/join"
fi
setting_set recordings.join "$join"

/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
