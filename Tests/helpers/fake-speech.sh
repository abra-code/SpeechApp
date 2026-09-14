#!/bin/bash
# fake-speech.sh - stands in for Contents/Support/speech under test (SPEECH_BIN). It records every
# invocation, then answers the verbs the applet uses from fixtures, so no model loads and no
# microphone opens.
#
#   FAKE_SPEECH_FIXTURES   directory holding catalog.json, transcribe.events.jsonl,
#                          transcribe.result.json (required)
#   FAKE_SPEECH_LOG        file each invocation's arguments are appended to, one line per call
#   FAKE_SPEECH_MODE       transcribe behavior: ok (default), fail (an error event, exit 1), or
#                          hang (one progress event, then wait to be signaled)
#   FAKE_SPEECH_FAIL_FILE  a recording that fails as in fail mode while every other one succeeds
#
# In hang mode the process replaces itself with sleep under its own name (exec -a), so its argv
# still starts with the SPEECH_BIN path. That is what the applet's argv check requires before it
# signals a pid, and a fake that failed the check would make every stop test pass vacuously.

log="${FAKE_SPEECH_LOG:-/dev/null}"
fixtures="${FAKE_SPEECH_FIXTURES:-}"
printf '%s\n' "$*" >> "$log"

if [ -z "$fixtures" ]; then
    printf 'fake-speech: FAKE_SPEECH_FIXTURES is not set\n' >&2
    exit 2
fi

[ "$1" = --json ] && shift
verb="$1"
shift

case "$verb" in
    catalog)
        /bin/cat "$fixtures/catalog.json"
        exit 0
        ;;
    transcribe)
        input="$1"
        output=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --output) output="$2"; shift ;;
            esac
            shift
        done
        mode="${FAKE_SPEECH_MODE:-ok}"
        [ -n "${FAKE_SPEECH_FAIL_FILE:-}" ] && [ "$input" = "$FAKE_SPEECH_FAIL_FILE" ] && mode=fail
        case "$mode" in
            fail)
                printf '%s\n' '{"code":"unsupported_format","message":"cannot decode the recording","t":0.01,"type":"error"}'
                printf 'speech transcribe: cannot decode the recording\n' >&2
                exit 1
                ;;
            hang)
                printf '%s\n' '{"audio_seconds_done":0,"audio_seconds_total":4.4,"fraction":0,"t":0.01,"type":"progress"}'
                exec -a "$0" /bin/sleep 600
                ;;
            *)
                /bin/cat "$fixtures/transcribe.events.jsonl"
                [ -n "$output" ] && /bin/cp "$fixtures/transcribe.result.json" "$output"
                exit 0
                ;;
        esac
        ;;
    stream)
        # A live session: one finished utterance and one still being spoken, then wait for stdin
        # to say stop - "q" on a line, or end of input. How it was told is written beside the log,
        # because the two stop paths are what the tests are about.
        printf '%s\n' '{"engine":"apple.transcriber","load_seconds":0.1,"model":"apple.transcriber","t":0.1,"type":"engine.ready"}'
        printf '%s\n' '{"end":1,"id":0,"start":0,"t":0.5,"text":"hello","type":"segment.partial"}'
        printf '%s\n' '{"end":1.5,"id":0,"start":0,"t":1.0,"text":"Hello world.","type":"segment.final","words":[{"end":0.6,"start":0,"text":"Hello"},{"end":1.5,"start":0.6,"text":"world."}]}'
        printf '%s\n' '{"end":2,"id":1,"start":1.6,"t":1.2,"text":"and more","type":"segment.partial"}'
        how="eof"
        while IFS= read -r line; do
            if [ "$line" = q ]; then
                how="q"
                break
            fi
        done
        printf '%s\n' '{"end":2.4,"id":1,"start":1.6,"t":2.0,"text":"And more.","type":"segment.final"}'
        printf '%s\n' '{"audio_seconds":2.4,"rtfx":1,"segments":2,"t":2.1,"type":"done","wall_seconds":2.4}'
        printf '%s\n' "$how" > "$log.stop"
        exit 0
        ;;
    export)
        input="$1"
        format=""
        output=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --format) format="$2"; shift ;;
                --output) output="$2"; shift ;;
            esac
            shift
        done
        if [ -z "$output" ]; then
            printf 'fake-speech: export without --output\n' >&2
            exit 2
        fi
        printf 'Transcript from %s as %s\n' "$input" "$format" > "$output"
        exit 0
        ;;
esac

printf 'fake-speech: unhandled verb %s\n' "$verb" >&2
exit 2
