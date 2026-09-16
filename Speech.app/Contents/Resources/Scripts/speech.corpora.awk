# speech.corpora.awk - one pass over corpora.tsv for the Benchmark tab's Corpus picker.
#
# Every corpus FLEURS has a test split for is offered, which is more than a hundred rows, and the tab
# asks on every poller tick which of them are on this Mac. A corpus_field call per row is an awk per
# row, so the whole question is answered here in one. Three lines come out:
#
#   1  one character per corpus, in table order: p when its manifest is on this Mac, - when it is not
#   2  the picker position of the corpus named by -v selected, empty when the table has no such id
#   3  the picker's options: a JSON array of the titles, the ones not here saying so
#
# Variables: dir is the Corpora directory, selected is the chosen corpus id, and downloading holds the
# ids downloading right now, each surrounded by spaces.
#
# The row filter is corpus_ids' filter, so line 1's characters and line 2's position are positions in
# that list, and a caller can turn either back into an id with it.

function json_string(text,   out, i, c) {
    out = ""
    for (i = 1; i <= length(text); i++) {
        c = substr(text, i, 1)
        if (c == "\\") out = out "\\\\"
        else if (c == "\"") out = out "\\\""
        else if (c >= " ") out = out c
    }
    return "\"" out "\""
}

BEGIN { FS = "\t" }

!/^#/ && NF >= 5 {
    position++
    # getline rather than a shell test: a manifest that opens and has a line is a corpus that is
    # here, which is what corpus_is_present asks with [ -s ]. Each file is closed again because a
    # hundred of them are read on every tick.
    got = (getline line < (dir "/" $4))
    close(dir "/" $4)

    title = $2
    if (got <= 0) {
        marks = marks "-"
        # An arrow to a bar (U+2913) on a corpus that has to be fetched: a cloud reads as weather in
        # a menu, and an emoji arrow sits heavily in a list of a hundred. It is written as bytes so
        # this file stays ASCII, and json_string copies it a byte at a time, leaving its UTF-8 alone.
        if (index(downloading, " " $1 " ") > 0) title = title " (downloading)"
        else title = title "   \342\244\223"
    } else {
        marks = marks "p"
    }

    if ($1 == selected) at = position
    options = options (position > 1 ? "," : "") json_string(title)
}

END {
    print marks
    print at
    print "[" options "]"
}
