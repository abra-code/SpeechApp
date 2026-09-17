# speech.suggest.awk - two model suggestions for one language, from measurements only.
#
#   awk -F'\t' -v language=pl -v mlx=<mark> -v ggml=<mark> -v fluid=<mark> \
#       -f speech.suggest.awk \
#       role=models models.tsv role=results results.tsv \
#       role=reference measurements.tsv role=live live-measurements.tsv
#
# models.tsv is every transcriber row of the catalog (speech.suggest.jq): id, label, languages,
# modes, engine, state, size. results.tsv is what this Mac measured, measurements.tsv and
# live-measurements.tsv what speech published. Each file's role is named by the assignment before
# it, the way speech.benchmark.results.awk does it, so an empty file passed as /dev/null needs no
# first line.
#
# Prints one record per suggestion, tab-separated:
#
#   mode <TAB> kind <TAB> id <TAB> name <TAB> metric <TAB> figure <TAB> second <TAB> rows
#     <TAB> corpus <TAB> source <TAB> state <TAB> size <TAB> wait
#
# mode is recordings or live; kind is accurate, fast or none; metric is wer or cer; figure is the
# error rate as a percentage; second is throughput ("46.1x") for recordings and the wait for text
# ("1.25 s") for live; wait says which wait that is, "partial" for a row that shows text as it
# speaks and "final" for one whose text only arrives a sentence at a time; source is this-mac or
# reference; state is the catalog's install state.
# A "none" record carries a reason in place of the id: unmeasured (no cell for this language) or
# unsupported (no model claims it), with the number of rows that claim it in the figure field.
#
# Two rules that are not obvious and are the reason this is a program rather than a sort:
#
#  - **The metric depends on the language.** Chinese, Japanese, Cantonese, Thai, Khmer, Lao,
#    Burmese and Tibetan write no spaces between words, so a whitespace word error rate there is
#    near 100% for every model and says nothing; the character error rate is the comparable
#    figure. Mandarin's best row is 99.76% WER and 7.19% CER, from the same cell.
#  - **A corpus is part of a figure.** Two corpora of one language can rank models differently
#    (Granite Speech NAR is first on LibriSpeech test-clean and around twentieth on FLEURS
#    English), so a pick is made inside one corpus and a second corpus is printed when it
#    disagrees. Never across two corpora: test-clean and test-other are different recordings, and
#    the lower of their two numbers is not the better model.
#
# This Mac's own measurement always beats the published one for the same model and corpus, which
# is what the Benchmarks tab is for. Nothing here ranks a model that was never measured in the
# language asked about: an unmeasured row is reported as unmeasured, never guessed at.

BEGIN {
    FS = "\t"
    # Languages whose orthography puts no space between words. Same set as speech's
    # tools/battery-report.py; see the rule above.
    split("zh cmn yue ja th km lo my bo", unspaced_list, " ")
    for (i in unspaced_list) unspaced[unspaced_list[i]] = 1
    metric = (language in unspaced) ? "cer" : "wer"
    # A faster row is only worth naming when it is clearly faster, and an alternative is only
    # worth naming when its accuracy is close.
    close_factor = 1.5
    faster_factor = 1.5
    quicker_seconds = 0.5
    # Two rows this close are not distinguishable on these corpora (the plan's curation rule), so
    # a much smaller model may take the pick; it has to be at least this much smaller to count.
    #
    # Close is both absolute and relative, and the relative part is what makes it honest. Half a
    # point is nothing at 9% and a great deal at 1.4%: on LibriSpeech, 1.41% against 1.75% is a
    # quarter more errors, and naming the smaller row there would be wrong however small it is.
    tie_points = 0.5
    tie_share = 1.10
    smaller_share = 0.7
}

function v(name) { return (name in col) ? $(col[name]) : "" }

# The language tag's base: "pl-PL" and "pl" both answer "pl".
function base(tag,    cut) {
    cut = index(tag, "-")
    return cut > 0 ? substr(tag, 1, cut - 1) : tag
}

function name_of(id,    mark) {
    if (!(id in label)) return id
    mark = ""
    if (engine[id] == "mlx") mark = mlx
    else if (engine[id] == "ggml") mark = ggml
    else if (engine[id] == "fluid") mark = fluid
    return mark == "" ? label[id] : label[id] " " mark
}

# A pick is made inside one corpus, never across two: LibriSpeech test-clean and test-other are
# different recordings of the same language, and the lower of their two numbers is not the better
# model. This only decides which corpus the box answers with first - the language's own FLEURS
# split, then the rest by name. A corpus this program does not know ranks with FLEURS.
function corpus_rank(corpus) {
    return (corpus ~ /^librispeech/) ? 2 : 1
}

function claims_language(id,    i, n, tags, tag) {
    if (!(id in languages)) return 0
    if (languages[id] == "*") return 1
    n = split(languages[id], tags, ",")
    for (i = 1; i <= n; i++) {
        tag = tags[i]
        sub(/^ +/, "", tag)
        if (base(tag) == language) return 1
    }
    return 0
}

function has_mode(id, wanted,    i, n, modes_list) {
    if (!(id in modes)) return 0
    n = split(modes[id], modes_list, ",")
    for (i = 1; i <= n; i++) if (modes_list[i] == wanted) return 1
    return 0
}

# One measured cell, kept only when it is the best evidence for that model, corpus and mode:
# this Mac beats the reference, and a newer cell of the same origin beats an older one.
function remember(mode, id, corpus, error, second, rows, source, date, wait,    key) {
    key = mode "|" id "|" corpus
    if (key in cell_rank) {
        if (source == "reference" && cell_source[key] == "this-mac") return
        if (source == cell_source[key] && date <= cell_date[key]) return
    }
    cell_rank[key] = 1
    cell_mode[key] = mode
    cell_id[key] = id
    cell_corpus[key] = corpus
    cell_error[key] = error
    cell_second[key] = second
    cell_rows[key] = rows
    cell_source[key] = source
    cell_date[key] = date
    cell_wait[key] = wait
    keys[key] = 1
}

role == "models" {
    label[$1] = $2
    languages[$1] = $3
    modes[$1] = $4
    engine[$1] = $5
    state[$1] = $6
    size[$1] = $7
    next
}

/^#/ { next }

# Every published or measured file names its columns in a header line.
$1 == "model" {
    for (i = 1; i <= NF; i++) col[$i] = i
    next
}

role == "results" {
    if (v("status") != "ok") next
    if (base(v("language")) != language) next
    remember("recordings", $1, v("corpus"), v(metric "_pct"), v("rtfx"), v("rows"),
             "this-mac", v("date"), "")
    next
}

role == "reference" {
    if (base(v("language")) != language) next
    remember("recordings", $1, v("corpus"), v(metric "_pct"), v("rtfx"), v("rows"),
             "reference", v("date"), "")
    next
}

role == "live" {
    if (base(v("language")) != language) next
    # How soon text appears: the first partial where the row emits partials, and how far its
    # finals run behind the speaker where it does not.
    wait = v("first_partial_median_s")
    wait_kind = "partial"
    if (wait == "") {
        wait = v("final_lag_median_s")
        wait_kind = "final"
    }
    remember("live", $1, v("corpus"), v(metric "_pct"), wait, v("rows"), "reference", v("date"),
             wait_kind)
    next
}

# --- the picks -------------------------------------------------------------

function record(mode, kind, key) {
    named[mode SUBSEP cell_id[key]] = 1
    print mode "\t" kind "\t" cell_id[key] "\t" name_of(cell_id[key]) "\t" metric "\t" \
        cell_error[key] "\t" cell_second[key] "\t" cell_rows[key] "\t" cell_corpus[key] "\t" \
        cell_source[key] "\t" state[cell_id[key]] "\t" size[cell_id[key]] "\t" cell_wait[key]
}

function none(mode, reason, claimed) {
    print mode "\tnone\t" reason "\t\t" metric "\t" claimed "\t\t\t\t\t\t\t"
}

# The cells of one mode that a suggestion may rest on: the model has to be in the catalog, claim
# the language and do this mode. A cell for a model the catalog no longer lists is ignored rather
# than shown as a name nobody can select.
function usable(mode, key,    id) {
    if (cell_mode[key] != mode) return 0
    id = cell_id[key]
    if (!(id in label)) return 0
    if (!claims_language(id)) return 0
    if (!has_mode(id, mode == "live" ? "live" : "batch")) return 0
    # A missing figure is "" or a placeholder such as "-"; either would compare as 0 and win.
    if (cell_error[key] !~ /^[0-9]+(\.[0-9]+)?$/) return 0
    return 1
}

# Live is measured on continuous speech where that exists, because a row that loses the tail of
# long speech only shows it there; single sentences are used when they are all there is.
function live_family(    key, found) {
    found = ""
    for (key in keys) {
        if (!usable("live", key)) continue
        if (cell_corpus[key] ~ /continuous/) found = "continuous"
    }
    return found
}

# Whether one cell may be compared inside one pick: the right mode, the right corpus family, and
# the right kind of corpus for live.
function eligible(mode, key, corpus, want_continuous) {
    if (!usable(mode, key)) return 0
    if (corpus != "" && cell_corpus[key] != corpus) return 0
    if (want_continuous == "continuous" && cell_corpus[key] !~ /continuous/) return 0
    if (want_continuous == "sentences" && cell_corpus[key] ~ /continuous/) return 0
    return 1
}

# The pick for one corpus family: the lowest error rate, and then a clearly smaller model whose
# error rate is within `tie_points` of it.
#
# Two passes, because one pass cannot do this. Comparing each row against the current winner lets
# the winner drift: a row 0.3 points worse and slightly smaller replaces it, then a row 0.3 points
# worse than THAT replaces it again, and the pick walks away from the best figure a third of a
# point at a time. Both passes here compare against the best error rate in the family, so the
# answer does not depend on the order the rows arrive in.
#
# "Clearly smaller" is a share rather than any difference at all: two int8 variants of one
# checkpoint differ by 200 KB, which is not a reason to name the less accurate one, while half the
# download for a fifth of a point is exactly the tradeoff a quick decision wants.
function best_in(mode, corpus, want_continuous,    key, best, cheaper) {
    best = ""
    for (key in keys) {
        if (!eligible(mode, key, corpus, want_continuous)) continue
        if (best == "" || (cell_error[key] + 0) < (cell_error[best] + 0)) best = key
    }
    if (best == "") return ""
    cheaper = ""
    for (key in keys) {
        if (key == best) continue
        if (!eligible(mode, key, corpus, want_continuous)) continue
        if ((cell_error[key] + 0) - (cell_error[best] + 0) > tie_points) continue
        if ((cell_error[key] + 0) > (cell_error[best] + 0) * tie_share) continue
        if ((size[cell_id[key]] + 0) <= 0 || (size[cell_id[best]] + 0) <= 0) continue
        if ((size[cell_id[key]] + 0) > (size[cell_id[best]] + 0) * smaller_share) continue
        if (cheaper == "" || (cell_error[key] + 0) < (cell_error[cheaper] + 0)) cheaper = key
    }
    return cheaper != "" ? cheaper : best
}

# The fastest row whose accuracy is still close to the best, for recordings; the quickest to show
# text, for live. Returns "" when the best row is already that row, or when the difference is too
# small to be worth a sentence.
function alternative(mode, corpus, want_continuous, best,    key, pick) {
    pick = ""
    for (key in keys) {
        if (key == best) continue
        if (!eligible(mode, key, corpus, want_continuous)) continue
        # Close enough to name: within half again the best error rate, or within one point
        # of it, which is what keeps a 1.80% and a 2.08% row in the same conversation.
        if ((cell_error[key] + 0) > (cell_error[best] + 0) * close_factor && \
            (cell_error[key] + 0) > (cell_error[best] + 0) + 1) continue
        if (cell_second[key] == "") continue
        if (pick == "") { pick = key; continue }
        if (mode == "live") {
            if (cell_second[key] + 0 < cell_second[pick] + 0) pick = key
        } else if (cell_second[key] + 0 > cell_second[pick] + 0) pick = key
    }
    if (pick == "") return ""
    if (cell_second[best] == "") return pick
    if (mode == "live")
        return ((cell_second[best] + 0) - (cell_second[pick] + 0) >= quicker_seconds) \
            ? pick : ""
    return ((cell_second[pick] + 0) >= (cell_second[best] + 0) * faster_factor) ? pick : ""
}

function claimed_rows(mode,    id, count) {
    count = 0
    for (id in label)
        if (claims_language(id) && has_mode(id, mode == "live" ? "live" : "batch")) count++
    return count
}

function suggest(mode, want_continuous,    key, corpus, best, other, printed, i, n, order, seen) {
    printed = 0
    # The corpora this mode has cells in, the language's own split first and the rest by name.
    n = 0
    for (key in keys) {
        if (!eligible(mode, key, "", want_continuous)) continue
        corpus = cell_corpus[key]
        if (corpus in seen) continue
        seen[corpus] = 1
        n++
        order[n] = sprintf("%d\001%s", corpus_rank(corpus), corpus)
    }
    if (n == 0) return 0
    sort_strings(order, n)
    for (i = 1; i <= n; i++) {
        corpus = substr(order[i], index(order[i], "\001") + 1)
        best = best_in(mode, corpus, want_continuous)
        if (best == "") continue
        # A second corpus is printed only when it disagrees: naming the same model twice, as
        # either pick, is noise. One second answer is enough; a third is a table, not a hint.
        if (printed > 0 && (mode SUBSEP cell_id[best]) in named) continue
        record(mode, "accurate", best)
        printed++
        if (printed > 1) break
        other = alternative(mode, corpus, want_continuous, best)
        if (other != "") record(mode, "fast", other)
    }
    return printed
}

# An insertion sort: awk has no sort of its own that every awk carries, and the list is a handful
# of corpus names.
function sort_strings(list, count,    i, j, value) {
    for (i = 2; i <= count; i++) {
        value = list[i]
        j = i - 1
        while (j >= 1 && list[j] > value) {
            list[j + 1] = list[j]
            j--
        }
        list[j + 1] = value
    }
}

END {
    if (suggest("recordings", "") == 0)
        none("recordings", claimed_rows("recordings") > 0 ? "unmeasured" : "unsupported",
             claimed_rows("recordings"))
    if (suggest("live", live_family()) == 0)
        none("live", claimed_rows("live") > 0 ? "unmeasured" : "unsupported",
             claimed_rows("live"))
}
