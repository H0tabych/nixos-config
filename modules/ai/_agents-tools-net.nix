# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Сеть агентов v3 (AI-SBX-5, ADR-47, R9.20). Единая точка истины для лаунчера
# (agents-tools.nix) и теста (tests/agent-network.nix) — проверяется ровно этот код.
#
# Песочница работает в своём пространстве имён пользователя и сети, созданном `pasta`:
# соединения агента выходят СОКЕТАМИ ХОСТА — по его маршрутам (туннель, корпоративные VPN,
# переключатель маршрута) и через его резолвер, любым протоколом. Правила nftables грузит
# охранник (`guard`) внутри пространства до старта песочницы; песочница (bwrap) вложена в
# своё пространство пользователя и прав над сетевым не имеет. Сбой любого шага — команда не
# запускается (AI-SBX-6).
#
#   agents-net mode <проект>                                 → online | offline
#   agents-net run <режим> <порт шлюза|-> [порт...] -- <команда>
#       на хосте: снимает адреса хоста и сети VPN, поднимает pasta, внутри — guard;
#       порты — явная публикация на 127.0.0.1 хоста (веб-интерфейс агента);
#   agents-net guard -- <команда>                            (внутри пространства)
#
# Режим по умолчанию — online; offline задают корни `cloud = "deny"` в `roots.toml`
# (владелец, AI-SEC-6) либо флаг запуска. Проект политику не меняет (AI-SEC-5).
# Выяснено в ВМ (2026-11-12): pasta отображает пользователя в root пространства с полными
# правами; `-T all` не поддерживается — для online действует `-T auto` (loopback хоста,
# только 127.0.0.1, службы, запущенные позже, тоже видны), для offline — явный `-T <порт>`.
{
  pkgs,
  lib,
  nftTool,
  # Линки корпоративных VPN (my.tunnel.dns.scopedZones.*.link): их маршруты — «сети VPN».
  vpnLinks ? [ ],
  # Порты служб хоста, закрытые агенту (my.net.sensitiveLoopbackPorts, D21).
  sensitivePorts ? [ ],
}:
pkgs.writeShellApplication {
  name = "agents-net";
  runtimeInputs = [
    pkgs.passt
    pkgs.nftables
    pkgs.iproute2
    pkgs.yq-go
    pkgs.jq
    pkgs.coreutils
    pkgs.gnugrep
    nftTool
  ];
  text = ''
    dns_forward=169.254.1.1
    vpn_links="${lib.concatStringsSep " " vpnLinks}"
    sensitive="${lib.concatMapStringsSep " " toString sensitivePorts}"

    fail() {
      echo "agents-net: $*" >&2
      exit 1
    }

    # Режим по умолчанию. Без roots.toml — online (облако разрешено, AI-SEC-6); файл есть,
    # но не разобран — отказ, а не молчаливый online: ошибка в нём открыла бы закрытое.
    mode_of() {
      local project=$1 roots=''${AGENTS_ROOTS_FILE:-$HOME/.config/ai/roots.toml} real rows path cloud root
      real=$(realpath -- "$project")
      if [ -e "$roots" ]; then
        rows=$(yq -p toml -o json -I0 '.root[]? | [(.path // ""), (.cloud // "")]' "$roots" | jq -r '@tsv') ||
          fail "$roots не разобран (TOML)"
        while IFS=$'\t' read -r path cloud; do
          [ -n "$path$cloud" ] || continue
          [ -n "$path" ] || fail "$roots: у записи [[root]] нет path"
          case "$cloud" in deny | allow) ;; *) fail "$roots: cloud = \"$cloud\" у $path (допустимо deny | allow)" ;; esac
          [ "$cloud" = deny ] || continue
          root=$(realpath -m -- "''${path/#\~/$HOME}")
          [ "$root" = "/" ] && continue
          case "$real" in "$root" | "$root"/*) echo offline; return ;; esac
        done <<< "$rows"
      fi
      echo online
    }

    # Адреса самого хоста (глобальные): службы хоста для правил offline (AI-SBX-5).
    host_addrs() {
      { ip -j addr show; ip -j -6 addr show; } | jq -r '.[].addr_info[] | select(.scope == "global" or .scope == "site") | .local' | sort -u | tr '\n' ' '
    }

    # Сети VPN: маршруты через линки корпоративных VPN на момент запуска. VPN, поднятый
    # позже, до перезапуска агента в offline не виден (ADR-47, «Риски»).
    vpn_nets() {
      local l
      for l in $vpn_links; do
        { ip -j route show dev "$l"; ip -j -6 route show dev "$l"; } 2>/dev/null |
          jq -r '.[].dst | select(. != "default" and (startswith("fe80:") | not))' || true
      done | sort -u | tr '\n' ' '
    }

    cmd=''${1:-}
    [ "$#" -gt 0 ] && shift
    case "$cmd" in
      mode)
        [ "$#" -eq 1 ] || fail "usage: agents-net mode <проект>"
        mode_of "$1"
        ;;

      run)
        [ "$#" -ge 3 ] || fail "usage: agents-net run <режим> <порт шлюза|-> [порт...] -- <команда>"
        mode=$1 gw=$2
        shift 2
        case "$mode" in online | offline) ;; *) fail "режим: online | offline" ;; esac
        publish=()
        while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
          [[ "$1" =~ ^[0-9]+$ ]] || fail "неверный порт публикации: $1"
          publish+=("$1")
          shift
        done
        [ "''${1:-}" = "--" ] && shift
        [ "$#" -gt 0 ] || fail "нет команды"
        [ "$gw" = "-" ] && gw=""

        # Автопубликации портов агента на хост нет: только явные `127.0.0.1/<порт>`
        # (pasta не сочетает `none` с перечнем портов, поэтому `none` — лишь без публикаций).
        args=(-f --config-net --dns-forward "$dns_forward" -u none)
        if [ "''${#publish[@]}" -eq 0 ]; then
          args+=(-t none)
        else
          for p in "''${publish[@]}"; do args+=(-t "127.0.0.1/$p"); done
          args+=(--host-lo-to-ns-lo)
        fi
        if [ "$mode" = offline ]; then
          # Наружу в offline — только порт шлюза; адрес шлюза стека на хост не отображается.
          args+=(--no-map-gw -T "''${gw:-none}" -U none)
        fi

        export AGENTS_NET_MODE=$mode AGENTS_NET_GW_PORT=$gw AGENTS_NET_SENSITIVE=$sensitive
        AGENTS_NET_HOST_ADDRS=$(host_addrs)
        AGENTS_NET_VPN_NETS=$(vpn_nets)
        AGENTS_HOST_UID=$(id -u)
        AGENTS_HOST_GID=$(id -g)
        export AGENTS_NET_HOST_ADDRS AGENTS_NET_VPN_NETS AGENTS_HOST_UID AGENTS_HOST_GID
        # pasta сам не вернёт управление, пока команда жива; ненулевой код — отказ запуска.
        exec pasta "''${args[@]}" -- "$0" guard -- "$@"
        ;;

      guard)
        [ "''${1:-}" = "--" ] && shift
        [ "$#" -gt 0 ] || fail "нет команды"
        mode=''${AGENTS_NET_MODE:-}
        case "$mode" in online | offline) ;; *) fail "guard запускается только из run" ;; esac
        # Шлюз стека (pasta отображает его на хост) — тоже «адрес хоста».
        gateway=$(ip -j route show default | jq -r '.[0].gateway // empty')
        export AGENTS_NET_HOST_ADDRS="''${AGENTS_NET_HOST_ADDRS:-} $gateway" AGENTS_NET_DNS=$dns_forward
        rules=$(mktemp)
        agents-nft "$mode" > "$rules" || fail "не сформированы правила nftables"
        nft -f "$rules" || fail "правила nftables не загружены (AI-SBX-6)"
        rm -f "$rules"
        nft list table inet agents > /dev/null || fail "таблица inet agents отсутствует после загрузки"

        # Свой resolv.conf песочницы: единственный сервер — пересылка DNS стека; поисковые
        # домены хоста (короткие имена корпоративных зон) переносим, кроме пустого `.`.
        resolv=$(mktemp "''${XDG_RUNTIME_DIR:-/tmp}/agents-resolv.XXXXXX")
        { echo "nameserver $dns_forward"; echo "options edns0"; grep -E '^search ' /etc/resolv.conf 2> /dev/null | grep -vE '^search \.?$' || true; } > "$resolv"
        export AGENTS_RESOLV_CONF=$resolv AGENTS_NET_GUARDED=1
        unset AGENTS_NET_MODE AGENTS_NET_GW_PORT AGENTS_NET_SENSITIVE AGENTS_NET_HOST_ADDRS AGENTS_NET_VPN_NETS AGENTS_NET_DNS
        exec "$@"
        ;;

      *)
        fail "usage: agents-net <mode|run|guard> ..."
        ;;
    esac
  '';
}
