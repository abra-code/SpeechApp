# speech.models.add.start - the Add button of the Add a Model sheet. Checks what was typed, starts
# the add worker (speech.add.worker.sh) detached, so the add goes on when the window closes, and
# closes the sheet. Each Models window's poller shows the add on its status line. What cannot be
# added is said on the sheet, which stays open.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.models.sh"

[ -n "$window_uuid" ] || exit 0

repo="$(repo_from_input "${OMC_ACTIONUI_VIEW_4110_VALUE:-}")"
if [ -z "$repo" ]; then
    set_add_error "Enter the model's Hugging Face repository as owner/name, or paste its address."
    exit 0
fi
quant="$(quant_from_input "${OMC_ACTIONUI_VIEW_4111_VALUE:-}")"
quant_status=$?
if [ "$quant_status" -ne 0 ]; then
    set_add_error "A quantization is letters, digits and underscores, such as Q4_K_M."
    exit 0
fi

/bin/mkdir -p "$APP_SUPPORT"
mkdir_status=$?
if [ "$mkdir_status" -ne 0 ]; then
    set_add_error "Could not create $APP_SUPPORT"
    exit 1
fi

# One add at a time: a second click, or Add in a second Models window, finds the lock or the
# running worker. The lock is held for a moment only, so one older than a minute was left by a
# handler that was killed, and would otherwise refuse every add from then on.
lock="$APP_SUPPORT/add.lock"
stale="$(/usr/bin/find "$lock" -maxdepth 0 -type d -mmin +1 2>/dev/null)"
[ -n "$stale" ] && /bin/rmdir "$lock" 2>/dev/null
/bin/mkdir "$lock" 2>/dev/null
lock_status=$?
if [ "$lock_status" -ne 0 ]; then
    set_add_error "Speech is starting another add. Try again in a moment."
    exit 0
fi
trap '/bin/rmdir "$lock" 2>/dev/null' EXIT
refusal="$(add_refusal)"
if [ -n "$refusal" ]; then
    set_add_error "$refusal"
    exit 0
fi

/bin/rm -rf "$ADDING_DIR"
/bin/mkdir -p "$ADDING_DIR"
mkdir_status=$?
if [ "$mkdir_status" -ne 0 ]; then
    set_add_error "Could not create $ADDING_DIR"
    exit 1
fi
write_state "$ADDING_DIR/repo" "$repo"
write_state "$ADDING_DIR/quant" "$quant"
write_state "$ADDING_DIR/token" "$(/bin/date +%s) $$"
write_state "$ADDING_DIR/state" running
/bin/sh "$ADD_WORKER_SCRIPT" "$repo" "$ADDING_DIR" < /dev/null > /dev/null 2>&1 &
write_state "$ADDING_DIR/worker.pid" "$!"

"$dialog" "$window_uuid" omc_window omc_dismiss_modal
set_models_status "Adding $repo..."
disable_ctrl "$MODELS_ADD_BTN"

exit 0
