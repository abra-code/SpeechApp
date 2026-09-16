# speech.recordings.copy - copy the selected recording's transcript, as shown in the window, to the
# clipboard; with Join on, the transcripts of every recording in the list, one after another.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

pane="$(pane_dir_for "$window_uuid" recordings)"
[ -n "$window_uuid" ] && [ -d "$pane" ] || exit 0
use_pane recordings

if [ "$(read_state "$pane/join")" = 1 ]; then
    if [ -f "$pane/batch" ]; then
        set_status "Join waits until the recordings are transcribed."
        exit 0
    fi
    joined="$pane/copy.$$.txt"
    : > "$joined"
    count=0
    while IFS= read -r item; do
        [ -n "$item" ] && [ -s "$item/transcript.txt" ] || continue
        /bin/cat "$item/transcript.txt" >> "$joined"
        count=$((count + 1))
    done <<ITEMS
$(joinable_items "$pane")
ITEMS
    if [ "$count" = 0 ]; then
        /bin/rm -f "$joined"
        exit 0
    fi
    "$pasteboard" general set "$(/bin/cat "$joined")"
    copy_status=$?
    /bin/rm -f "$joined"
    if [ "$copy_status" -ne 0 ]; then
        set_status "Could not copy the transcripts."
        exit 0
    fi
    what="$count transcripts"
    [ "$count" = 1 ] && what="1 transcript"
    set_status "Copied $what, joined.$(left_out_note "$pane" "$count")"
    exit 0
fi

selected="$(read_state "$pane/selected.key")"
[ -n "$selected" ] && [ -s "$pane/items/$selected/transcript.txt" ] || exit 0

"$pasteboard" general set "$(/bin/cat "$pane/items/$selected/transcript.txt")"
copy_status=$?
if [ "$copy_status" -ne 0 ]; then
    set_status "Could not copy the transcript."
    exit 0
fi
set_status "Copied the transcript."

exit 0
