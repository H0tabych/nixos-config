# Фиктивные значения для tests/tunnel-config.nix (STRUCTURE 5.1): не настоящие
# секреты, только корректный/некорректный формат. Каталог — в исключениях
# .gitleaks.toml.
{
  # Корректный формат: публичный адрес примера (RFC 5737), UUID из нулей,
  # x25519-ключ из нулевых байт в base64url (43 символа), hex shortId.
  valid = {
    "tunnel.endpoint" = "198.51.100.10";
    "tunnel.serverKey" = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    "tunnel.serverName" = "example.com";
    "tunnel.fingerprint" = "chrome";
    "tunnel.clientId" = "00000000-0000-0000-0000-000000000000";
    "tunnel.shortId" = "0123456789abcdef";
  };

  # VPN-A14: ключ не в формате base64url x25519 — ядро должно отказать.
  invalidKey = {
    "tunnel.serverKey" = "not-a-valid-reality-key";
  };

  # VPN-A14: короткий идентификатор не в hex — ядро должно отказать.
  invalidShortId = {
    "tunnel.shortId" = "zznothexchar!!!!";
  };
}
