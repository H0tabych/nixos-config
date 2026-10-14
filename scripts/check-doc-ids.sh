#!/usr/bin/env bash
# Сверка ID правил между документами docs/architecture/*.md и docs/adr/*.md:
# каждый ID, упомянутый где-либо, должен быть определён где-либо (иначе —
# опечатка или ссылка на правило, которое переименовали/удалили — так был
# найден мёртвый ADR-33 при правке ROADMAP.md). Вызывается justfile/check.yml.
#
# Область: только ID с дефисом из закреплённых в документах семейств
# (раздел 0.4 каждого документа). Короткие формы без дефиса (A1, C1, D1, G4,
# W1, RK1, R4.7, M2, S1) — вне охвата: слишком шумно для общего regex,
# и это не те правила, что разошлись в сессии 2026-10-10 (DOT-4 vs A14,
# ADR-33). ПРОВЕРИТЬ при необходимости расширять вручную.
set -euo pipefail
cd "$(dirname "$0")/.."

DOCS=(docs/architecture/*.md docs/adr/*.md)

# Семейства ID с дефисом (0.4 каждого документа + реестр ADR Архитектуры).
PREFIX='ARCH|STR|DOT|SEC|STO|NET|DESK|DEV|APP|ML|OPS|HOST|USER|FEAT|ADR|PNR|L'
PREFIX="$PREFIX|VPN-A|VPN-MOD|VPN-CLI|VPN-RTE|VPN-DNS|VPN-KS|VPN-SRV|VPN-LLM|VPN-RES|VPN-INT|VPN-SEC|VPN-OPS"
PREFIX="$PREFIX|AI-A|AI-INF|AI-CMP|AI-GW|AI-AGT|AI-CTX|AI-RES|AI-SEC|AI-OPS|AI-ROLE|AI-CC|AI-SBX"
PREFIX="$PREFIX|DSN-P|DSN-MAT|DSN-COL|DSN-TYP|DSN-SHP|DSN-MOT|DSN-LAY|DSN-CMP|DSN-EXC|DSN-PWR|DSN-TOK"
ID_RE="\b(${PREFIX})-[0-9]+[a-z]?\b"

# Определения: первая колонка таблицы ("| ARCH-1 |", "| **PNR-2** |")
# либо жирным в начале абзаца ("**STR-1.** Текст…" или "**STR-4a. Заголовок.**
# Текст…" — оба стиля встречаются).
defined=$(grep -ohE "^\|[[:space:]]*\*{0,2}(${PREFIX})-[0-9]+[a-z]?\*{0,2}[[:space:]]*\||^\*\*(${PREFIX})-[0-9]+[a-z]?\.[^*]*\*\*" "${DOCS[@]}" \
  | grep -oE "(${PREFIX})-[0-9]+[a-z]?" | sed -E 's/-0+([0-9])/-\1/' | sort -u)

# Все упоминания (включая определения). Числа без лидирующих нулей —
# иначе "ADR-001" в примере пути (Приложение E) ложно считается опечаткой.
mentioned=$(grep -ohE "$ID_RE" "${DOCS[@]}" | sed -E 's/-0+([0-9])/-\1/' | sort -u)

missing=$(comm -23 <(echo "$mentioned") <(echo "$defined"))

if [ -n "$missing" ]; then
  echo "[check-doc-ids] ОШИБКА: упомянуты, но не определены ни в одном документе:"
  echo "$missing" | sed 's/^/  /'
  exit 1
fi

echo "[check-doc-ids] все ID с дефисом из закреплённых семейств упомянуты только там, где определены"
