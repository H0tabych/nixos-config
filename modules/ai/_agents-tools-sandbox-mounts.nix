# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Фрагмент скрипта agents-sandbox-exec: монтирования $HOME, проекта,
# каталога состояния, кэша окружения, защиты git, узлов устройств (AI-SBX-2, 7, 12, 14).
# Вставляется в тот же скрипт: переменные (`bwrap_args`, `real_home`, `state_dir`,
# `home_rw`, `no_project`, `config_dirs`, `app_paths` …) — общие с ним.
# Без проекта (`no_project`, долгоживущая песочница AI-SBX-13) — только домашний каталог,
# каталог состояния и база разрешений direnv: проектных привязок нет (ADR-48).
# Порядок привязок значим (позднее перекрывает раннее): проект, состояние, `.direnv`
# роли, база direnv, затем защита git.
''
  # AI-SBX-14: узлы устройств хоста из белого списка — после `--dev /dev` (иначе он их затрёт);
  # узла на хосте нет — пропуск.
  for d in ''${devices[@]+"''${devices[@]}"}; do
    bwrap_args+=(--dev-bind-try "/dev/$d" "/dev/$d")
  done

  # База разрешений direnv (AI-SBX-4): ищется в $XDG_DATA_HOME/direnv — кладём ro.
  direnv_data="''${XDG_DATA_HOME:-$real_home/.local/share}/direnv"

  if [ "$home_rw" -eq 1 ]; then
    bwrap_args+=(--bind "$real_home" "$real_home")
  else
    bwrap_args+=(--tmpfs "$real_home")
    for d in machine.d ai git direnv ''${config_dirs[@]+"''${config_dirs[@]}"}; do
      bwrap_args+=(--ro-bind-try "$real_home/.config/$d" "$real_home/.config/$d")
    done
  fi

  if [ "$no_project" -eq 0 ]; then
    # Кэш окружения проекта (AI-SBX-7): у роли свой, по хэшу пути проекта.
    direnv_cache="$state_dir/direnv/$(printf '%s' "$project_real" | sha256sum | cut -c1-16)"
    mkdir -p "$direnv_cache"
    bwrap_args+=(
      --bind "$project_dir" "$project_dir"
      --bind "$state_dir" "$state_dir"
      --bind "$direnv_cache" "$project_dir/.direnv"
      --ro-bind-try "$direnv_data" "$state_dir/data/direnv"
      --chdir "$cwd_real"
    )

    # AI-SBX-7: монтирования защиты git — `agents-git binds`, через файл, чтобы
    # отказ останавливал запуск (set -e).
    git_binds_file=$(mktemp)
    agents-git binds "$project_dir" "$project_real" > "$git_binds_file"
    mapfile -d "" -t git_bind_args < "$git_binds_file"
    rm -f "$git_binds_file"
    bwrap_args+=(''${git_bind_args[@]+"''${git_bind_args[@]}"})
  else
    bwrap_args+=(
      --bind "$state_dir" "$state_dir"
      --ro-bind-try "$direnv_data" "$state_dir/data/direnv"
    )
  fi
  for p in ''${app_paths[@]+"''${app_paths[@]}"}; do
    bwrap_args+=(--bind-try "$p" "$p")
  done
''
