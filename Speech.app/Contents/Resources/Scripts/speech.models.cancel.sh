# speech.models.cancel - the Models window closed. Removing its spool ends its poller. Downloads
# go on: each has a worker of its own, and a Models window opened later shows their progress.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

# Without a window uuid the spool path would be the Sessions directory itself.
[ -n "$window_uuid" ] || exit 0
/bin/rm -rf "$(spool_dir_for "$window_uuid")"

exit 0
