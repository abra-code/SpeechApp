#!/bin/bash
# fake-speech.sh - stands in for Contents/Support/speech under test (SPEECH_BIN). It records every
# invocation, then answers the verbs the applet uses from fixtures, so no model loads and no
# microphone opens.
#
#   FAKE_SPEECH_FIXTURES   directory holding catalog.json, transcribe.events.jsonl,
#                          transcribe.result.json (required)
#   FAKE_SPEECH_LOG        file each invocation's arguments are appended to, one line per call
#   FAKE_SPEECH_MODE       transcribe behavior: ok (default), fail (an error event, exit 1),
#                          hang (one progress event, then wait to be signaled), or
#                          language_files (Apple's Italian files listed, then installing at 0%,
#                          then wait to be signaled - a download that does not move)
#   FAKE_SPEECH_FAIL_FILE  a recording that fails as in fail mode while every other one succeeds
#   FAKE_SPEECH_CATALOG    a writable copy of catalog.json to answer `catalog` from instead;
#                          `models download` and `models delete` then change the row's state in it
#   FAKE_SPEECH_DOWNLOAD   `models download` behavior: ok (default), fail (an error event, exit 1),
#                          or hang (one progress event, then wait to be signaled)
#   FAKE_SPEECH_DELETE     `models delete` behavior: ok (default) or fail (a message, exit 1)
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
        /bin/cat "${FAKE_SPEECH_CATALOG:-$fixtures/catalog.json}"
        exit 0
        ;;
    models)
        sub="$1"
        id="$2"
        catalog="${FAKE_SPEECH_CATALOG:-}"
        case "$sub" in
            download)
                case "${FAKE_SPEECH_DOWNLOAD:-ok}" in
                    fail)
                        printf '{"model":"%s","phase":"listing","t":0.01,"type":"model.progress"}\n' "$id"
                        printf '%s\n' '{"code":"runtime","message":"The network connection was lost.","t":0.02,"type":"error"}'
                        printf 'speech models download: The network connection was lost.\n' >&2
                        exit 1
                        ;;
                    hang)
                        printf '{"bytes_done":120000000,"bytes_total":480000000,"file":"model.bin","fraction":0.25,"model":"%s","phase":"downloading","t":0.1,"type":"model.progress"}\n' "$id"
                        exec -a "$0" /bin/sleep 600
                        ;;
                esac
                printf '{"model":"%s","phase":"listing","t":0.01,"type":"model.progress"}\n' "$id"
                printf '{"bytes_done":480000000,"bytes_total":480000000,"file":"model.bin","fraction":1,"model":"%s","phase":"downloading","t":0.2,"type":"model.progress"}\n' "$id"
                if [ -n "$catalog" ]; then
                    /usr/bin/jq --arg id "$id" '(.rows[] | select(.id == $id)) |= (.state = "installed" | .installed = true | .installed_bytes = (.size_bytes // 1000))' "$catalog" > "$catalog.tmp"
                    /bin/mv -f "$catalog.tmp" "$catalog"
                fi
                printf '{"bytes":1000,"model":"%s","path":"/nonexistent/Models/%s","t":0.3,"type":"model.installed"}\n' "$id" "$id"
                exit 0
                ;;
            delete)
                if [ "${FAKE_SPEECH_DELETE:-ok}" = fail ]; then
                    printf 'error: cannot remove the model files: permission denied\n' >&2
                    exit 1
                fi
                if [ -n "$catalog" ]; then
                    /usr/bin/jq --arg id "$id" '(.rows[] | select(.id == $id)) |= (.state = "missing" | .installed = false | del(.installed_bytes))' "$catalog" > "$catalog.tmp"
                    /bin/mv -f "$catalog.tmp" "$catalog"
                fi
                printf '{"model":"%s","path":"/nonexistent/Models/%s","state":"missing","t":0.01,"type":"model.entry"}\n' "$id" "$id"
                exit 0
                ;;
            status)
                printf '{"model":"%s","path":"/nonexistent/Models/%s","state":"installed","t":0.01,"type":"model.entry"}\n' "$id" "$id"
                exit 0
                ;;
        esac
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
            language_files)
                printf '%s\n' '{"file":"it_IT","model":"apple.dictation","phase":"listing","t":0.7,"type":"model.progress"}'
                printf '%s\n' '{"file":"it_IT","fraction":0,"model":"apple.dictation","phase":"installing","t":0.8,"type":"model.progress"}'
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
    record)
        # A new recording: started, one level, then wait for stdin to say stop - "q" on a line, or
        # end of input - and write the file, as `speech record` keeps what it captured. In
        # record_fail mode it fails before the microphone opens and writes nothing.
        output="$1"
        if [ "${FAKE_SPEECH_MODE:-ok}" = record_fail ]; then
            printf '%s\n' '{"code":"unavailable","message":"microphone access was refused.","t":0.01,"type":"error"}'
            printf 'speech record: microphone access was refused.\n' >&2
            exit 1
        fi
        printf '{"channels":1,"device":"Test Microphone","output":"%s","sample_rate":48000,"t":0.1,"type":"recording.started"}\n' "$output"
        printf '%s\n' '{"peak_db":-12,"rms_db":-30,"seconds":65.2,"t":0.3,"type":"recording.level"}'
        how="eof"
        while IFS= read -r line; do
            if [ "$line" = q ]; then
                how="q"
                break
            fi
        done
        printf 'RIFF recorded' > "$output"
        printf '{"audio_seconds":2,"output":"%s","segments":0,"t":2.1,"type":"done","wall_seconds":2.1}\n' "$output"
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
