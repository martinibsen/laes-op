#!/usr/bin/env bash
#
# laes-op/speak.sh - read text aloud with ElevenLabs TTS on macOS.
#
#   speak.sh /tmp/laes-op.txt     read a file
#   pbpaste | speak.sh            read stdin
#
# Run ./setup.sh once first - it stores the api key and the chosen voice.
#
# Env overrides:
#   TTS_VOICE      ElevenLabs voice id       (default: ~/.config/tts/voice)
#   TTS_MODEL      model id                  (default: eleven_multilingual_v2)
#   TTS_KEY_FILE   file holding the api key  (default: ~/.config/tts/elevenlabs_key)
#   TTS_VOICE_FILE file holding the voice id (default: ~/.config/tts/voice)
#   TTS_MAX_CHARS  chars per request         (default: 2400)
#
# The api key may also come from $ELEVENLABS_API_KEY, which wins over the file.

set -euo pipefail

# Camilla, a native Danish voice. Used only when setup.sh has not run and
# $TTS_VOICE is unset. Any English-trained voice mangles æ, ø and å, so the
# fallback deliberately is not one of ElevenLabs' default premade voices.
FALLBACK_VOICE="4RklGmuxoAskAbGXplXN"

MODEL_ID="${TTS_MODEL:-eleven_multilingual_v2}"
KEY_FILE="${TTS_KEY_FILE:-$HOME/.config/tts/elevenlabs_key}"
VOICE_FILE="${TTS_VOICE_FILE:-$HOME/.config/tts/voice}"
MAX_CHARS="${TTS_MAX_CHARS:-2400}"

if [ -n "${TTS_VOICE:-}" ]; then
  VOICE_ID="$TTS_VOICE"
elif [ -r "$VOICE_FILE" ]; then
  VOICE_ID="$(tr -d '[:space:]' < "$VOICE_FILE")"
else
  VOICE_ID="$FALLBACK_VOICE"
fi

die() { printf 'laes-op: %s\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 findes ikke i PATH"
command -v afplay  >/dev/null 2>&1 || die "afplay findes ikke (scriptet er kun til macOS)"

# --- input: file argument, or stdin -----------------------------------------
workdir="$(mktemp -d "${TMPDIR:-/tmp}/laes-op.XXXXXX")"
next_pid=""
cleanup() {
  [ -n "$next_pid" ] && kill "$next_pid" 2>/dev/null
  rm -rf "$workdir"
  return 0
}
trap cleanup EXIT INT TERM

src="$workdir/input.txt"
if [ "$#" -gt 0 ] && [ "$1" != "-" ]; then
  [ -f "$1" ] || die "filen findes ikke: $1"
  cat -- "$1" > "$src"
else
  cat > "$src"
fi
[ -s "$src" ] || die "ingen tekst at læse op"

# --- api key ----------------------------------------------------------------
if [ -n "${ELEVENLABS_API_KEY:-}" ]; then
  api_key="$ELEVENLABS_API_KEY"
elif [ -r "$KEY_FILE" ]; then
  api_key="$(tr -d '[:space:]' < "$KEY_FILE")"
else
  die "ingen api-nøgle. Kør setup.sh, eller sæt \$ELEVENLABS_API_KEY"
fi
[ -n "$api_key" ] || die "api-nøglen i $KEY_FILE er tom"

[ -n "$VOICE_ID" ] || die "ingen stemme valgt. Kør setup.sh, eller sæt \$TTS_VOICE"

# --- split into chunks and build one json payload per chunk -----------------
# ElevenLabs caps a single request, and shorter requests start playing sooner.
# previous_text/next_text keep the prosody continuous across the seams.
chunks="$(python3 - "$src" "$workdir" "$MODEL_ID" "$MAX_CHARS" <<'PY'
import json, os, re, sys

src, outdir, model, limit = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
text = open(src, encoding="utf-8", errors="replace").read().strip()
if not text:
    sys.exit(3)

units = [u.strip() for u in re.split(r"(?<=[.!?:;])\s+|\n{2,}", text) if u and u.strip()]

chunks, cur = [], ""
for unit in units:
    while len(unit) > limit:            # a single sentence longer than the limit
        chunks.append(unit[:limit])
        unit = unit[limit:]
    if cur and len(cur) + len(unit) + 1 > limit:
        chunks.append(cur)
        cur = unit
    else:
        cur = (cur + " " + unit).strip()
if cur:
    chunks.append(cur)

for i, chunk in enumerate(chunks):
    payload = {"text": chunk, "model_id": model}
    if i > 0:
        payload["previous_text"] = chunks[i - 1][-400:]
    if i < len(chunks) - 1:
        payload["next_text"] = chunks[i + 1][:400]
    path = os.path.join(outdir, "payload-%03d.json" % (i + 1))
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False)

print(len(chunks))
PY
)" || die "kunne ikke dele teksten op"

# --- synthesise + play ------------------------------------------------------
synth() {
  local pad payload out
  pad="$(printf '%03d' "$1")"
  payload="$workdir/payload-$pad.json"
  out="$workdir/chunk-$pad.mp3"
  if ! curl -sS --fail-with-body -X POST \
        "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID?output_format=mp3_44100_128" \
        -H "xi-api-key: $api_key" \
        -H "Content-Type: application/json" \
        -H "Accept: audio/mpeg" \
        --data-binary "@$payload" \
        -o "$out"; then
    printf 'laes-op: ElevenLabs afviste afsnit %s:\n' "$1" >&2
    head -c 800 "$out" >&2; printf '\n' >&2
    return 1
  fi
}

killall afplay 2>/dev/null || true

synth 1 || exit 1
for (( i = 1; i <= chunks; i++ )); do
  if (( i < chunks )); then
    synth $(( i + 1 )) &
    next_pid=$!
  fi

  rc=0
  afplay "$workdir/chunk-$(printf '%03d' "$i").mp3" || rc=$?
  if (( rc != 0 )); then
    (( rc >= 128 )) && exit 0          # afbrudt med vilje (killall / Ctrl-C)
    die "afplay fejlede (kode $rc)"
  fi

  if [ -n "$next_pid" ]; then
    wait "$next_pid" || die "kunne ikke hente lyd til afsnit $(( i + 1 ))"
    next_pid=""
  fi
done
