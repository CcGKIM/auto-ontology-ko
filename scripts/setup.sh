#!/usr/bin/env bash
# One-step setup for the Auto-Ontology sample stack.
#
#   bash scripts/setup.sh                 # asks for your NVIDIA API key, nothing else
#   NVIDIA_API_KEY=nvapi-... bash scripts/setup.sh
#
# The NVIDIA API key is the only thing you have to supply. Everything else is a
# fixed INTERNAL-TEST value (see below), because this stack is meant to run on
# your own machine with the sample database, not as a real deployment.
#
# It does three things the install used to ask you to do by hand, and is safe to
# run again (every step skips itself when there is nothing to do):
#   1. fixes Windows line endings (CRLF -> LF) in the files that run in containers
#   2. applies the NVIDIA-hosted-model patch (patches/nvidia-hosted-llm.patch)
#   3. creates .env from .env.example: your key, the fixed test credentials, the
#      sample database connection and the embedding model that works on
#      build.nvidia.com
#
# Fixed test credentials (public, so do not reuse them anywhere that matters;
# docker-compose.sample.yml binds every port to 127.0.0.1 for this reason):
#   Postgres / pgAdmin password   autoontology-test
#   Web login                     admin@nvidia.com / autoontologypassword123
#
# Options:
#   --random-secrets generate random passwords instead of the fixed test ones
#   --force          overwrite an existing .env (a new one is generated)
#   --auto-compile   also start the semantic compilation by itself (calls the
#                    model many times, about 22 minutes on the sample)
#   --skip-patch     do not touch auto_ontology/utils/llm_invoke.py
set -eu

cd "$(dirname "$0")/.."

FORCE=0
RANDOM_SECRETS=0
AUTO_COMPILE=0
SKIP_PATCH=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --random-secrets) RANDOM_SECRETS=1 ;;
    --auto-compile) AUTO_COMPILE=1 ;;
    --skip-patch) SKIP_PATCH=1 ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }

# ---------------------------------------------------------------- 1) line endings
say "[1/3] 줄바꿈 확인"
fixed=0
for f in Dockerfile frontend/Dockerfile mcp/Dockerfile frontend/prisma/migrate.sh \
         auto_ontology/utils/llm_invoke.py; do
  [ -f "$f" ] || continue
  # differs from its CR-stripped copy  <=>  contains CR
  if ! tr -d '\r' < "$f" | cmp -s - "$f"; then
    tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    say "  CRLF -> LF: $f"
    fixed=1
  fi
done
[ "$fixed" = 0 ] && say "  이미 LF입니다."

# ---------------------------------------------------------------- 2) code patch
say "[2/3] NVIDIA 호스팅 모델용 코드 패치"
TARGET=auto_ontology/utils/llm_invoke.py
PATCH=patches/nvidia-hosted-llm.patch
if [ "$SKIP_PATCH" = 1 ]; then
  say "  건너뜀 (--skip-patch)"
elif grep -q "_is_nvidia_hosted" "$TARGET"; then
  say "  이미 적용되어 있습니다."
elif tr -d '\r' < "$PATCH" | git apply --check 2>/dev/null; then
  # the patch itself may have been checked out with CRLF; strip it before applying
  tr -d '\r' < "$PATCH" | git apply
  # with core.autocrlf=true git writes the patched file back with CRLF
  tr -d '\r' < "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
  say "  적용했습니다."
else
  say "  ⚠ 패치를 자동으로 적용하지 못했습니다. $TARGET 이 예상한 버전과 다릅니다." >&2
  say "    README의 '수동으로 하려면'을 보거나, 패치가 필요 없는 환경이면 --skip-patch 로 다시 실행하세요." >&2
  exit 1
fi

# ---------------------------------------------------------------- 3) .env
say "[3/3] .env"
if [ -f .env ] && [ "$FORCE" != 1 ]; then
  say "  .env 가 이미 있어서 건드리지 않습니다. (새로 만들려면 --force)"
else
  KEY="${NVIDIA_API_KEY:-}"
  if [ -z "$KEY" ]; then
    printf '  NVIDIA API 키 (nvapi-... , 입력은 화면에 보이지 않습니다): '
    read -rs KEY
    echo
  fi
  case "$KEY" in
    nvapi-*) ;;
    *) say "  ✗ nvapi- 로 시작하는 NVIDIA 키가 필요합니다. https://build.nvidia.com 에서 받으세요. (OpenAI 키는 안 됩니다)" >&2; exit 1 ;;
  esac
  [ -f .env.example ] || { say "  ✗ .env.example 이 없습니다." >&2; exit 1; }

  # Internal-test defaults. Letters and digits (and "-") only, so they are safe
  # inside a connection URL.
  PG_PW="autoontology-test"; PGADMIN_PW="autoontology-test"
  ADMIN_PW="autoontologypassword123"; AUTH_SEC="auto-ontology-internal-test-secret-0123456789"
  if [ "$RANDOM_SECRETS" = 1 ]; then
    rand() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1" || true; }
    PG_PW="$(rand 24)"; ADMIN_PW="$(rand 20)"; PGADMIN_PW="$(rand 20)"; AUTH_SEC="$(rand 48)"
  fi

  : > .env.tmp
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      DEFAULT_MODELS_API_KEY=*)  printf '%s\n' "DEFAULT_MODELS_API_KEY=$KEY" ;;
      # per-role keys would keep the "nvapi-your-api-key-here" placeholder and win
      # over the default key, so they are left out (they fall back to the default)
      REASONING_API_KEY=*|NON_REASONING_API_KEY=*|EMBED_API_KEY=*|RERANK_API_KEY=*) ;;
      EMBED_MODEL=*)             printf '%s\n' "EMBED_MODEL=nvidia/nemotron-3-embed-1b" ;;
      POSTGRES_PASSWORD=*)       printf '%s\n' "POSTGRES_PASSWORD=$PG_PW" ;;
      CONNECTION_STRINGS=*)      printf '%s\n' "CONNECTION_STRINGS=postgresql://postgres:$PG_PW@postgres:5432/wideworldimporters" ;;
      AUTO_ONTOLOGY_ADMIN_PASSWORD=*) printf '%s\n' "AUTO_ONTOLOGY_ADMIN_PASSWORD=$ADMIN_PW" ;;
      PGADMIN_PASSWORD=*)        printf '%s\n' "PGADMIN_PASSWORD=$PGADMIN_PW" ;;
      AUTH_SECRET=*)             printf '%s\n' "AUTH_SECRET=$AUTH_SEC" ;;
      *)                         printf '%s\n' "$line" ;;
    esac
  done < .env.example >> .env.tmp
  if [ "$AUTO_COMPILE" = 1 ]; then
    printf '\n# start the semantic compilation automatically (see docker-compose.sample.yml)\nSAMPLE_AUTO_COMPILE=true\n' >> .env.tmp
  fi
  mv .env.tmp .env
  say "  .env 를 만들었습니다. (API 키는 출력하지 않습니다)"
fi

ADMIN_EMAIL="$(grep -E '^AUTO_ONTOLOGY_ADMIN_EMAIL=' .env | head -1 | cut -d= -f2- | tr -d '\r')"
say ""
say "끝났습니다. 다음 한 줄로 전부 띄웁니다:"
say "  docker compose -f docker-compose.yml -f docker-compose.sample.yml up -d --build"
say ""
say "웹 화면:  http://localhost:3000   로그인: ${ADMIN_EMAIL:-admin@nvidia.com}"
if [ "$RANDOM_SECRETS" = 1 ]; then
  say "비밀번호는 .env 의 AUTO_ONTOLOGY_ADMIN_PASSWORD 에 있습니다."
else
  say "비밀번호: ${ADMIN_PW:-autoontologypassword123}   (내부 테스트용 고정값, 이 컴퓨터(localhost)에서만 접속됩니다)"
fi
