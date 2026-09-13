# speech.drop - a file dropped on the Transcribe tab. The trigger context is ActionUI's drop
# payload, {"items":[...],"location":{...}}; an item is either a path or a file URL, so both are
# accepted. One recording at a time: the first item is used.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

spool="$(spool_dir_for "$window_uuid")"
[ -n "$window_uuid" ] && [ -d "$spool" ] || exit 0

item="$(printf '%s' "${OMC_ACTIONUI_TRIGGER_CONTEXT:-}" | "$jq" -r '.items[0] // empty' 2>/dev/null)"
[ -n "$item" ] || exit 0

case "$item" in
    file://*)
        # A file URL: drop the scheme and an optional localhost host, then decode %XX escapes.
        # Backslashes are doubled first so printf %b cannot read one in the name as an escape.
        path="${item#file://}"
        path="${path#localhost}"
        path="$(printf '%s' "$path" | /usr/bin/sed 's/\\/\\\\/g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
        path="$(printf '%b' "$path")"
        ;;
    *)
        path="$item"
        ;;
esac
[ -f "$path" ] || exit 0

run_is_active "$spool"
active=$?
if [ "$active" -eq 0 ]; then
    set_status "Stop the current transcription before dropping another recording."
    exit 0
fi

set_source "$spool" "$path"
refresh_actions "$spool"

exit 0
