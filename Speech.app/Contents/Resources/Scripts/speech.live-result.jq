# speech.live-result.jq - a live session's transcript in the shape `speech transcribe --format
# json` writes ({model, language, segments}), so Export converts it with `speech export` like any
# other transcript. `speech stream` has no --output of its own.
#
# Input: every event of the session, slurped (jq -s). $model and $language are the run's.
# A segment's last final or refined event wins; partial events are drafts and are left out.
# A refined segment carries no word timings (speech drops them, since they describe the draft's
# words), so words are kept only where the event has them.

{
  model: $model,
  language: $language,
  segments: (
    map(select(.type == "segment.final" or .type == "segment.refined"))
    | group_by(.id)
    | map(last | {id, start, end, text} + (if .words then {words} else {} end))
  )
}
