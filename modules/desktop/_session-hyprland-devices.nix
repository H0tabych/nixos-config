# Приватная часть владельца: session-hyprland · Домен: desktop
# Контракт: DESK-5, A5, A.6 (AQ_DRM_DEVICES — список через двоеточие из
# udev-симлинков без двоеточий). Тексты скрипта обновления списка, env-дропина
# UWSM и udev-правила (STR-6): session-hyprland.nix растёт за счёт них.
#
# Почему список динамический. По DESK-5 он не включает дискретную GPU, пока к
# её выходам ничего не подключено — иначе композитор держит её занятой и A5
# (suspended в простое) не выполняется. На этом хосте HDMI-A-1 и DP-1
# принадлежат именно дискретной (docs/hosts/sgms-laptop.md §13), поэтому
# «подключён внешний монитор» = «дискретная нужна».
#
# Почему env-дропин, а не конфиг композитора. AQ_DRM_DEVICES читает aquamarine
# при инициализации бэкенда, до применения `env =` из hyprland.conf, поэтому
# переменная должна быть в окружении ДО запуска — то есть в env-файлах UWSM
# (A.6). Владелец uwsm/env — сам session-hyprland (там прокси M1), поэтому
# список уезжает в отдельный дропин uwsm/env.d/*: man uwsm(1) перечисляет
# `uwsm/env.d/`* как сорсируемый каталог, так что двух владельцев одного файла
# не возникает (ARCH-1).
#
# Чего механизм НЕ делает: не переключает устройства у уже запущенного
# композитора — aquamarine перечисляет их один раз на старте. Юнит держит файл
# актуальным, поэтому верный список получает СЛЕДУЮЩИЙ старт сессии. Это и есть
# критерий A5/R5.7 «композитор стартует в обоих случаях», а не горячая замена
# набора GPU под работающей сессией.
# Зависимости: —
{ lib, pkgs }:
{
  # host — значение config.my.host фичи-владельца.
  mkCompositorDevices =
    { host }:
    let
      stateDir = "/run/compositor-devices";
      listFile = "${stateDir}/aq-drm-devices";

      igpu = "/dev/dri/by-host/igpu";
      dgpu = "/dev/dri/by-host/dgpu";

      # Скрипт принадлежит этой фиче целиком: он читает только sysfs и факт
      # шины, без значений хоста в тексте — адрес приходит аргументом.
      refresh = pkgs.writeShellApplication {
        name = "compositor-devices-refresh";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          # $1 — PCI-адрес дискретной GPU в формате udev/lspci (0000:01:00.0).
          dgpu_bus=$1
          dgpu_needed=0

          # Выходы дискретной GPU: у разъёма card<N>-<имя> родительская карта
          # card<N>, а у неё device → PCI-устройство. Сопоставление идёт по
          # шине, а не по номеру карты: cardN меняется между загрузками (L-6).
          for status in /sys/class/drm/*/status; do
            connector=''${status%/status}
            card=''${connector##*/}
            card=''${card%%-*}

            device=/sys/class/drm/$card/device
            [ -e "$device" ] || continue
            [ "$(basename "$(readlink -f "$device")")" = "$dgpu_bus" ] || continue

            if [ "$(cat "$status")" = connected ]; then
              dgpu_needed=1
              break
            fi
          done

          mkdir -p ${stateDir}

          # Встроенная GPU всегда первая: первый элемент списка — основной
          # рендерер, по DESK-5 это встроенная.
          if [ "$dgpu_needed" = 1 ]; then
            printf '%s:%s\n' ${igpu} ${dgpu} > ${listFile}
          else
            printf '%s\n' ${igpu} > ${listFile}
          fi
        '';
      };
    in
    {
      inherit listFile;

      service = {
        description = "Список устройств композитора по состоянию выходов dGPU (DESK-5)";
        # Файл должен существовать до входа в сессию, иначе первый старт
        # композитора уйдёт в fallback дропина.
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        serviceConfig = {
          Type = "oneshot";
          # RemainAfterExit здесь был бы ошибкой: юнит остался бы active, и
          # повторный запуск по следующему событию udev стал бы no-op —
          # список перестал бы обновляться после первого срабатывания.
          ExecStart = "${lib.getExe refresh} ${host.gpu.discreteBusId}";
        };
      };

      # ACTION=="change" на самой карте — событие подключения/отключения кабеля
      # (add/remove относятся к появлению самих карт). Разъёмы card<N>-<имя>
      # своих событий не присылают, поэтому фильтр по KERNEL=="card[0-9]*".
      udevRules = ''
        ACTION=="change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="compositor-devices.service"
      '';

      # Fallback — встроенная GPU: если файла нет (юнит не успел или упал),
      # безопаснее стартовать без дискретной, чем не стартовать вовсе.
      envDropIn = ''
        # Сгенерировано Nix (session-hyprland, DESK-5) — не редактируйте руками.
        # Значение обновляет compositor-devices.service по событию udev.
        if [ -r ${listFile} ]; then
            export AQ_DRM_DEVICES="$(cat ${listFile})"
        else
            export AQ_DRM_DEVICES=${igpu}
        fi
      '';
    };
}
