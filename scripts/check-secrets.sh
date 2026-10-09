#!/usr/bin/env bash
# Сканирование кода и истории на секреты (SEC-9, A3). Вызывается .github/workflows/secrets.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

gitleaks detect --source . --redact -v
