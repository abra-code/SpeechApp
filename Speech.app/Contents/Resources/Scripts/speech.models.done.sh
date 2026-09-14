# speech.models.done - the Done button. Closes the Models window, which runs speech.models.cancel.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

"$dialog" "$window_uuid" omc_window omc_terminate_cancel

exit 0
