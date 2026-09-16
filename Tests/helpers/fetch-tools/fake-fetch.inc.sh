# fake-fetch.inc.sh - the body of the fake fetch tools in this directory, which stand in for speech's
# tools/fetch-fleurs.sh and tools/fetch-librispeech.sh under test (SPEECH_FETCH_TOOLS_DIR). Sourced,
# not executed, so the process keeps the argv "/bin/sh <tools dir>/<tool> <argument>" that the
# applet's argv check requires before it signals a tool.
#
#   FAKE_FETCH_LOG     file each invocation is appended to: tool, argument and SPEECH_CORPUS_DIR
#   FAKE_FETCH_MODE    ok (default; a partial archive, then the manifest where the real tool writes
#                      it), fail (curl could not reach the server: the real tool's two message lines,
#                      exit 1), empty (exit 0 and no manifest), or hang (a partial archive of
#                      FAKE_FETCH_BYTES, then wait in a child sleep whose pid goes to
#                      $SPEECH_CORPUS_DIR/fake-fetch.child, as the real tool waits in curl)
#   FAKE_FETCH_BYTES   the partial archive's size in hang mode (default 1000000)
#
# The layouts match the real tools: fleurs/<lang>/test.tar.gz and fleurs/<lang>/manifest.tsv;
# LibriSpeech/<split>.tar.gz and LibriSpeech/<split>/manifest.tsv.

fake_tool="${0##*/}"
fake_argument="$1"
printf '%s %s %s\n' "$fake_tool" "$fake_argument" "${SPEECH_CORPUS_DIR:-}" >> "${FAKE_FETCH_LOG:-/dev/null}"

case "$fake_tool" in
    fetch-fleurs.sh)
        fake_dest="$SPEECH_CORPUS_DIR/fleurs/$fake_argument"
        fake_archive="$fake_dest/test.tar.gz"
        ;;
    *)
        fake_dest="$SPEECH_CORPUS_DIR/LibriSpeech/$fake_argument"
        fake_archive="$SPEECH_CORPUS_DIR/LibriSpeech/$fake_argument.tar.gz"
        ;;
esac
/bin/mkdir -p "${fake_archive%/*}"

case "${FAKE_FETCH_MODE:-ok}" in
    fail)
        echo "== $fake_argument -> $fake_dest"
        printf '  %% Total    %% Received\r  0     0    0     0\n' >&2
        echo "-- could not download the audio for $fake_argument (curl 6)" >&2
        echo "   re-run to resume the partial download, or delete $fake_archive to start over" >&2
        echo "" >&2
        echo "1 of 1 language(s) failed; see the messages above." >&2
        exit 1
        ;;
    empty)
        exit 0
        ;;
    hang)
        # A sparse file: its size is what the applet reads, and nothing is written to the disk.
        /bin/dd if=/dev/zero of="$fake_archive" bs="${FAKE_FETCH_BYTES:-1000000}" count=0 seek=1 2>/dev/null
        /bin/sleep 600 &
        printf '%s' "$!" > "$SPEECH_CORPUS_DIR/fake-fetch.child"
        wait
        exit 0
        ;;
esac

/bin/dd if=/dev/zero of="$fake_archive" bs=1000 count=1 2>/dev/null
/bin/mkdir -p "$fake_dest"
printf '%s/a.wav\tone\ten-US\n%s/b.wav\ttwo\ten-US\n' "$fake_dest" "$fake_dest" > "$fake_dest/manifest.tsv"
/bin/rm -f "$fake_archive"
exit 0
