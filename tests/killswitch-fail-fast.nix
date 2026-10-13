# Проверка свойства (STRUCTURE 5.1): kill switch в M2 отвечает **отказом**, а не
# молчаливым отбрасыванием (VPN-KS-3), и делает это до общего разрешения
# локальной сети для DNS (VPN-KS-5).
#
# Зачем именно так. Разница drop/reject не видна в конфиге — она видна только по
# поведению: при drop клиент висит до своего таймаута, при reject получает
# ошибку немедленно. От этого зависит AI-GW-5/AI-A9 (уход на локальную роль за
# ≤ 10 с), поэтому свойство проверяется в ВМ, а не глазами в ревью.
#
# ВМ без реального выхода: туннель не поднимается, линка tun* нет — это и есть
# проверяемое состояние «туннель недоступен» (VPN-DNS-6, NET-8).
{
  pkgs,
  nixosModules,
  ...
}:
let
  n = nixosModules;
in
pkgs.testers.runNixOSTest {
  name = "killswitch-fail-fast";

  nodes.machine = {
    imports = [
      n.host-facts
      n.tunnel-facts
      n.killswitch
    ];

    my.host = {
      name = "killswitch-fixture";
      class = "vm";
    };

    my.tunnel = {
      mode = "m2";
      # Зона с линком — обязательна по VPN-DNS-1; здесь только чтобы состав
      # фактов был валидным, dns-resolver в этот тест не входит.
      killswitch.allowedInterfaces = [ ];
    };

    # Чтобы `timeout`/`curl` были в ВМ.
    environment.systemPackages = [
      pkgs.curl
      pkgs.dnsutils
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # VPN-KS-1: таблица существует и принадлежит kill switch'у, а не firewall —
    # владение не делится.
    ruleset = machine.succeed("nft list table inet killswitch")

    # VPN-KS-5: отказ для DNS стоит ВЫШЕ общего разрешения локальной сети.
    # Это именно про порядок: поменяй правила местами — и запрос к порту 53
    # внутри 192.168/16 ушёл бы на домашний маршрутизатор.
    dns_pos = ruleset.index("dport 53")
    lan_pos = ruleset.index("192.168.0.0/16")
    assert dns_pos < lan_pos, \
        "VPN-KS-5: правило отказа для DNS должно стоять до разрешения локальной сети"

    # VPN-KS-3: отказ, а не молчаливое отбрасывание. Различие видно только по
    # поведению: при reject ядро получает ICMP admin-prohibited и curl не может
    # соединиться (код 7); при drop пакеты уходят в тишину и curl упирается в
    # --max-time (код 28). Туннеля в ВМ нет, линка tun* нет — это и есть
    # состояние «туннель недоступен» (NET-8, VPN-DNS-6).
    rc, _ = machine.execute("timeout 30 curl -s -o /dev/null --max-time 10 http://192.0.2.1/")
    assert rc == 7, (
        f"VPN-KS-3: ожидался быстрый отказ (curl 7 — соединиться не удалось), получено {rc}. "
        "Код 28 означал бы drop вместо reject, код 124 — что истёк внешний timeout"
    )

    # VPN-KS-3, количественно: отказ приходит за ≤ 2 с, а не по таймауту клиента.
    elapsed = machine.succeed(
        "start=$(date +%s); "
        "timeout 30 dig +tries=1 +time=10 @192.168.1.1 example.com >/dev/null 2>&1 || true; "
        "echo $(( $(date +%s) - start ))"
    )
    assert int(elapsed.strip()) <= 2, \
        f"VPN-KS-3: DNS-запрос мимо туннеля должен отказываться за ≤ 2 с, занял {elapsed.strip()} с"
  '';
}
