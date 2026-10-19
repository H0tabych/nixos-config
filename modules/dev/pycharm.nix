# Фича: pycharm · Слот: — · Домен: dev · Классы: H · Для: capability development
# Контракт: DEV-9/AI-CMP-8 (ARCHITECTURE.md §6, каталог dev): необязательная
# JetBrains IDE для Python вне реестра приложений (DOT-3 на неё не
# распространяется — конфиг IDE живёт внутри самой IDE, не в dotfiles).
# С апреля 2025 PyCharm Professional и Community объединены в один продукт
# (jetbrains.pycharm, unfree): базовый функционал бесплатен без ограничения
# по времени, Pro-фичи — по подписке после месяца триала. Старый бесплатный
# пакет jetbrains.pycharm-oss помечен в nixpkgs insecure (CVE, без обновлений).
# Зависимости: —
_: {
  flake.modules.homeManager.pycharm = { pkgs, ... }: {
    home.packages = [ pkgs.jetbrains.pycharm ];
  };
}
