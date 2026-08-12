# Læs op

A [Claude Code](https://claude.com/claude-code) skill that reads text aloud in a
native Danish voice, via ElevenLabs and `afplay`. A skill I actually use, not a demo.

A skill is a folder with a `SKILL.md` in it. The frontmatter says *when* to use it,
the body says *how*. Claude reads the description, decides it applies, and follows the
instructions. That is the whole mechanism. No plugin API, no framework, no build step.

## Install

Clone, then symlink the skill into Claude Code's skills directory:

```bash
git clone https://github.com/martinibsen/laes-op.git ~/Projects/laes-op
ln -s ~/Projects/laes-op/laes-op ~/.claude/skills/laes-op
```

Symlink rather than copy, so `git pull` updates the skill in place.

## What it does

Say *"læs det op"*, *"læs det her højt"* or *"read this aloud"*, and Claude strips the
markdown out of whatever you are looking at and speaks the prose through a real voice.
Built for proofreading by ear: an essay that reads fine on screen often falls apart when
you hear it.

macOS only, because it plays audio with `afplay`.

### Setup

```bash
cd ~/Projects/laes-op/laes-op && ./setup.sh
```

It asks for an [ElevenLabs api key](https://elevenlabs.io/app/settings/api-keys), fetches
the most-used voices for your language, speaks a sample sentence in each, and saves the one
you pick to `~/.config/tts/voice`. The key goes in `~/.config/tts/elevenlabs_key`, mode 600.
Nothing is added to your ElevenLabs account: shared voices are addressed directly by id.

### The part that is not obvious

ElevenLabs' `?language=da` filter returns every voice that *can* speak Danish, not the
voices that *are* Danish. Ask for Danish and the top of the list is `Adam - American, Dark
and Tough`, whose 1.9 million clones bury every native Danish voice. He will read your text,
and he will pronounce æ, ø and å like an American reading a street sign in Aarhus.

`setup.sh` therefore requires the voice's own primary language to match, which drops 34 of
60 results and leaves the ones with a Danish mouth. Same trap applies to any language that
is not English.

### Use

Ask Claude, or run it directly:

```bash
./speak.sh notes.md          # from a file
pbpaste | ./speak.sh         # from the clipboard
killall afplay               # stop
```

Long texts are split on sentence boundaries and synthesised chunk by chunk, so playback
starts before the whole text is rendered. Each chunk carries the neighbouring text along
as context, so the voice does not reset its intonation at the seams.

### Configuration

| Variable | Default | |
|---|---|---|
| `TTS_VOICE` | `~/.config/tts/voice` | voice id for one run |
| `TTS_MODEL` | `eleven_multilingual_v2` | model id |
| `TTS_KEY_FILE` | `~/.config/tts/elevenlabs_key` | where the key lives |
| `TTS_MAX_CHARS` | `2400` | characters per request |

`$ELEVENLABS_API_KEY` overrides the key file if set.

### Cost

ElevenLabs bills per character. A 1,200 word essay is roughly 7,000 characters, so the
free tier is about one and a half essays a month. Check your balance before feeding it a
book.

## Licence

MIT. See [LICENSE](LICENSE).
