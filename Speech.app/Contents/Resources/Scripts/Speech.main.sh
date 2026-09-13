# Speech.main - the launch and drop dispatcher. OMC runs the main command on a bare launch
# (OMC_OBJ_PATH empty) and when recordings are dropped on the app or opened with it
# (OMC_OBJ_PATH = newline-separated paths). It opens no window itself: a recording gets a window
# of its own through the same handoff File > Open uses, and a bare launch gets an empty one.
# One recording at a time, so only the first path is used.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

first="$(printf '%s' "$OMC_OBJ_PATH" | /usr/bin/sed -n '1p')"

if [ -n "$first" ] && [ -f "$first" ]; then
    route_file "$first"
else
    "$next_command" "$OMC_CURRENT_COMMAND_GUID" "speech.new"
fi

exit 0
