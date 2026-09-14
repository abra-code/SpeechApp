# Speech.main - the launch and drop dispatcher. OMC runs the main command on a bare launch
# (OMC_OBJ_PATH empty) and when recordings are dropped on the app or opened with it
# (OMC_OBJ_PATH = newline-separated paths). It opens no window itself: recordings get a window of
# their own, listed in its Recordings tab, through the same handoff File > Open uses, and a bare
# launch gets an empty window.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

if [ -n "$OMC_OBJ_PATH" ]; then
    route_files "$OMC_OBJ_PATH"
else
    "$next_command" "$OMC_CURRENT_COMMAND_GUID" "speech.new"
fi

exit 0
