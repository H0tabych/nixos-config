# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Фрагмент скрипта agents-sandbox-exec: монтирования $HOME, проекта,
# каталога состояния, кэша окружения, защиты git (AI-SBX-2, AI-SBX-7, AI-SBX-12, AI-SBX-13).
# Вставляется в тот же скрипт: переменные (`bwrap_args`, `real_home`, `state_dir`,
# `home_rw`, `private_*`, `config_dirs`, `app_paths` …) — общие с ним.
''
  # База разрешений direnv (AI-SBX-4): ищется в $XDG_DATA_HOME/direnv — кладём ro.
  direnv_data="''${XDG_DATA_HOME:-$real_home/.local/share}/direnv"

  if [ "$home_rw" -eq 1 ]; then
    bwrap_args+=(--bind "$real_home" "$real_home")
    # Подмена общего с хостом состояния своим (state-dir): после bind $HOME.
    for rel in ''${private_dirs[@]+"''${private_dirs[@]}"}; do
      src="$state_dir/private/$(printf '%s' "$rel" | tr '/' '_')"
      mkdir -p "$src"
      bwrap_args+=(--bind "$src" "$real_home/$rel")
    done
    for rel in ''${private_files[@]+"''${private_files[@]}"}; do
      src="$state_dir/private/$(printf '%s' "$rel" | tr '/' '_')"
      mkdir -p "$state_dir/private"
      [ -e "$src" ] || : > "$src"
      bwrap_args+=(--bind "$src" "$real_home/$rel")
    done
  else
    [ "''${#private_dirs[@]}" -eq 0 ] && [ "''${#private_files[@]}" -eq 0 ] || usage
    bwrap_args+=(--tmpfs "$real_home")
    for d in machine.d ai git direnv ''${config_dirs[@]+"''${config_dirs[@]}"}; do
      bwrap_args+=(--ro-bind-try "$real_home/.config/$d" "$real_home/.config/$d")
    done
  fi

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
  bwrap_args+=(''${git_bind_args[@]+"''${git_bind_args[@]}"})
  for p in ''${app_paths[@]+"''${app_paths[@]}"}; do
    bwrap_args+=(--bind-try "$p" "$p")
  done
''
