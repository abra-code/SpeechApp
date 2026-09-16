# speech.benchmark.progress.jq - how far a measurement has got, from the `speech --json eval` events
# written so far. Read with -R -n, so the line speech is still in the middle of writing is skipped
# rather than failing the whole read.
#
#   jq -R -r -n --arg us "<unit separator>" -f speech.benchmark.progress.jq events.jsonl
#
# Prints one record: rows US wer US phase US percent US file.
#
# rows is how many recordings have been scored, and wer the word error rate over them so far, as a
# percentage with one decimal: each recording's rate weighted by its reference's word count, which is
# speech's corpus rate as long as its scorer counts words the way whitespace does - close enough for a
# progress line, and the result that is recorded is speech's own. Before the first recording, phase,
# percent and file come from the last model.progress event.

[inputs | fromjson? | select(type == "object")] as $events
| [$events[] | select(.type == "eval.row")] as $rows
| if ($rows | length) > 0 then
    [$rows[] | {words: ((.reference // "") | tostring | split(" ") | map(select(length > 0)) | length), wer: (.wer // 0)}] as $scored
    | ([$scored[] | .words] | add) as $words
    | ([$scored[] | .words * .wer] | add) as $edits
    | [($rows | length), (if $words > 0 then (($edits / $words * 1000) | round) / 10 else 0 end), "", "", ""]
  else
    ([$events[] | select(.type == "model.progress")] | last) as $progress
    | [0, "", ($progress.phase // ""), (if $progress.fraction == null then "" else ($progress.fraction * 100 | floor) end), ($progress.file // "")]
  end
| map(tostring)
| join($us)
