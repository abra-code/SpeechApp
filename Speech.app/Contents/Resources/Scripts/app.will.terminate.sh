# app.will.terminate - the app is quitting. Stop every speech process and window poller this
# bundle started, each identified by its argv so an unrelated process that merely mentions the
# path is never signaled, then remove the per-window spools.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.sh"

# One process listing, matched literally. pgrep -f takes a regular expression, and a bundle
# path with a parenthesis in it ("Speech (1)/Speech.app") matched nothing, so nothing was stopped.
#
# A download's speech process is stopped like the rest; its worker then records the download as
# stopped and exits, and the bytes already on disk let the next download resume.
#
# So is the benchmark worker: it keeps the measurement in progress in the queue and ends, and the
# next Run measures it again.
/bin/ps -axo pid=,args= 2>/dev/null | while read -r pid args; do
    case "$args" in
        "$SPEECH_BIN"|"$SPEECH_BIN "*) /bin/kill -TERM "$pid" 2>/dev/null ;;
        "/bin/sh $BENCHMARK_WORKER_SCRIPT"|"/bin/sh $BENCHMARK_WORKER_SCRIPT "*) /bin/kill -TERM "$pid" 2>/dev/null ;;
        "/bin/sh $POLL_SCRIPT "*) /bin/kill -TERM "$pid" 2>/dev/null ;;
        "/bin/sh $MODELS_POLL_SCRIPT "*) /bin/kill -TERM "$pid" 2>/dev/null ;;
    esac
done

[ -d "$SESSIONS_DIR" ] && /bin/rm -rf "$SESSIONS_DIR"

exit 0
