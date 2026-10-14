# Каркас: templates · Домен: core
# Регистрация flake.templates.<имя> (DEV-3). Один шаблон — один проектный
# flake со своим flake.lock (STRUCTURE.md §4.3); сюда — только путь и описание.
_: {
  flake.templates = {
    python = {
      path = ../../templates/python;
      description = "python: интерпретатор + uv (A.5)";
    };
    rust = {
      path = ../../templates/rust;
      description = "rust: тулчейн через rust-overlay по rust-toolchain.toml (A.5)";
    };
    cpp = {
      path = ../../templates/cpp;
      description = "cpp: clang/gcc, cmake, ninja, ccache, gdb, lldb (A.5)";
    };
    sql = {
      path = ../../templates/sql;
      description = "sql: postgresql + sqlfluff + pgcli (A.5)";
    };
  };
}
