# speech.benchmark.summary.jq - one line of the benchmark results store, from the summary.json that
# `speech eval --report` writes.
#
#   jq -r --arg corpus pl_pl --arg sample 100 --arg version "speech 0.1.0" --arg note "" \
#       -f speech.benchmark.summary.jq summary.json
#
# The first 23 columns are those of speech's docs/benchmarks/measurements.tsv, rounded the same
# way, so one reader shows this Mac's results and the reference; then machine, speech_version,
# sample, status and note (RESULTS_COLUMNS in lib.speech.benchmark.sh). A field the summary does
# not carry is empty. Tabs and line breaks inside a field become spaces.

def clean: if . == null then "" else tostring | gsub("[\t\r\n]"; " ") end;
def places(n): if . == null then null else (. * pow(10; n) | round) / pow(10; n) end;

[ .model,
  $corpus,
  .os,
  .language,
  .resolved_locales,
  .rows,
  .skipped,
  (if .wer == null then null else (.wer * 100 | places(2)) end),
  (if .cer == null then null else (.cer * 100 | places(2)) end),
  (.rtfx | places(1)),
  (.audio_seconds | places(1)),
  (.wall_seconds | places(1)),
  (.load_seconds | places(2)),
  .peak_memory_bytes,
  .peak_footprint_bytes,
  .peak_neural_bytes,
  .reference_words,
  .reference_characters,
  .substitutions,
  .deletions,
  .insertions,
  .character_errors,
  .date,
  .machine,
  $version,
  $sample,
  "ok",
  $note
]
| map(clean)
| join("\t")
