# speech.models.show - an installed card's Show button. Selects the model's folder in the Finder.
# A folder that has left this Mac since the catalog was read says so rather than opening a Finder
# window on nothing; the next catalog read moves the card.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

[ -n "$window_uuid" ] || exit 0
spool="$(spool_dir_for "$window_uuid")"
row="$(card_row_of "${OMC_ACTIONUI_TRIGGER_VIEW_ID:-}")"
[ -n "$row" ] || exit 0
id="$(card_field "$spool" "$row" 1)"
[ -n "$id" ] || exit 0
state="$(card_field "$spool" "$row" 7)"
[ "$state" = installed ] || exit 0

label="$(card_field "$spool" "$row" 3)"
path="$(model_path "$id")"
if [ -z "$path" ] || [ ! -e "$path" ]; then
    set_models_status "The files of $label are not on this Mac."
    exit 0
fi

"$OPEN_BIN" -R "$path"

exit 0
