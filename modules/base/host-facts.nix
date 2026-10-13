# Фича: host-facts · Слот: — · Домен: base · Классы: N · Для: всех фич и хостов, читающих my.host.*
# Контракт: ARCH-4, HOST-1. Объявляет схему my.host.* (факты железа и класс хоста) без значений.
# gpu.compute/gpu.computeCapability — по стыку с AI_SUBSYSTEM (AI-INF-3, HOST-3).
# Зависимости: —
_: {
  flake.modules.nixos.host-facts =
    { lib, ... }:
    {
      options.my.host = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Имя хоста (HOST-1).";
        };
        class = lib.mkOption {
          type = lib.types.enum [
            "laptop"
            "workstation"
            "server"
            "vm"
          ];
          description = "Класс хоста (5.3 Архитектуры).";
        };
        stateVersion = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Версия состояния — параметр хоста (HOST-5).";
        };
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Пользователи хоста (USER-2).";
        };

        gpu = {
          integratedBusId = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "PCI-шина встроенного GPU.";
          };
          discreteBusId = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "PCI-шина дискретного GPU.";
          };
          vramGiB = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            description = "Объём видеопамяти дискретного GPU, ГБ.";
          };
          compute = lib.mkOption {
            type = lib.types.enum [
              "cuda"
              "vulkan"
              "none"
            ];
            default = "none";
            description = "Вычислительный бэкенд GPU (AI-INF-3).";
          };
          computeCapability = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Compute Capability GPU, например \"7.5\".";
          };
        };

        battery = {
          present = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Есть ли батарея у хоста.";
          };
          capacityWh = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            description = "Ёмкость батареи, Вт·ч.";
          };
        };

        inputDevices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Встроенные устройства ввода (раздел 7.1 docs/hosts).";
        };

        keyboardLayout = lib.mkOption {
          type = lib.types.str;
          default = "us";
          description = "Раскладка клавиатуры рабочего стола, формат xkb (DESK-7) — единый источник для X11 и машинного слоя.";
        };

        outputs = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Метка вывода.";
                };
                connector = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Имя коннектора компоситора (напр. eDP-1), подтверждённое на хосте. null — коннектор не подтверждён, правило монитора не привязывается к конкретному выходу.";
                };
                width = lib.mkOption { type = lib.types.ints.positive; };
                height = lib.mkOption { type = lib.types.ints.positive; };
                refreshRate = lib.mkOption { type = lib.types.ints.positive; };
                internal = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
              };
            }
          );
          default = [ ];
          description = "Мониторы хоста (DESK-8).";
        };

        disk.device = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Устройство диска для декларативной разметки (STO-1).";
        };

        # Размер swap-файла — аппаратное различие (зависит от объёма RAM),
        # поэтому факт хоста, а не константа в фиче (HOST-3, STO-4).
        swap.sizeMiB = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Размер swap-файла в МиБ, ≥ объёма RAM (STO-4).";
        };

        resume.offset = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Смещение swap-файла для гибернации (STO-5).";
        };
      };
    };
}
