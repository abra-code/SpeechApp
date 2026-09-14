# speech.service.file - "Transcribe with Speech" in the Services menu. macOS hands the selected
# files in OMC_OBJ_PATH, newline-separated; they get a window of their own, listed in its
# Recordings tab, through the same handoff as File > Open and a drop on the app. A selection with
# no file is ignored.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

files=""
while IFS= read -r path; do
    [ -n "$path" ] && [ -f "$path" ] || continue
    files="$files$path$NL"
done <<EOF
$OMC_OBJ_PATH
EOF
[ -n "$files" ] || exit 0

route_files "$files"

exit 0
