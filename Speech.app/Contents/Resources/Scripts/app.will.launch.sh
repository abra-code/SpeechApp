# app.will.launch - the app is starting, before any window opens. Removes the window spools a
# killed app left behind (sweep_sessions in lib.speech.sh). Command.json waits for it, so a window
# that opens next never has its fresh spool judged.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

sweep_sessions

exit 0
