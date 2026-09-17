# speech.benchmark.worker.sh - measures what waits in the benchmark queue, one measurement at a
# time, for as long as that takes. Not an OMC command: speech.benchmark.run starts it with /bin/sh,
# detached, so measuring goes on when the window that pressed Run closes. One worker serves the whole
# app, and every window's Benchmarks tab shows its progress.
#
# Each measurement is `speech eval` over a corpus's manifest (measure_cell in
# lib.speech.benchmark.sh). A finished or failed one is written to results.tsv and leaves the queue;
# a stopped one stays, and the next Run measures it from the start. The worker ends when the queue is
# empty, when Stop asks it to, or when the app that started it is gone.
#
# When Speech quits, app.will.terminate signals this worker and its speech process; the measurement
# in progress stays in the queue.

. "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.speech.benchmark.sh"

[ -d "$WORKER_DIR" ] || exit 0

BENCH_APP_PID="${OMC_APP_PROCESS_ID:-}"
BENCH_STOP=0
BENCH_SPEECH_PID=""
# A signal to the worker is passed on to speech, and the measurement counts as stopped.
trap 'BENCH_STOP=1; [ -n "$BENCH_SPEECH_PID" ] && signal_speech_pid "$BENCH_SPEECH_PID" TERM' TERM INT HUP

# Recorded with every result: a measurement belongs to the speech that took it.
speech_version="$("$SPEECH_BIN" --version 2>/dev/null)"

while [ "$BENCH_STOP" = 0 ]; do
    [ -f "$WORKER_DIR/stop.request" ] && break
    if [ -n "$BENCH_APP_PID" ]; then
        pid_alive "$BENCH_APP_PID"
        app_status=$?
        [ "$app_status" -eq 0 ] || break
    fi
    cell="$(queued_cells | /usr/bin/head -1)"
    [ -n "$cell" ] || break
    measure_cell "$cell" "$speech_version"
    measured=$?
    [ "$measured" -eq 2 ] && break
done

/bin/rm -f "$WORKER_DIR/state" "$WORKER_DIR/cell" "$WORKER_DIR/speech.pid" "$WORKER_DIR/stop.request" "$WORKER_DIR/worker.pid"

exit 0
