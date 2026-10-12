# Каркас: lib · Домен: core
# Хелперы путей к корню репозитория (STR-9): фичи обращаются к ним вместо ../../.
_: {
  flake.lib.repo = {
    secrets = path: ../../secrets + "/${path}";
    assets = path: ../../assets + "/${path}";
    machines = path: ../../machines + "/${path}";
  };

  flake.lib.host = {
    # STO-5: гибернация возможна только когда задано смещение swap-файла
    # (устройство resume и сам файл появляются вместе с ним — storage/swap, R5.1).
    # Политику закрытия крышки (hardware/sleep) и действие при критическом заряде
    # (hardware/power) нельзя включать раньше: иначе получается «пустая кнопка»
    # Hibernate (L-12). Два потребителя — поэтому функция здесь, а не в фиче
    # (STRUCTURE 3.5, правило второго потребителя).
    hibernationReady = host: host.resume.offset != null;
  };
}
