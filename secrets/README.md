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
| `secrets/users/sgm.yaml` | `ai.gateway.accessKey` | `llm-gateway` |
| `secrets/users/sgm.yaml` | `ai.gateway.admin.user` | `llm-gateway` |
| `secrets/users/sgm.yaml` | `ai.gateway.admin.pass` | `llm-gateway` |
| `secrets/users/sgm.yaml` | `ai.gateway.providerKey.<роль>` | `llm-gateway` |

`ai.gateway.providerKey.<роль>` — по одной строке на каждую роль, заданную в
`my.ai.gateway.cloudRoles` на хосте (`cost-autonomous`/`strong-autonomous`/
`experimental`, раздел 4 AI_SUBSYSTEM.md); имя роли — не вендор (SEC-3: это
часть публичного контракта ролей, AI-ROLE-1), даже если несколько ролей
используют один и тот же вендорский ключ — значение просто повторяется.
Без хотя бы одной настроенной облачной роли эта строка не появляется: по
умолчанию `cloudRoles = { }` (R8.5, AI-A14/AI-GW-9 — юнит не падает без
облачных ключей). `ai.gateway.accessKey`/`admin.*` — обязательны всегда, без
них юнит `llm-gateway` не поднимается вовсе.

Строки появляются по мере объявления `sops.secrets` в фичах-потребителях
(SEC-4) — начиная с `tunnel-facts` (R3.2). `vpnClient.credentials` — только
логин и пароль, двумя строками, формат `auth-user-pass` OpenVPN (R4.12: правка
R4.8 — структура `.ovpn`-профиля публична для коммерческого/штатного VPN,
SEC-2 класс C, секретом не является и сюда не попадает, см. `assets/README.md`
и `assets/vpn-client/<хост>.ovpn`). Ключ плоский
(`sops.secrets."vpnClient.credentials"`), не вложенный — sops-nix ищет ключ
плоско, вложенные структуры не поддерживает.
