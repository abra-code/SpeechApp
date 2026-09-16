# speech.record-events.jq - flatten the events of `speech --json record` into one record per event,
# the way speech.events.jq does for a transcription:
#
#   type US seconds US rms_db US message US audio_seconds US device
#
# US is the ASCII unit separator (0x1F), not a tab, so an empty field cannot collapse into its
# neighbor under the shell's `read`. A field the event does not carry is empty. Tabs, line breaks
# and unit separators inside a field become spaces. Unknown event types pass through with their
# type and the reader skips them.

def clean: if . == null then "" else tostring | gsub("[\t\r\n\u001f]"; " ") end;

[ .type,
  .seconds,
  .rms_db,
  .message,
  .audio_seconds,
  .device
]
| map(clean)
| join("\u001f")
