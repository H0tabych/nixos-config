# Приватная часть владельца: dotfiles-link · Домен: shell
# Контракт: DOT-5, DOT-6, DESK-7, DESK-8. Статические тексты машинного слоя
# (~/.config/machine.d/*), которые Nix формирует из фактов my.host.* и вставляет
# в конфиги приложений через штатный include (STR-6, п. 2): файл-владелец растёт
# за счёт этих текстов, поэтому они здесь, а не в нём.
# Секретов и приватных фактов нет (SEC-2). Импортируется и упоминается только
# в dotfiles-link.nix (C8).
# Зависимости: —
{ lib }:
{
  # host — значение config.my.host фичи-владельца.
  mkMachineFiles =
    { host }:
    let
      # Именованная строка — только для выходов с подтверждённым connector (DESK-8);
      # завершающий wildcard — безопасный fallback для любых остальных физических
      # выходов (A14: не навязывать им режим неподтверждённого/внутреннего монитора).
      monitorLines =
        lib.concatMapStrings (
          o:
          "monitor=${
            if o.connector == null then "" else o.connector
          },${toString o.width}x${toString o.height}@${toString o.refreshRate},auto,1\n"
        ) host.outputs
        + "monitor=,preferred,auto,1\n";
    in
    {
      "hypr-monitors.conf" = ''
        # Сгенерировано Nix (dotfiles-link, DOT-5) из my.host.outputs — не редактируйте руками.
      ''
      + monitorLines;

      "hypr-input.conf" = ''
        # Сгенерировано Nix (dotfiles-link, DOT-5) из my.host.keyboardLayout (DESK-7).
        input {
            kb_layout = ${host.keyboardLayout}
            kb_options = grp:alt_shift_toggle
        }
      '';

      "launch-prefix" = ''
        # Префикс запуска графических приложений (DESK-2). Механизм сессии —
        # UWSM (session-hyprland, R4.3): приложения из лаунчера/бара получают
        # прокси-переменные и остальное окружение сессии через `uwsm app --`.
        LAUNCH_PREFIX=uwsm app --
      '';

      "gpu-env" = ''
        # Сгенерировано Nix (dotfiles-link, DOT-5) из my.host.gpu — не редактируйте руками.
        # Стабильные симлинки устройств создаёт udev-правило фичи gpu-hybrid
        # (DESK-5): /dev/dri/by-host/igpu и /dev/dri/by-host/dgpu.
        GPU_INTEGRATED_BUS_ID=${toString host.gpu.integratedBusId}
        GPU_DISCRETE_BUS_ID=${toString host.gpu.discreteBusId}
        GPU_VRAM_GIB=${toString host.gpu.vramGiB}
      '';

      "battery-info" = ''
        # Сгенерировано Nix (dotfiles-link, DOT-5) из my.host.battery. Имя устройства
        # (/sys/class/power_supply/BAT*) не подтверждено — docs/hosts/sgms-laptop.md §8.
        BATTERY_PRESENT=${if host.battery.present then "1" else "0"}
        BATTERY_CAPACITY_WH=${toString host.battery.capacityWh}
      '';
    };
}
