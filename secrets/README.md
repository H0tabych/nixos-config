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
| `secrets/hosts/sgms-laptop.yaml` | `vpnClient.credentials` | `vpn-client` |

Строки появляются по мере объявления `sops.secrets` в фичах-потребителях
(SEC-4) — начиная с `tunnel-facts` (R3.2). `vpnClient.credentials` — только
логин и пароль, двумя строками, формат `auth-user-pass` OpenVPN (R4.12: правка
R4.8 — структура `.ovpn`-профиля публична для коммерческого/штатного VPN,
SEC-2 класс C, секретом не является и сюда не попадает, см. `assets/README.md`
и `assets/vpn-client/<хост>.ovpn`). Ключ плоский
(`sops.secrets."vpnClient.credentials"`), не вложенный — sops-nix ищет ключ
плоско, вложенные структуры не поддерживает.
