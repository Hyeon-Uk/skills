#!/usr/bin/env bash
#
# generate_music.sh — Gemini API의 Lyria 3로 음악 파일을 생성한다.
#
# 사용법:
#   export GEMINI_API_KEY="your_api_key"
#   ./generate_music.sh "A romantic jazz piano piece with soft strings"
#
# 옵션 (환경변수):
#   MODEL       기본 lyria-3-pro-preview
#               대안: lyria-3-clip-preview (30초 클립)
#   OUTPUT_DIR  기본 ./output
#

set -euo pipefail

# ────────────────────────────── 설정 ──────────────────────────────
MODEL="${MODEL:-lyria-3-pro-preview}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
API_BASE="https://generativelanguage.googleapis.com/v1beta/models"

PROMPT="${1:-}"

# ────────────────────────── 사전 검사 ─────────────────────────────
usage() {
    cat >&2 <<EOF
Usage: $0 "<prompt text>"

Examples:
  $0 "A bright chiptune melody, retro 8-bit. Instrumental only, no vocals."
  $0 "[0:00] Intro: piano. [0:15] Verse: female vocal, melancholic."

Environment:
  GEMINI_API_KEY  (필수)  Gemini API 키
  MODEL           (선택)  lyria-3-pro-preview | lyria-3-clip-preview
  OUTPUT_DIR      (선택)  결과 파일이 저장될 디렉터리
EOF
    exit 1
}

if [[ -z "$PROMPT" ]]; then
    usage
fi

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
    echo "Error: GEMINI_API_KEY 환경변수가 설정되지 않았습니다." >&2
    echo "  export GEMINI_API_KEY=your_api_key" >&2
    exit 1
fi

for cmd in curl jq base64; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: 필수 명령이 없습니다: $cmd" >&2
        exit 1
    fi
done

# base64 -d (GNU) 와 base64 -D (BSD/구형 macOS) 호환
b64_decode() {
    if echo "" | base64 -d >/dev/null 2>&1; then
        base64 -d
    else
        base64 -D
    fi
}

# ────────────────────────── 요청 준비 ─────────────────────────────
mkdir -p "$OUTPUT_DIR"
TS=$(date +%Y%m%d_%H%M%S)
RESPONSE_FILE="$OUTPUT_DIR/response_${TS}.json"
LYRICS_FILE="$OUTPUT_DIR/lyrics_${TS}.txt"
# 확장자는 응답의 mime_type을 보고 나중에 확정
AUDIO_FILE_BASE="$OUTPUT_DIR/music_${TS}"

# jq로 페이로드를 안전하게 만든다 (특수문자/줄바꿈 escape)
PAYLOAD=$(jq -n --arg p "$PROMPT" '{
    contents: [{
        parts: [{ text: $p }]
    }]
}')

echo "[*] Lyria 3로 음악 생성 시작"
echo "    모델  : $MODEL"
echo "    프롬프트 : $PROMPT"
echo "    출력  : $OUTPUT_DIR/"
echo

# ────────────────────────── API 호출 ──────────────────────────────
HTTP_CODE=$(curl -sS \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    -X POST "${API_BASE}/${MODEL}:generateContent" \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$PAYLOAD")

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: API 호출 실패 (HTTP $HTTP_CODE)" >&2
    echo "응답 내용:" >&2
    jq . "$RESPONSE_FILE" >&2 2>/dev/null || cat "$RESPONSE_FILE" >&2
    exit 1
fi

echo "[*] 응답 수신, 오디오 추출 중..."

# ────────────────────── 오디오/메타데이터 추출 ────────────────────
# 안전 필터에 걸린 경우
FILTERED=$(jq -r '.candidates[0].finishReason // empty' "$RESPONSE_FILE")
if [[ "$FILTERED" == "SAFETY" || "$FILTERED" == "PROHIBITED_CONTENT" ]]; then
    echo "Error: 안전 필터에 의해 차단되었습니다 (finishReason=$FILTERED)" >&2
    jq -r '.promptFeedback // empty' "$RESPONSE_FILE" >&2
    exit 2
fi

# inline_data와 mime_type 추출
MIME_TYPE=$(jq -r '
    .candidates[0].content.parts[]
    | select(.inline_data != null)
    | .inline_data.mime_type
' "$RESPONSE_FILE" | head -n1)

if [[ -z "$MIME_TYPE" || "$MIME_TYPE" == "null" ]]; then
    echo "Error: 응답에서 오디오 데이터를 찾을 수 없습니다." >&2
    echo "응답 (요약):" >&2
    jq '.candidates[0].content.parts[]? | keys' "$RESPONSE_FILE" >&2 || true
    exit 3
fi

case "$MIME_TYPE" in
    audio/wav|audio/x-wav) EXT="wav" ;;
    audio/mpeg)            EXT="mp3" ;;
    audio/ogg)             EXT="ogg" ;;
    audio/flac)            EXT="flac" ;;
    audio/L16*)            EXT="pcm" ;;
    *)                     EXT="bin" ;;
esac

AUDIO_FILE="${AUDIO_FILE_BASE}.${EXT}"

# base64 → 바이너리 디코딩 (큰 응답을 위해 파이프 사용)
jq -r '
    .candidates[0].content.parts[]
    | select(.inline_data != null)
    | .inline_data.data
' "$RESPONSE_FILE" \
    | b64_decode > "$AUDIO_FILE"

if [[ ! -s "$AUDIO_FILE" ]]; then
    echo "Error: 디코딩된 오디오 파일이 비어 있습니다." >&2
    rm -f "$AUDIO_FILE"
    exit 4
fi

# 가사/구조(텍스트 파트)가 함께 오는 경우 따로 저장
LYRICS=$(jq -r '
    .candidates[0].content.parts[]
    | select(.text != null)
    | .text
' "$RESPONSE_FILE")

if [[ -n "$LYRICS" ]]; then
    printf '%s\n' "$LYRICS" > "$LYRICS_FILE"
fi

# ────────────────────────── 결과 출력 ─────────────────────────────
SIZE=$(wc -c < "$AUDIO_FILE" | tr -d ' ')
echo "[*] 완료"
echo "    오디오 : $AUDIO_FILE  ($((SIZE / 1024)) KB, $MIME_TYPE)"
[[ -n "$LYRICS" ]] && echo "    가사   : $LYRICS_FILE"
echo "    응답   : $RESPONSE_FILE"