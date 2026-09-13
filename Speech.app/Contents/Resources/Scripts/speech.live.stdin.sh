# speech.live.stdin.sh - holds a live session's stdin, and ends it. Not an OMC command:
# spawn_stream (lib.speech.sh) starts it beside `speech stream`.
#   args: <run_dir> <speech_pid> [app_pid]
#
# speech stream stops tidily on "q" and Return, or at end of input (speech's docs/live.md). Its
# stdin is the FIFO <run_dir>/stdin.fifo and this process is the only writer, so it decides:
#   - Stop writes <run_dir>/stop.request: this process sends "q" once and keeps the FIFO open
#     until speech exits, so the tidy stop is the only stop it receives.
#   - The window closes (the run directory disappears) or the app is gone: this process exits,
#     the FIFO reaches end of input, and speech stops on its own. A SIGKILLed app therefore does
#     not leave the microphone open.
#   - speech is still running 30 seconds after "q": it is signaled once with TERM, after the argv
#     check. speech treats a stop after a tidy stop as fatal, which is what giving up should be.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

run="$1"
speech_pid="$2"
app_pid="${3:-}"
[ -d "$run" ] || exit 0
case "$speech_pid" in ''|*[!0-9]*) exit 0 ;; esac

# Opening the write end waits for speech's read end, which its shell opens before it becomes
# speech, so neither side can run ahead of the other.
exec 3> "$run/stdin.fifo"

sent_at=""
signaled=0
while :; do
    [ -d "$run" ] || break
    if [ -n "$app_pid" ]; then
        pid_alive "$app_pid"
        app_status=$?
        [ "$app_status" -eq 0 ] || break
    fi
    pid_alive "$speech_pid"
    speech_status=$?
    [ "$speech_status" -eq 0 ] || break

    if [ -f "$run/stop.request" ] && [ -z "$sent_at" ]; then
        printf 'q\n' >&3
        sent_at="$(/bin/date +%s)"
    fi
    if [ -n "$sent_at" ] && [ "$signaled" = 0 ]; then
        now="$(/bin/date +%s)"
        if [ "$((now - sent_at))" -ge 30 ]; then
            signal_speech_pid "$speech_pid" TERM
            signaled=1
        fi
    fi
    /bin/sleep 0.5
done

exec 3>&-
exit 0
