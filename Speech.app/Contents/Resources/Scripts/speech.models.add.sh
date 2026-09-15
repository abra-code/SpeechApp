# speech.models.add - Add Model... in the Models window. Presents the Add a Model sheet
# (speech.model.add.json). The sheet's views join the window's pool when it is presented, so it
# can say at once that another add is still running.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

[ -n "$window_uuid" ] || exit 0
"$dialog" "$window_uuid" omc_window omc_present_modal "speech.model.add"
set_add_error "$(add_refusal)"

exit 0
