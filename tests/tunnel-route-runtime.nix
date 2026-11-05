# Проверка свойства (STRUCTURE 5.1): маршрут туннеля во время работы (NET-13, ADR-40)
# — VPN-A16 и M2-10 гейта 7.3. Стенд, топология, фикстуры и настоящее рукопожатие
# Reality — те же, что в tests/tunnel-m2.nix: этот файл подключает к ним `route-switch`
# и подставляет свой сценарий через аргумент `variant` (так сделаны и контрольные
# прогоны из docs/runbook/tunnel.md). Собственной топологии здесь нет — две копии
# разошлись бы.
#
# Не проверяется в ВМ (на машине, docs/runbook/tunnel.md, процедура 8): запрос пароля
# агентом polkit при каждом переключении, гибернация, перезагрузка → tunnel и
# `nix build` с подстановкой из кэша. Здесь: без агента неадминистратор переключить не
# может, а текст правила — auth_admin без удержания.
{
  pkgs,
  lib,
  inputs,
  nixosModules,
  ...
}:
let
  blockedDomain = "blocked.test";
  # Адреса стенда — те же константы, что в tests/tunnel-m2.nix.
  webIp = "93.184.216.34";
  clientIp = "10.0.0.2";
  relayIp = (import ./fixtures/tunnel-m2.nix).client."tunnel.endpoint";
in
import ./tunnel-m2.nix {
  inherit
    pkgs
    lib
    inputs
    nixosModules
    ;
  variant = {
    name = "route";

    # Домен, который политика разрешает только через туннель (VPN-RTE-9).
    tunnel.policy.proxy = [ "domain:${blockedDomain}" ];

    client =
      { ... }:
      {
        imports = [ nixosModules.route-switch ];
        security.polkit.enable = true;
        users.users.alice.isNormalUser = true;
      };

    script = ''
      import time

      STATE = "/run/tunnel/route"
      BLOCKED = "curl -sS --max-time 5 --resolve ${blockedDomain}:80:${webIp} http://${blockedDomain}/"
      DROPIN = "/run/systemd/system/tunnel-xray.service.d"


      def switch(route: str, expect: str) -> None:
          """Переключает маршрут и ждёт рабочий трафик не дольше 5 с (VPN-A16)."""
          t0 = time.monotonic()
          client.succeed(f"systemctl start route-switch@{route}.service")
          client.wait_until_succeeds(f"curl -sS --max-time 2 {WEB} | grep -qx {expect}", timeout=5)
          took = time.monotonic() - t0
          assert took <= 5, f"переключение на {route} заняло {took:.1f} с"


      def client_packets(filter_: str) -> str:
          """Пакеты клиента в захвате провайдера; захват останавливается."""
          isp.succeed("systemctl stop capture")
          return isp.succeed(f"tcpdump -nn -r /tmp/capture.pcap 'ip and ({filter_})'").strip()


      wait_tunnel()

      with subtest("VPN-MOD-9: нет файла состояния — маршрут tunnel"):
          client.fail(f"test -e {STATE}")
          assert fetch() == RELAY_IP
          assert client.succeed(BLOCKED).strip() == RELAY_IP

      with subtest("VPN-MOD-10: неадминистратор без агента не переключит; неверный маршрут отклонён"):
          client.fail("su -s /bin/sh alice -c 'systemctl start route-switch@direct.service'")
          client.fail(f"test -e {STATE}")
          client.fail("systemctl start route-switch@evil.service")
          client.fail(f"test -e {STATE}")

      with subtest("VPN-MOD-10: правило polkit — auth_admin без удержания"):
          rules = client.succeed("cat /etc/polkit-1/rules.d/*.rules")
          assert "AUTH_ADMIN" in rules and "AUTH_ADMIN_KEEP" not in rules, rules
          assert "route-switch@(tunnel|direct)" in rules, rules

      with subtest("VPN-A16: tunnel → direct ≤ 5 с, соединения с выходом нет"):
          switch("direct", CLIENT_IP)
          capture_start()
          assert fetch("http://${webIp}/") == CLIENT_IP
          assert fetch("http://site.ru/") == CLIENT_IP
          assert client.succeed(f"cat {STATE}").strip() == "direct"
          journal = client.succeed("journalctl -u 'route-switch@direct.service' --no-pager")
          assert "маршрут → direct" in journal, journal
          # Новое соединение — это SYN: RST на хвосты прежних соединений законны.
          hits = client_packets("src host ${clientIp} and dst host ${relayIp} and tcp[tcpflags] & tcp-syn != 0")
          assert hits == "", f"в direct клиент открыл соединение с выходом:\n{hits}"

      with subtest("VPN-RTE-9: домен policy.proxy в direct — быстрый отказ"):
          t0 = time.monotonic()
          client.fail(BLOCKED)
          assert time.monotonic() - t0 < 4, "отказ должен быть быстрым, а не по таймауту"

      with subtest("M2-10, VPN-KS-10: kill switch на месте, петли нет, остановка клиента — отказ"):
          client.succeed("nft list table inet killswitch")
          client.succeed(f"ip -4 route show table 7777 | grep -q 'default dev {TUN}'")
          client.succeed("systemctl stop tunnel-xray.service")
          capture_start()
          client.fail(f"curl -sS --max-time 5 {WEB}")
          leaked = client_packets("src host ${clientIp} and dst host ${webIp}")
          assert leaked == "", f"при остановленном клиенте трафик ушёл мимо:\n{leaked}"
          client.succeed("systemctl start tunnel-xray.service")
          client.wait_until_succeeds(f"curl -sS --max-time 5 {WEB} | grep -qx {CLIENT_IP}", timeout=30)

      with subtest("VPN-A16: выбор переживает активацию"):
          client.succeed("/run/current-system/bin/switch-to-configuration test")
          client.wait_for_unit("tunnel-xray.service")
          client.wait_until_succeeds(f"curl -sS --max-time 5 {WEB} | grep -qx {CLIENT_IP}", timeout=30)
          assert client.succeed(f"cat {STATE}").strip() == "direct"

      with subtest("VPN-MOD-11: в direct клиент стартует без секретов, в tunnel — отказ старта"):
          client.succeed(f"mkdir -p {DROPIN}")
          client.succeed(f"printf '[Service]\\nLoadCredential=\\n' > {DROPIN}/no-credential.conf")
          client.succeed("systemctl daemon-reload")
          client.succeed("systemctl start route-switch@direct.service")
          client.wait_until_succeeds(f"curl -sS --max-time 5 {WEB} | grep -qx {CLIENT_IP}", timeout=30)
          client.fail("systemctl start route-switch@tunnel.service")
          unit_log = client.succeed("journalctl -u tunnel-xray.service --no-pager")
          assert "ключи sops" in unit_log, unit_log
          client.succeed(f"rm -rf {DROPIN}")
          client.succeed("systemctl daemon-reload")
          client.succeed("systemctl reset-failed tunnel-xray.service")

      with subtest("VPN-MOD-9: любое значение, кроме direct, — tunnel"):
          client.succeed(f"echo garbage > {STATE}")
          client.succeed("systemctl restart tunnel-xray.service")
          wait_tunnel()

      with subtest("VPN-A16: direct → tunnel ≤ 5 с"):
          client.succeed("systemctl start route-switch@direct.service")
          switch("tunnel", RELAY_IP)
          assert client.succeed(BLOCKED).strip() == RELAY_IP
    '';
  };
}
