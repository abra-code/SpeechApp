# speech.events.jq - flatten `speech --json` events into one record per event, so the poller's
# shell loop reads fields with `read` instead of starting a JSON parser per field.
#
#   type US id US text US percent US phase US message US segments US audio_seconds
#        US wall_seconds US rtfx US file US model US device
#
# `file` and `model` let model.progress say what is being fetched: for Apple's engines, `file` is
# the locale whose speech files macOS is downloading. `device` is the microphone stream.started
# names.
#
# US is the ASCII unit separator (0x1F), not a tab: tab is whitespace to the shell's `read`, so
# two tabs around an empty field would collapse into one and shift every field after it. A field
# the event does not carry is empty. `percent` is the event's fraction as a whole number and
# `rtfx` is rounded. Tabs, line breaks and unit separators inside a field become spaces.
#
# Unknown event types pass through with their type and the reader skips them, which is what
# speech's docs/protocol.md asks of a reader, so a newer speech keeps working with this app.

def clean: if . == null then "" else tostring | gsub("[\t\r\n\u001f]"; " ") end;

[ .type,
  .id,
  .text,
  (if .fraction == null then null else (.fraction * 100 | floor) end),
  .phase,
  .message,
  .segments,
  .audio_seconds,
  .wall_seconds,
  (if .rtfx == null then null else (.rtfx | round) end),
  .file,
  .model,
  .device
]
| map(clean)
| join("\u001f")
