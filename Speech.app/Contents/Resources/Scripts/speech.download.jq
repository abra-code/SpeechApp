# speech.download.jq - reads the events.jsonl of a model download (`speech --json models download`)
# or of an add (`speech --json models add`). Run with -R -r -n and the file as input: each line is
# parsed on its own, so a line cut short by a stopped process is skipped instead of failing the
# whole read.
#
#   --arg want progress   the card's progress text, such as "Downloading 120 MB of 483 MB (25%)"
#   --arg want outcome    "installed", or "error" and speech's message joined by the unit
#                         separator, or nothing when the download ended without either
#   --arg want adding     what an add is doing now, for the Models window's status line
#   --arg want added      "added" and the id speech added, "installed" and the id of a model already
#                         listed whose download it finished, or "error" and speech's message, joined
#                         by the unit separator, or nothing when the add ended without either

def bytes:
    if . == null then ""
    elif . >= 1000000000 then "\((. / 100000000 | round) / 10) GB"
    elif . >= 1000000 then "\(. / 1000000 | round) MB"
    elif . >= 1000 then "\(. / 1000 | round) KB"
    else "\(.) bytes" end;

def clean: tostring | gsub("[\t\r\n\u001f]"; " ");

def progress_text:
    if . == null then "Starting the download..."
    elif .phase == "listing" then "Looking up the files..."
    elif .phase == "downloading" and .bytes_done != null then
        "Downloading \(.bytes_done | bytes)"
        + (if (.bytes_total // 0) > 0
           then " of \(.bytes_total | bytes) (\(.bytes_done * 100 / .bytes_total | floor)%)"
           else "" end)
    # A FluidAudio model counts files, not bytes: speech gives the fraction and "3 of 16 files".
    elif .phase == "downloading" then
        "Downloading..."
        + (if .fraction != null then " \(.fraction * 100 | floor)%" else "" end)
        + (if .file != null then " (\(.file | clean))" else "" end)
    elif .phase == "compiling" then "Preparing the model for this Mac..."
    elif .phase == "installing" then "Installing..."
    else "Downloading..." end;

# speech's usage messages name its command-line options; the sheet's field stands for --quant.
# A message this does not match is shown as speech wrote it.
def app_wording:
    gsub("; pick one with --quant or --file"; "; enter the quantization of the one you want")
    | gsub("; pass --quant <name>"; "; enter its quantization");

[inputs | fromjson? | select(type == "object")] as $events
| if $want == "progress" then
    $events | map(select(.type == "model.progress")) | last | progress_text
  elif $want == "adding" then
    ($events | map(select(.type == "model.progress" or .type == "model.installed")) | last) as $p
    | if $p == null then "Looking up the repository..."
      elif $p.type == "model.installed" then "Checking that Speech can transcribe with it..."
      else $p | progress_text end
  elif $want == "added" then
    ($events | map(select(.added != null or .type == "error")) | last) as $e
    | ($events | map(select(.type == "model.installed")) | last) as $installed
    | if $e == null and $installed != null then "installed\u001f" + ($installed.model // "" | clean)
      elif $e == null then empty
      elif $e.type == "error" then "error\u001f" + ($e.message // "" | app_wording | clean)
      else "added\u001f" + ($e.added.id // "" | clean) end
  else
    ($events | map(select(.type == "model.installed" or .type == "error")) | last) as $e
    | if $e == null then empty
      elif $e.type == "model.installed" then "installed"
      else "error\u001f" + ($e.message // "" | clean) end
  end
