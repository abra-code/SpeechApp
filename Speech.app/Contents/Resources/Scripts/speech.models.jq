# speech.models.jq - the Models window's cards, from `speech --json catalog`. Every row is listed,
# helpers included, in the catalog's own order, which the catalog computes so that no ranking can
# be read into it. Two kinds of line, fields joined by the unit separator (U+001F), which neither a
# cleaned field nor compact JSON can contain:
#
#   L  one row, for the handlers (cards.list, without the L): 1 id, 2 title, 3 label, 4 engine,
#      5 family, 6 role, 7 state, 8 available (1/0), 9 state text, 10 can download (1/0),
#      11 can delete (1/0), 12 size on disk, 13 source, 14 precision, 15 params_m,
#      16 languages, 17 modes (lists comma-joined)
#   C  one card (cards.json, without the C): section container id, card id, the card as compact
#      ActionUI JSON
#
# Arguments: $base, the card id base; $builtin, $installed, $available, the three section
# containers. A card's id is $base + row * 10, rows counted from 1; its parts sit at the offsets
# lib.speech.sh names CARD_*. An installed card has Show (CARD_SHOW), a folder icon, instead of
# the Download button.

def clean: if . == null then "" else tostring | gsub("[\t\r\n\u001f]"; " ") end;

def bytes:
    if . == null then ""
    elif . >= 1000000000 then "\((. / 100000000 | round) / 10) GB"
    elif . >= 1000000 then "\(. / 1000000 | round) MB"
    elif . >= 1000 then "\(. / 1000 | round) KB"
    else "\(.) bytes" end;

def flag: if . then "1" else "0" end;

def marker:
    if .engine == "mlx" then " \ud83c\udd3c"
    elif .engine == "ggml" then " \ud83c\udd36"
    elif .engine == "fluid" then " \ud83c\udd35"
    else "" end;

def on_disk: (.installed_bytes // 0);

def languages_text:
    ((.languages // []) | length) as $n
    | if $n == 0 then "Languages not listed" elif $n == 1 then "1 language" else "\($n) languages" end;

def use_text:
    if .role == "helper" then "Used by other models, not for transcribing on its own"
    elif ((.modes // []) | index("live")) != null then "Recordings and live"
    else "Recordings only" end;

# speech says why a row cannot run here - for Apple's rows on macOS 15, that they need macOS 26.
def unavailable_text:
    "Not available on this Mac" + (if (.reason // "") != "" then ": \(.reason)" else "" end);

def state_text:
    if .state == "system_managed" then
        if .available == true then "Built into macOS" else unavailable_text end
    elif .state == "installed" then
        "Installed" + (if on_disk > 0 then " - \(on_disk | bytes)" else "" end)
        + (if .available == true then "" else ". This Mac cannot run it with this version of Speech." end)
    elif .state == "partial" then
        if on_disk > 0 then
            "Download interrupted - \(on_disk | bytes)"
            + (if .size_bytes then " of \(.size_bytes | bytes)" else "" end)
            + " kept. Download again to resume."
        else "Download interrupted. Download again to resume." end
    elif on_disk > 0 then "Incomplete - \(on_disk | bytes) on disk that cannot be used. Delete it, then download again."
    elif .available != true then unavailable_text
    elif .size_bytes then "Not downloaded - \(.size_bytes | bytes)"
    else "Not downloaded" end;

def shows_download: .state == "missing" or .state == "partial";
# A missing row with files on disk has to be deleted first, as its state text says.
def can_download: .available == true and shows_download and (.state == "partial" or on_disk == 0);
# An installed card takes Show instead of the Download button: a hidden button still takes its
# space, which would leave an empty slot beside the trash button. Cards are rebuilt when the
# catalog changes, so a finished download swaps the button.
def shows_show: .state == "installed";
def can_delete: .state == "installed" or .state == "partial" or (.state != "system_managed" and on_disk > 0);

def section:
    if .state == "system_managed" then $builtin
    elif .state == "installed" then $installed
    else $available end;

# The trailing controls of a card, in the Interpreter Models window's presentation: an installed
# card is a pair of borderless icons, Show (folder) then Delete (trash), 14 apart; every other card
# keeps Delete first and the Download button last, so the prominent button stays flush with the
# card's trailing edge even where a hidden trash still takes its space.
def delete_button($card):
    { type: "Button", id: ($card + 5), properties: { systemImage: "trash", buttonStyle: "borderless", role: "destructive", help: "Delete this model from this Mac", actionID: "speech.models.delete", hidden: (can_delete | not) } };

def show_button($card):
    { type: "Button", id: ($card + 7), properties: { systemImage: "folder", buttonStyle: "borderless", help: "Show this model's files in the Finder", actionID: "speech.models.show" } };

def download_button($card):
    { type: "Button", id: ($card + 4), properties: { title: (if .state == "partial" then "Resume" else "Download" end), buttonStyle: "borderedProminent", actionID: "speech.models.download", hidden: (shows_download | not), disabled: (can_download | not) } };

def card($card):
    {
      type: "GroupBox", id: $card, properties: { frame: { maxWidth: "infinity" } },
      children: [
        {
          type: "VStack", properties: { alignment: "leading", spacing: 6, frame: { maxWidth: "infinity" } },
          children: [
            {
              type: "HStack", properties: { spacing: 8 },
              children: [
                { type: "Text", id: ($card + 1), properties: { text: (((.label // .id) + marker) | clean), font: "headline" } },
                { type: "Spacer" },
                { type: "Button", id: ($card + 6), properties: { systemImage: "info.circle", buttonStyle: "borderless", help: "About this model", actionID: "speech.models.info" } }
              ]
            },
            { type: "Text", id: ($card + 2), properties: { text: ([languages_text, use_text] | join(" - ")), font: "caption", foregroundStyle: "secondary" } },
            {
              type: "HStack", properties: { spacing: (if shows_show then 14 else 8 end) },
              children: ([
                { type: "Text", id: ($card + 3), properties: { text: (state_text | clean), font: "caption", foregroundStyle: "secondary" } },
                { type: "Spacer" }
              ] + (if shows_show then [show_button($card), delete_button($card)]
                   else [delete_button($card), download_button($card)] end))
            }
          ]
        }
      ]
    };

.rows | to_entries[] | (.key + 1) as $row | .value | ($base + $row * 10) as $card
| ( ["L", .id, ((.label // .id) + marker), (.label // .id), .engine, .family, .role, .state,
      (.available == true | flag), state_text, (can_download | flag), (can_delete | flag),
      (if on_disk > 0 then (on_disk | bytes) else "" end), .source, .precision, .params_m,
      ((.languages // []) | join(",")), ((.modes // []) | join(","))]
    | map(clean) | join("\u001f") ),
  ( ["C", (section | tostring), ($card | tostring), (card($card) | tojson)] | join("\u001f") )
