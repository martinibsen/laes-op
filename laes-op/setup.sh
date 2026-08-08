#!/usr/bin/env bash
#
# laes-op/setup.sh - one-time setup: store an ElevenLabs api key and pick a voice.
#
# Fetches the most-used voices for your language from ElevenLabs' shared library,
# speaks a sample sentence in each, and saves the one you pick. Nothing is added
# to your ElevenLabs account; shared voices are used directly by id.
#
# Written for macOS (uses afplay). bash 3.2 compatible.

set -euo pipefail

CONFIG_DIR="${TTS_CONFIG_DIR:-$HOME/.config/tts}"
KEY_FILE="$CONFIG_DIR/elevenlabs_key"
VOICE_FILE="$CONFIG_DIR/voice"
API="https://api.elevenlabs.io/v1"
CANDIDATES=6
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

b=""; d=""; o=""
if [ -t 1 ]; then
  b="$(tput bold 2>/dev/null || true)"
  d="$(tput dim  2>/dev/null || true)"
  o="$(tput sgr0 2>/dev/null || true)"
fi

die() { printf '\n%ssetup: %s%s\n' "$b" "$1" "$o" >&2; exit 1; }
hd()  { printf '\n%s%s%s\n' "$b" "$1" "$o"; }

[ -t 0 ] || die "kør scriptet i en terminal, det stiller spørgsmål undervejs"

# --- 1. dependencies --------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "scriptet bruger afplay og virker kun på macOS"
for tool in curl python3 afplay; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool findes ikke i PATH"
done
mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"

# --- 2. api key -------------------------------------------------------------
hd "1. ElevenLabs api-nøgle"
if [ -s "$KEY_FILE" ]; then
  printf '   Der ligger allerede en nøgle i %s\n' "$KEY_FILE"
  printf '   Behold den? [J/n] '
  read -r keep
  case "$(printf '%s' "$keep" | tr '[:upper:]' '[:lower:]')" in
    n|nej|no) rm -f "$KEY_FILE" ;;
  esac
fi

if [ ! -s "$KEY_FILE" ]; then
  printf '   Hent en nøgle på %shttps://elevenlabs.io/app/settings/api-keys%s\n' "$d" "$o"
  printf '   Indsæt den her (den vises ikke): '
  read -r -s api_key
  printf '\n'
  [ -n "$api_key" ] || die "tom nøgle"
  printf '%s' "$api_key" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  unset api_key
fi

KEY="$(tr -d '[:space:]' < "$KEY_FILE")"
printf '   Tjekker nøglen ... '
if ! curl -sS --fail-with-body "$API/user/subscription" -H "xi-api-key: $KEY" -o /tmp/laes-op-sub.json 2>/dev/null; then
  rm -f "$KEY_FILE"
  die "nøglen blev afvist. Prøv igen."
fi
python3 - <<'PY'
import json
d = json.load(open('/tmp/laes-op-sub.json'))
used, cap = d.get('character_count', 0), d.get('character_limit', 0)
print("ok. Plan: %s, brugt %s af %s tegn." % (d.get('tier', '?'), used, cap))
if cap and cap - used < 2000:
    print("   Bemærk: der er under 2000 tegn tilbage. Prøverne herunder koster cirka 600.")
PY

# --- 3. language ------------------------------------------------------------
hd "2. Sprog"
printf '   Tosbogstavskode, fx da, en, sv, de, nl, fr, es [da]: '
read -r lang
lang="$(printf '%s' "${lang:-da}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

# --- 4. fetch candidates ----------------------------------------------------
printf '   Henter de mest brugte %s-stemmer ... ' "$lang"
curl -sS --fail-with-body "$API/shared-voices?language=$lang&page_size=60&sort=trending" \
  -H "xi-api-key: $KEY" -o /tmp/laes-op-shared.json \
  || die "kunne ikke hente stemmer"

python3 - "$lang" "$CANDIDATES" > /tmp/laes-op-cands.tsv <<'PY'
import json, sys
lang, want = sys.argv[1], int(sys.argv[2])
voices = json.load(open('/tmp/laes-op-shared.json')).get('voices', [])

# The ?language= filter matches any voice that CAN speak the language, not
# voices that ARE it. Ask for Danish and you get Adam - American, Dark and
# Tough, whose 1.9M clones bury every native Danish voice. Requiring the
# voice's own primary language is what keeps æ, ø and å intact.
native = [v for v in voices if (v.get('language') or '') == lang]
if not native:
    sys.stderr.write("no-native\n")
    sys.exit(2)

native.sort(key=lambda v: v.get('cloned_by_count', 0), reverse=True)

seen, rows = set(), []
for v in native:
    name = (v.get('name') or '').strip()
    if not name or name in seen:
        continue
    seen.add(name)
    desc = ' '.join((v.get('description') or '').split())[:88]
    meta = ', '.join(x for x in (v.get('gender'), v.get('age'), v.get('accent')) if x)
    rows.append((v['voice_id'], name, meta, desc))
    if len(rows) >= want:
        break

for i, r in enumerate(rows, 1):
    print('\t'.join([str(i)] + list(r)))
PY
[ -s /tmp/laes-op-cands.tsv ] || die "ingen stemmer med '$lang' som modersmål. ElevenLabs har engelske stemmer, der kan sproget, men de udtaler det med accent. Prøv en anden sprogkode."
printf 'fandt %s\n' "$(wc -l < /tmp/laes-op-cands.tsv | tr -d ' ')"

SAMPLE="$(python3 - "$lang" <<'PY'
import sys
lang = sys.argv[1]
s = {
 "da": "Rødgrød med fløde på Ærø. Sådan lyder jeg, når jeg læser dine tekster højt.",
 "en": "This is how I sound when I read your text out loud.",
 "sv": "Så här låter jag när jag läser din text högt.",
 "no": "Slik høres jeg ut når jeg leser teksten din høyt.",
 "de": "So klinge ich, wenn ich deinen Text vorlese.",
 "nl": "Zo klink ik wanneer ik jouw tekst voorlees.",
 "fr": "Voici ma voix lorsque je lis votre texte à haute voix.",
 "es": "Así sueno cuando leo tu texto en voz alta.",
 "it": "Ecco come suono quando leggo il tuo testo ad alta voce.",
 "pt": "É assim que eu soo quando leio o seu texto em voz alta.",
}
print(s.get(lang, s["en"]))
PY
)"

# --- 5. synthesise samples --------------------------------------------------
hd "3. Prøver"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/laes-op-setup.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

sample_for() { # $1=index $2=voice_id $3=name
  python3 -c "import json,sys;print(json.dumps({'text':sys.argv[1],'model_id':'eleven_multilingual_v2'},ensure_ascii=False))" \
    "$3. $SAMPLE" > "$WORK/$1.json"
  curl -sS --fail-with-body -X POST \
    "$API/text-to-speech/$2?output_format=mp3_44100_128" \
    -H "xi-api-key: $KEY" -H "Content-Type: application/json" -H "Accept: audio/mpeg" \
    --data-binary "@$WORK/$1.json" -o "$WORK/$1.mp3" 2>/dev/null
}

printf '   Laver %s prøver ' "$(wc -l < /tmp/laes-op-cands.tsv | tr -d ' ')"
while IFS=$'\t' read -r i vid name meta desc; do
  sample_for "$i" "$vid" "$name" && printf '.' || printf 'x'
done < /tmp/laes-op-cands.tsv
printf ' klar\n\n'

play_all() {
  while IFS=$'\t' read -r i vid name meta desc; do
    [ -s "$WORK/$i.mp3" ] || continue
    printf '   %s%s.%s %s %s%s%s\n' "$b" "$i" "$o" "$name" "$d" "${meta:+($meta)}" "$o"
    [ -n "$desc" ] && printf '      %s%s%s\n' "$d" "$desc" "$o"
    afplay "$WORK/$i.mp3" 2>/dev/null || true
    sleep 0.3
  done < /tmp/laes-op-cands.tsv
}
play_all

# --- 6. choose --------------------------------------------------------------
while :; do
  printf '\n   Vælg nummer, %sa%s for at høre alle igen, eller %s1-N%s igen for én: ' "$b" "$o" "$b" "$o"
  read -r pick
  pick="$(printf '%s' "$pick" | tr -d '[:space:]')"
  case "$pick" in
    a|A) play_all; continue ;;
    ''|*[!0-9]*) printf '   Skriv et tal eller a.\n'; continue ;;
  esac
  line="$(awk -F'\t' -v n="$pick" '$1==n' /tmp/laes-op-cands.tsv)"
  [ -n "$line" ] || { printf '   Findes ikke.\n'; continue; }
  CHOSEN_ID="$(printf '%s' "$line" | cut -f2)"
  CHOSEN_NAME="$(printf '%s' "$line" | cut -f3)"
  printf '   Valgt: %s%s%s. Gem? [J/n] ' "$b" "$CHOSEN_NAME" "$o"
  read -r ok
  case "$(printf '%s' "$ok" | tr '[:upper:]' '[:lower:]')" in
    n|nej|no) continue ;;
  esac
  break
done

printf '%s' "$CHOSEN_ID" > "$VOICE_FILE"
chmod 600 "$VOICE_FILE"

# --- 7. done ----------------------------------------------------------------
hd "Færdig"
printf '   Nøgle:  %s\n' "$KEY_FILE"
printf '   Stemme: %s  (%s)\n' "$VOICE_FILE" "$CHOSEN_NAME"
printf '   Skift stemme igen: kør %s./setup.sh%s. Skift for ét kald: %sTTS_VOICE=<id>%s\n\n' "$d" "$o" "$d" "$o"

if [ -x "$HERE/speak.sh" ]; then
  printf '%s' "$SAMPLE" | "$HERE/speak.sh" || true
fi
