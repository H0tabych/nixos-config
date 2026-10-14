# rust

Тулчейн фиксирован `rust-toolchain.toml` через `rust-overlay` (A.5). `rust-analyzer`
поставляется только отсюда, не глобально (DEV-4). Отладчик — глобальный `lldb`
(`lsp-global`, DEV-5).

```
direnv allow
cargo build
```
