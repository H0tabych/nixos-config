# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Правила nftables сетевого пространства агента (AI-SBX-5, ADR-47, R9.20). Печатает набор
# `table inet agents` для режима из аргумента; грузит его охранник (`agents-net guard`)
# внутри пространства, созданного pasta, ДО старта песочницы. Агент в пространстве прав
# не имеет (вложенное пространство пользователя у bwrap), поэтому правил не меняет.
#
# Вход — переменные окружения (списки через пробел, пустое — нет такого списка):
#   AGENTS_NET_HOST_ADDRS  адреса самого хоста и шлюз стека (IPv4 и IPv6): «службы хоста»;
#   AGENTS_NET_VPN_NETS    сети корпоративных VPN (маршруты через их линки);
#   AGENTS_NET_GW_PORT     порт шлюза на loopback хоста (только offline);
#   AGENTS_NET_DNS         адрес пересылки DNS стека;
#   AGENTS_NET_SENSITIVE   порты служб хоста без аутентификации (my.net.sensitiveLoopbackPorts, D21).
#
#   online  — сеть как у пользователя (интернет, VPN, loopback и адреса хоста, LAN); закрыты
#             только порты SENSITIVE на адресах хоста (D21: uid службы обходит туннель).
#   offline — политика drop; открыты: DNS стека, loopback пространства (там слушает только
#             проброшенный pasta порт шлюза), сети VPN. Адреса самого хоста закрываются РАНЬШЕ
#             сетей VPN: иначе через адрес интерфейса VPN открылись бы службы хоста.
{ pkgs }:
pkgs.writeShellApplication {
  name = "agents-nft";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    mode=''${1:-}
    case "$mode" in online | offline) ;; *)
      echo "usage: agents-nft <online|offline>" >&2
      exit 1
      ;;
    esac

    # Список адресов одного семейства в виде `a, b, c`; family — 4 или 6.
    pick() {
      local family=$1 out="" a
      shift
      for a in "$@"; do
        case "$a" in
          *:*) [ "$family" = 6 ] || continue ;;
          *) [ "$family" = 4 ] || continue ;;
        esac
        out="''${out:+$out, }$a"
      done
      printf '%s' "$out"
    }

    read -r -a host_addrs <<< "''${AGENTS_NET_HOST_ADDRS:-}"
    read -r -a vpn_nets <<< "''${AGENTS_NET_VPN_NETS:-}"
    read -r -a sensitive <<< "''${AGENTS_NET_SENSITIVE:-}"
    sens=$(printf '%s, ' "''${sensitive[@]}")
    sens=''${sens%, }
    # Валидность: порты и порт шлюза — только цифры (значения идут в правила).
    for p in "''${sensitive[@]}" "''${AGENTS_NET_GW_PORT:-}"; do
      [[ "$p" =~ ^[0-9]*$ ]] || { echo "agents-nft: неверный порт: $p" >&2; exit 1; }
    done

    echo "table inet agents {"
    echo "  chain output {"
    echo "    type filter hook output priority 0; policy $([ "$mode" = offline ] && echo drop || echo accept);"

    # D21: порты служб хоста закрыты на loopback и адресах хоста в обоих режимах.
    if [ -n "$sens" ]; then
      echo "    ip daddr { 127.0.0.0/8$(h=$(pick 4 "''${host_addrs[@]}"); [ -z "$h" ] || echo ", $h") } tcp dport { $sens } drop"
      echo "    ip6 daddr { ::1$(h=$(pick 6 "''${host_addrs[@]}"); [ -z "$h" ] || echo ", $h") } tcp dport { $sens } drop"
    fi

    if [ "$mode" = offline ]; then
      if [ -n "''${AGENTS_NET_DNS:-}" ]; then
        echo "    ip daddr ''${AGENTS_NET_DNS} udp dport 53 accept"
        echo "    ip daddr ''${AGENTS_NET_DNS} tcp dport { 53, 853 } accept"
      fi
      # Loopback пространства: наружу из него ведёт только проброшенный порт шлюза.
      echo "    oifname \"lo\" accept"
      h4=$(pick 4 "''${host_addrs[@]}")
      h6=$(pick 6 "''${host_addrs[@]}")
      [ -z "$h4" ] || echo "    ip daddr { $h4 } drop"
      [ -z "$h6" ] || echo "    ip6 daddr { $h6 } drop"
      n4=$(pick 4 "''${vpn_nets[@]}")
      n6=$(pick 6 "''${vpn_nets[@]}")
      [ -z "$n4" ] || echo "    ip daddr { $n4 } accept"
      [ -z "$n6" ] || echo "    ip6 daddr { $n6 } accept"
    fi
    echo "  }"
    echo "}"
  '';
}
