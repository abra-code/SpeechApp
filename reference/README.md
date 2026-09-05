# Reference measurements

What is in here is a **starting reference point**, produced once, on one machine. It is not a measurement of anybody else's Mac and must never be presented to a user as one.

## What was measured

`measurements-2026-09-05.tsv` holds 44 cells: every catalog row that could be run, scored over the full FLEURS `en_us` (647 utterances), `pl_pl` (758) and `de_de` (862) test splits, 13,602 utterances in total.

Each cell carries WER, CER, throughput as a multiple of real time, peak memory and load time, plus the machine, the OS and the date, because none of those numbers means anything without them.

| | |
| --- | --- |
| Machine | Apple M5, 24 GB |
| macOS | 26.6.2 |
| Toolchain | Swift 6.2, `speech` built `-c release` |
| Engines | FluidAudio 0.15.6 (CoreML), transcribe.cpp 0.2.3 (ggml on Metal) |
| Corpus | FLEURS test splits, full |
| Produced by | `speech eval --report` |

`models/` holds one page per model family, written from those numbers, for the app's info sheet.

## Why it lives here and not in the CLI

`speech` reports what it is authoritative about: which rows exist, where their weights come from, how big they are, what the loaded model says it can do, and whether it is installed. It does not rank them.

A ranking needs scores, and a score is only valid for the machine, the OS and the dependency versions it was taken on. An M1 Air will not reproduce these throughput figures; a future macOS will not reproduce the Apple baseline; a requantized GGUF will not reproduce the accuracy. Shipping these numbers inside the CLI would freeze one laptop's September 2026 results into every future build and present them as fact.

So they are data the app owns, the app shows them as a reference, and the app can replace them with numbers measured where the user actually is.

## Refreshing them

Any of these can be re-measured with the CLI directly:

```sh
speech eval --model ggml.canary-1b-v2@q8_0 --manifest <corpus>/manifest.tsv \
    --language pl --report out/canary-pl
```

Each run writes `summary.json` and `report.md`. The TSV here is those summaries flattened.

Speech.app is meant to do this for the user rather than making them run a command - over the standard corpora and over their own recordings. See the benchmarking section of the development plan.
