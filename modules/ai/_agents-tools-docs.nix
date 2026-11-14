# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Отчёт лаунчера о документах и файлах агентов в проекте (AI-AGT-8, AI-AGT-9, AI-A19; ADR-47).
# Дополняет `agents-git` (AI-SBX-7): тот смотрит на метаданные git, этот — на то, что агент
# оставил в проекте и в порядке ли документация. Это отчёт, а не граница: сообщает, не меняет.
#   - новые неотслеживаемые файлы, которые адаптер агента знает как свои (`AGENTS_PROJECT_FILES`,
#     строки «glob|причина»; правила по назначению, без списков имён в лаунчере): «файл агента»;
#   - `CLAUDE.md` рядом с `AGENTS.md` без строки-импорта `@AGENTS.md` — в своём проекте это
#     дубль знаний (AI-A19); в чужом (командном) репозитории файлы не переписываются, замечание
#     к ним не относится — решает человек.
# Использование:
#   agents-docs snapshot <корень> <файл>   — до сессии
#   agents-docs report   <корень> <файл>   — после сессии, в stderr
# Вне git-репозитория ничего не делает.
{ pkgs }:
pkgs.writeShellApplication {
  name = "agents-docs";
  runtimeInputs = [
    pkgs.git
    pkgs.coreutils
  ];
  text = ''
    [ "$#" -eq 3 ] || {
      echo "usage: agents-docs <snapshot|report> <root> <file>" >&2
      exit 1
    }
    cmd=$1
    root=$2
    file=$3
    git -C "$root" rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

    untracked() { git -C "$root" ls-files -o --exclude-standard | sort; }

    case "$cmd" in
      snapshot) untracked > "$file" ;;
      report)
        [ -r "$file" ] || exit 0
        notes=()
        while IFS='|' read -r glob reason; do
          [ -n "$glob" ] || continue
          while IFS= read -r path; do
            # shellcheck disable=SC2053  # glob из адаптера — намеренно образец
            if [[ $path == $glob ]]; then
              notes+=("файл агента: $path — $reason")
            fi
          done < <(comm -13 "$file" <(untracked))
        done <<< "''${AGENTS_PROJECT_FILES:-}"
        if [ -f "$root/CLAUDE.md" ] && [ -f "$root/AGENTS.md" ] && ! grep -qx '@AGENTS.md' "$root/CLAUDE.md"; then
          notes+=("CLAUDE.md рядом с AGENTS.md без строки '@AGENTS.md' — в своём проекте это дубль знаний (AI-A19)")
        fi
        if [ "''${#notes[@]}" -gt 0 ]; then
          echo "agent-launcher: документы и файлы агентов (AI-AGT-8) — проверьте:" >&2
          printf '  %s\n' "''${notes[@]}" >&2
        fi
        ;;
      *)
        echo "usage: agents-docs <snapshot|report> <root> <file>" >&2
        exit 1
        ;;
    esac
  '';
}
