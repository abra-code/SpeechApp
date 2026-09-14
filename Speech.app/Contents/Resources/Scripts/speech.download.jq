# speech.download.jq - reads a model download's events.jsonl (`speech --json models download`).
# Run with -R -r -n and the file as input: each line is parsed on its own, so a line cut short by a
# stopped process is skipped instead of failing the whole read.
#
#   --arg want progress   the card's progress text, such as "Downloading 120 MB of 483 MB (25%)"
#   --arg want outcome    "installed", or "error" and speech's message joined by the unit
#                         separator, or nothing when the download ended without either

def bytes:
    if . == null then ""
    elif . >= 1000000000 then "\((. / 100000000 | round) / 10) GB"
    elif . >= 1000000 then "\(. / 1000000 | round) MB"
    elif . >= 1000 then "\(. / 1000 | round) KB"
    else "\(.) bytes" end;

[inputs | fromjson? | select(type == "object")] as $events
| if $want == "progress" then
    ($events | map(select(.type == "model.progress")) | last) as $p
    | if $p == null then "Starting the download..."
      elif $p.phase == "listing" then "Looking up the files..."
      elif $p.phase == "downloading" then
          "Downloading \($p.bytes_done // 0 | bytes)"
          + (if ($p.bytes_total // 0) > 0
             then " of \($p.bytes_total | bytes) (\(($p.bytes_done // 0) * 100 / $p.bytes_total | floor)%)"
             else "" end)
      elif $p.phase == "compiling" then "Preparing the model for this Mac..."
      elif $p.phase == "installing" then "Installing..."
      else "Downloading..." end
  else
    ($events | map(select(.type == "model.installed" or .type == "error")) | last) as $e
    | if $e == null then empty
      elif $e.type == "model.installed" then "installed"
      else "error\u001f" + ($e.message // "" | tostring | gsub("[\t\r\n\u001f]"; " ")) end
  end
