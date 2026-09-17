# speech.suggest.jq - every transcriber row of `speech --json catalog`, as models.tsv for
# speech.suggest.awk: id <TAB> label <TAB> languages <TAB> modes <TAB> engine <TAB> state
# <TAB> size in bytes. Lists are comma-joined; a row that claims no language of its own gets "*".
#
# Unlike speech.catalog.jq, which answers "what can this window transcribe with right now", this
# one keeps rows that are not downloaded yet: the point of a suggestion is to name the model worth
# having, and its size is what the user is agreeing to. Rows whose engine is missing from this
# build, or which need a newer macOS than this Mac runs, are dropped - suggesting one would be
# advice nobody can take.

def clean: tostring | gsub("[\t\r\n]"; " ");
def list: if type == "array" and length > 0 then map(clean) | join(",") else "*" end;

.rows[]
| select(.role == "transcriber")
| select(.available == true)
| [ (.id | clean), (.label | clean), (.languages | list),
    ((.modes // []) | if length > 0 then map(clean) | join(",") else "-" end),
    ((.engine // "") | clean), ((.state // "") | clean),
    ((.size_bytes // 0) | clean) ]
| join("\t")
