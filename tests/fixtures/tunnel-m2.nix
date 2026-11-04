# Фиктивные значения для tests/tunnel-m2.nix (STRUCTURE 5.1): ключи выхода в ВМ, не
# настоящие секреты. Пара x25519 рабочая, потому что в тесте настоящее рукопожатие
# Reality, а адреса выхода существуют только во внутренней сети ВМ. Каталог — в
# исключениях .gitleaks.toml.
{
  realityPrivateKey = "4Ose4S6yzFQ-oR7s2OvNhV34G9MD4LzkHAjKN-3y3lc";

  client = {
    "tunnel.endpoint" = "45.77.0.10";
    "tunnel.serverKey" = "zReECkhDuZNmWqNrY5dWRuy1HAG2TmcIuW0d-g4RlnQ";
    "tunnel.serverName" = "target.test";
    "tunnel.fingerprint" = "chrome";
    "tunnel.clientId" = "11111111-2222-4333-8444-555555555555";
    "tunnel.shortId" = "0123456789abcdef";
  };
}
