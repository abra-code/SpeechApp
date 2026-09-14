# speech.drop - files dropped on the Recordings tab join its list. The trigger context is
# ActionUI's drop payload, {"items":[...],"location":{...}}; an item is either a path or a file
# URL, so both are accepted. Anything that is not a file is ignored.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

items="$(printf '%s' "${OMC_ACTIONUI_TRIGGER_CONTEXT:-}" | "$jq" -r '.items[]? | strings' 2>/dev/null)"
[ -n "$items" ] || exit 0

paths=""
while IFS= read -r item; do
    [ -n "$item" ] || continue
    paths="$paths$(path_from_drop_item "$item")$NL"
done <<EOF
$items
EOF

added="$(add_recordings "$pane" "$paths")"
[ "${added:-0}" -gt 0 ] || exit 0
render_recordings_table "$pane"
/bin/rm -f "$pane/actions.sig"
refresh_recordings_actions "$pane"

exit 0
