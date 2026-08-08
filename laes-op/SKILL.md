---
name: laes-op
description: Use when the user wants text spoken out loud on their Mac instead of printed - "læs det op", "læs det her højt", "læs artiklen op", "kan du læse det op", "sig det højt", "read this aloud", "read it out loud", "say this out loud", "speak this" - whether they point at a file, a draft, an essay, or the answer you just gave. Also use when they ask to stop, pause, or replay the audio.
---

# Læs op

Speaks text aloud through ElevenLabs TTS and macOS `afplay`. The user hears prose,
not markup, so the text is cleaned before it is sent.

## Steps

1. **Pick the text.** Whatever they pointed at: a file, a passage, or your own
   previous answer. If it is ambiguous, read the most recent thing you produced.
2. **Clean it** into plain spoken prose (rules below).
3. **Write the clean text** to `/tmp/laes-op.txt`.
4. **Run it in the background** — playback blocks for as long as the audio lasts,
   which can exceed the foreground timeout on a long text:

   ```bash
   bash ~/.claude/skills/laes-op/speak.sh /tmp/laes-op.txt
   ```

5. **Say one line** about what is being read. Do not reprint the text.

## Cleaning rules

| In the source | Send to the voice |
|---|---|
| `#`, `##` headings | The words alone, ending in a period so it gets a pause |
| `**bold**`, `*kursiv*`, `_x_`, `` `kode` `` | The words alone, markers stripped |
| Fenced code blocks | Drop entirely. Say "kodeblokken springes over" only if it carried the point |
| `[tekst](url)` | `tekst`. Never the url |
| Bare URLs, image refs, footnote markers | Drop |
| `- `, `* `, `1. ` list markers | Drop the marker, keep the item as its own sentence |
| Tables | One short sentence per row, or skip the table and name what it showed |
| Emoji, box drawing, `|`, `>` quote marks | Drop |
| Sentence punctuation `. , : ; ? !` | **Keep** — it is what drives the pauses and intonation |

Danish text goes to the voice as Danish. Do not translate, do not summarise, do
not add a spoken preamble like "Her er teksten". Read what they asked for.

## Stop or replay

- Stop: `killall afplay`
- Replay the same text: rerun step 4. The script kills any running playback first,
  so a new request always interrupts the old one.

## Configuration

- **Key**: `~/.config/tts/elevenlabs_key` (mode 600). `$ELEVENLABS_API_KEY` overrides it.
- **Voice**: Camilla, a native Danish voice, hardcoded as `DEFAULT_VOICE` in `speak.sh`.
  Override per run with `TTS_VOICE=<voice-id>`. Do not swap in one of the account's own
  library voices — they are all English-trained and mispronounce æ, ø and å.
- **Model**: `eleven_multilingual_v2`. Override with `TTS_MODEL`.
- Long texts are split on sentence boundaries and streamed chunk by chunk, so audio
  starts before the whole text is synthesised.

## Common mistakes

- **Running it in the foreground** — the call hangs for the length of the audio.
- **Sending raw markdown** — the voice reads asterisks and backticks out loud.
- **Reading the text back in the reply too** — they asked to hear it, not read it.
- **Summarising instead of reading** — only summarise if they explicitly asked for it.
