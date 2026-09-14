# speech.models.poll.sh - the Models window's poller, one per open Models window. Not an OMC
# command: speech.models.init starts it with /bin/sh, and it runs until the window's spool
# directory disappears (window closed, app quit) or the app itself is gone.
#   args: <window_uuid> <spool_dir>
#
# Each tick it reads the catalog again when models.changed says a model was downloaded or deleted
# (and on its first tick), rebuilds the cards when what they show changed, and puts each
# download's progress on its card (poll_models_window in lib.speech.models.sh). It is the only
# code that inserts or removes cards: handlers change one card's text and buttons, so two writers
# can never leave duplicate cards behind.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

window_uuid="$1"
spool="$2"
[ -n "$window_uuid" ] && [ -d "$spool" ] || exit 0
app_pid="${OMC_APP_PROCESS_ID:-}"

while [ -d "$spool" ]; do
    if [ -n "$app_pid" ]; then
        pid_alive "$app_pid"
        app_status=$?
        [ "$app_status" -eq 0 ] || break
    fi
    poll_models_window "$spool"
    /bin/sleep 1
done

exit 0
