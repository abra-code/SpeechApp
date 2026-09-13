# speech.service.file - "Transcribe with Speech" in the Services menu. macOS hands the selected
# files in OMC_OBJ_PATH, newline-separated; the first one gets a window of its own through the
# same handoff as File > Open and a drop on the app. A selection with no file is ignored.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

first="$(printf '%s' "$OMC_OBJ_PATH" | /usr/bin/sed -n '1p')"
[ -n "$first" ] && [ -f "$first" ] || exit 0

route_file "$first"

exit 0
