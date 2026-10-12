# Реестр секретов

Таблица «файл → ключ → фича-потребитель»; значений здесь нет (STR-10, C9).
Имена ключей нейтральные: `<домен>.<роль>` (SEC-3).

| Файл | Ключ | Фича-потребитель |
|---|---|---|
| `secrets/common.yaml` | `tunnel.endpoint` | `tunnel-xray` |
| `secrets/common.yaml` | `tunnel.serverKey` | `tunnel-xray` |
| `secrets/common.yaml` | `tunnel.serverName` | `tunnel-xray` |
| `secrets/common.yaml` | `tunnel.fingerprint` | `tunnel-xray` |
| `secrets/hosts/sgms-laptop.yaml` | `tunnel.clientId` | `tunnel-xray` |
| `secrets/hosts/sgms-laptop.yaml` | `tunnel.shortId` | `tunnel-xray` |
| `secrets/hosts/sgms-laptop.yaml` | `vpnClient.config` | `vpn-client` |

Строки появляются по мере объявления `sops.secrets` в фичах-потребителях
(SEC-4) — начиная с `tunnel-facts` (R3.2). `vpnClient.config` — весь
`.ovpn`-профиль (сертификаты, ключи, auth) одним секретом (R4.8); ключ плоский
(`sops.secrets."vpnClient.config"`), не вложенный (`vpnClient: config:`) —
sops-nix ищет ключ плоско, вложенные структуры не поддерживает.
