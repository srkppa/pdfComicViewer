#!/bin/zsh

validated_install_destination() {
    local home_directory="${1:-}"
    local destination_app="${2:-}"

    [[ -n "$home_directory" && "$home_directory" = /* && "$home_directory" != "/" ]] || {
        print -u2 -- "安全でないHOMEを拒否しました: ${home_directory:-<empty>}"
        return 64
    }

    local physical_home
    physical_home="$(cd -P -- "$home_directory" 2> /dev/null && pwd -P)" || {
        print -u2 -- "安全でないHOMEを拒否しました: $home_directory"
        return 64
    }
    [[ "$physical_home" != "/" && "$home_directory" == "$physical_home" ]] || {
        print -u2 -- "安全でないHOMEを拒否しました: $home_directory"
        return 64
    }

    local expected_destination="$home_directory/Applications/PDF漫画ビューアー.app"
    [[ "$destination_app" == "$expected_destination" ]] || {
        print -u2 -- "安全でないインストール先を拒否しました: $destination_app"
        return 64
    }

    print -r -- "$destination_app"
}
