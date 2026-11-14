@AGENTS.md

# Специфика Claude Code

- Навыки лежат в `.agents/skills/`; `.claude/skills` — симлинк (Claude Code читает навыки только
  оттуда). Команды `.claude/commands/` больше нет: `/step`, `/gate`, `/rule` — навыки.
- Права — `.claude/settings.json` (запреты необратимых команд и чтения секретов); личное —
  `.claude/settings.local.json` и `CLAUDE.local.md` (оба в `.gitignore`).
- `AGENTS.md` каталога Claude Code читает штатно: корневой — через импорт выше, вложенные
  (`modules/`, `secrets/`) — как `CLAUDE.md` соответствующего каталога. `/init` не использовать.
- Память Claude штатная (`~/.claude/projects/<проект>/memory/`).
