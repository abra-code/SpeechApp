# speech.join.jq - join the JSON transcripts of several recordings into one, timed as if the
# recordings were played one after another, so subtitles made from it fit the recordings joined
# into one file. Read with -s from build_joined_result in lib.speech.sh:
#
#   {"seconds": <the recording's length, or null>, "doc": <what speech transcribe --format json wrote>}
#
# one per recording, in list order. Each recording's segments and words move later by the lengths
# of the recordings before it. A length speech did not report falls back to where the recording's
# last segment ends, which loses only the silence after it. Segment ids are numbered again from 0,
# since `speech export` expects them to increase through the document. The model is every model
# that took part; the language is kept only when all the recordings share it.

def later($by):
  .start += $by
  | .end += $by
  | if .words == null then . else .words |= map(.start += $by | .end += $by) end;

. as $parts
| (reduce $parts[] as $part ({offset: 0, segments: []};
    .offset as $offset
    | .segments += ($part.doc.segments // [] | map(later($offset)))
    | .offset += ($part.seconds // ($part.doc.segments // [] | last | .end) // 0)))
| .segments
| to_entries
| map(.value + {id: .key}) as $segments
| ([$parts[].doc.language] | unique) as $languages
| {model: ([$parts[].doc.model | select(. != null)] | unique | join(", ")), segments: $segments}
| if ($languages | length) == 1 and $languages[0] != null then .language = $languages[0] else . end
