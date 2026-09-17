# speech.benchmark.results.awk - the Benchmarks tab's results table for one corpus and sample size.
#
#   awk -F'\t' -v corpus=pl_pl -v sample=100 -v macos=26.6.2 \
#       -v mlx=<mark> -v ggml=<mark> -v fluid=<mark> \
#       -f speech.benchmark.results.awk role=labels labels.tsv role=results results.tsv \
#       role=reference measurements.tsv
#
# labels.tsv is id <TAB> label <TAB> engine from the catalog; results.tsv is this app's own
# measurements; measurements.tsv is the reference published with speech. Each file's role is named
# by the assignment before it rather than counted from where a file starts, because an empty file
# (no results yet, passed as /dev/null) has no first line to count. Prints one row per line,
# tab-separated: a sort key, then Model, WER, CER, Speed, Peak memory, Recordings, Measured, Note.
# The caller sorts on the key and drops it.
#
# Order: this app's measurements first, lowest word error rate first, then its failures, then the
# reference, lowest word error rate first. Of this app's measurements only the newest per model
# counts, so measuring a model again replaces its row. The reference is the full set of the corpus
# whichever sample size is chosen; the Recordings column shows how many recordings each row scored.
#
# Columns are found by their header names, not their positions, so a column speech adds to its
# measurements later moves nothing. Lines starting with # are comments; the reference's
# "machine:" comment names the Mac it was measured on.

function v(name) { return (name in col) ? $(col[name]) : "" }

function name_of(id,    mark) {
    if (!(id in label)) return id
    mark = ""
    if (engine[id] == "mlx") mark = mlx
    else if (engine[id] == "ggml") mark = ggml
    else if (engine[id] == "fluid") mark = fluid
    return mark == "" ? label[id] : label[id] " " mark
}

function pct(x) { return x == "" ? "-" : sprintf("%.2f%%", x) }
function speed(x) { return x == "" ? "-" : sprintf("%.1fx", x) }

function memory(bytes) {
    if (bytes == "" || bytes + 0 <= 0) return "-"
    if (bytes >= 1e9) return sprintf("%.1f GB", bytes / 1e9)
    return sprintf("%.0f MB", bytes / 1e6)
}

function recordings(rows, skipped) {
    if (rows == "") return "-"
    return skipped + 0 > 0 ? rows " (" skipped " skipped)" : rows
}

function when(mac, date) {
    return (mac == "" ? "" : ", macOS " mac) (date == "" ? "" : ", " substr(date, 1, 10))
}

# Apple's engines are part of macOS, so their accuracy moves with it.
function apple_note(id, mac) {
    if (id ~ /^apple\./ && macos != "" && mac != "" && mac != macos)
        return "Measured on macOS " mac ". Apple's engines change with macOS, and this Mac runs " macos "."
    return ""
}

function joined(a, b) { return a == "" ? b : (b == "" ? a : a " " b) }

function sort_key(group, wer, id) { return sprintf("%d%012.4f%s", group, wer == "" ? 0 : wer, id) }

FNR == 1 { split("", col); header = 0 }

role == "labels" { label[$1] = $2; engine[$1] = $3; next }

/^#/ {
    if (role == "reference" && refmachine == "" && $0 ~ /^#[ \t]*machine:/) {
        refmachine = $0
        sub(/^#[ \t]*machine:[ \t]*/, "", refmachine)
    }
    next
}

!header { for (i = 1; i <= NF; i++) col[$i] = i; header = 1; next }

role == "results" {
    if (v("corpus") != corpus || v("sample") != sample) next
    id = v("model")
    if (id == "") next
    date = v("date")
    if ((id in newest) && newest[id] > date) next
    newest[id] = date
    machine = v("machine")
    mac = v("macos")
    measured = (machine == "" ? "This Mac" : machine) when(mac, date)
    note = joined(v("note"), apple_note(id, mac))
    if (v("status") == "ok") {
        mine[id] = sort_key(1, v("wer_pct"), id) "\t" name_of(id) "\t" pct(v("wer_pct")) "\t" pct(v("cer_pct")) "\t" \
            speed(v("rtfx")) "\t" memory(v("peak_memory_bytes")) "\t" recordings(v("rows"), v("skipped")) "\t" measured "\t" note
    } else {
        mine[id] = sort_key(2, "", id) "\t" name_of(id) "\tFailed\t-\t-\t-\t-\t" measured "\t" note
    }
    next
}

role == "reference" {
    if (v("corpus") != corpus) next
    id = v("model")
    if (id == "") next
    mac = v("macos")
    print sort_key(3, v("wer_pct"), id) "\t" name_of(id) "\t" pct(v("wer_pct")) "\t" pct(v("cer_pct")) "\t" \
        speed(v("rtfx")) "\t" memory(v("peak_memory_bytes")) "\t" recordings(v("rows"), v("skipped")) "\t" \
        "Reference" (refmachine == "" ? "" : ", " refmachine) when(mac, v("date")) "\t" apple_note(id, mac)
}

END { for (id in mine) print mine[id] }
