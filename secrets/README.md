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
| `secrets/users/sgm.yaml` | `ai.gateway.providerKey.<id>` | `agents-keys` |

`ai.gateway.providerKey.<id>` — ключ провайдера моделей (ADR-051: шлюз облачных провайдеров
больше не обслуживает); строку, на которую указывает `my.ai.agentKeys.<агент>.sopsKey` на хосте,
фича `agents-keys` отдаёт пользователю файлом 0400 в `/run/secrets` (лаунчер читает его снаружи
песочницы и передаёт агенту значением в окружение). Имя ключа историческое: переименовать в
`ai.agents.<агент>.apiKey` через `just sops-edit` и поправить `sopsKey` на хосте можно в любой момент.
Ключ должен быть в файле ДО сборки: иначе активация sops-nix не пройдёт. Ключи доступа к шлюзу и учётные данные его
управляющего API (`ai.gateway.accessKey`, `ai.gateway.admin.*`, `ai.gateway.providerKey.<роль>`
из схемы до R9.16) в sops больше не хранятся: их генерирует служба. Старые строки после
проверки удалить (`just sops-edit`).

Строки появляются по мере объявления `sops.secrets` в фичах-потребителях
(SEC-4) — начиная с `tunnel-facts` (R3.2). `vpnClient.credentials` — только
логин и пароль, двумя строками, формат `auth-user-pass` OpenVPN (R4.12: правка
R4.8 — структура `.ovpn`-профиля публична для коммерческого/штатного VPN,
SEC-2 класс C, секретом не является и сюда не попадает, см. `assets/README.md`
и `assets/vpn-client/<хост>.ovpn`). Ключ плоский
(`sops.secrets."vpnClient.credentials"`), не вложенный — sops-nix ищет ключ
плоско, вложенные структуры не поддерживает.
