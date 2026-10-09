# Каркас: lib · Домен: core
# Хелперы путей к корню репозитория (STR-9): фичи обращаются к ним вместо ../../.
_: {
  flake.lib.repo = {
    secrets = path: ../../secrets + "/${path}";
    assets = path: ../../assets + "/${path}";
    machines = path: ../../machines + "/${path}";
  };
}
