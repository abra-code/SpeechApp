# speech.catalog.jq - the rows of `speech --json catalog` this window can transcribe with, as
# models.tsv: id <TAB> label <TAB> languages <TAB> modes <TAB> capabilities <TAB> engine, lists
# comma-joined.
#
# A row qualifies when the catalog calls it a transcriber, its engine is available in this build
# on this Mac, and its weights are usable now: installed, or managed by the OS (the Apple rows).
# A row that reports no language list of its own gets "*", as the catalog's TSV spells it.
# Tabs and line breaks inside a field would split a record, so they become spaces.

def clean: tostring | gsub("[\t\r\n]"; " ");
def list: if type == "array" and length > 0 then map(clean) | join(",") else "*" end;

.rows[]
| select(.role == "transcriber")
| select(.available == true)
| select(.state == "installed" or .state == "system_managed")
| [ (.id | clean), (.label | clean), (.languages | list), ((.modes // []) | if length > 0 then map(clean) | join(",") else "-" end), ((.capabilities // []) | if length > 0 then map(clean) | join(",") else "-" end), ((.engine // "") | clean) ]
| join("\t")
