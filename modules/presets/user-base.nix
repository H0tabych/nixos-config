# Фича: user-base · Слот: — · Домен: presets · Классы: H · Для: всех пользователей
# Контракт: STR-7, ADR-32 — подключается фичей users каждому пользователю
# независимо от capability. shell-zsh не имеет homeManager-класса (HM
# programs.zsh не используется, A.6) — оболочка подключается через N-сторону
# в пресете base. git — системный пакет (см. файл фичи vcs-tools), доступен
# каждому пользователю хоста через base; lazygit (H-класс той же фичи) —
# сопутствующая TUI-утилита без системной нужды, подключается здесь — тем же
# рассуждением ADR-32 (доступна каждому пользователю, не только capability).
# Зависимости: —
{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.user-base = {
    imports = [
      hm.dotfiles-link
      hm.user-dirs
      hm.prompt-starship
      hm.vcs-tools
    ];
  };
}
