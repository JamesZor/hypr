#!/usr/bin/env bash

if [[ $# != 1 || ( $1 != apply && $1 != toggle ) ]]; then
    printf 'Usage: %s <toggle|apply>\n' "$0" >&2
    exit 2
fi

set -o pipefail
export LC_ALL=C
umask 077

# Open read-only and lock the real script, including runs via a symlink.
IFS= read -r -d '' script < <(realpath -ez -- "${BASH_SOURCE[0]}") || exit 1
exec {lock_fd}<"$script" || exit 1
flock -x "$lock_fd" || exit 1

state_home=${XDG_STATE_HOME-}
config=${XDG_CONFIG_HOME-}
data=${XDG_DATA_HOME-}
if [[ $state_home != /* ]]; then state_home=${HOME:?HOME is not set}/.local/state; fi
if [[ $config != /* ]]; then config=${HOME:?HOME is not set}/.config; fi
if [[ $data != /* ]]; then data=${HOME:?HOME is not set}/.local/share; fi
state=${state_home%/}/hypr-theme
config=${config%/}

mode=dark
# Don't strip NULs from a malformed mode file as Bash's line reader would.
if [[ -f $state/mode ]] && head -n 1 -- "$state/mode" 2>/dev/null | grep -aEx $'[ \t\r]*light[ \t\r]*' >/dev/null; then
    mode=light
fi
if [[ $1 == toggle ]]; then
    if [[ $mode == dark ]]; then mode=light; else mode=dark; fi
fi

live() {
    timeout --signal=KILL 2 "$@" {lock_fd}<&-
}

notice() {
    live hyprctl notify -1 4000 0 "theme: $1" >/dev/null 2>&1 || :
}

fail() {
    notice "could not $1 the $mode theme"
    exit 1
}

temps=()
build_dirs=()
cleanup() {
    if ((${#temps[@]})); then rm -f -- "${temps[@]}"; fi
    if ((${#build_dirs[@]})); then rmdir --ignore-fail-on-non-empty -- "${build_dirs[@]}" 2>/dev/null || :; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

stage() {
    temp=$(mktemp -- "${1%/*}/.hypr-theme.XXXXXXXXXX") || return 1
    temps+=("$temp")
}

build() {
    local file bundle dir i j
    local -a generated=(kitty.conf rofi.rasi gtk3.css gtk4.css qt6ct-colors.conf)
    local -a rendered=() staged=() originals=() published=()

    # Validate both palettes and render everything before creating any files.
    bundle=$(lua "${script%/*}/theme_gen.lua" "${script%/*}/../theme/palette.lua" "$mode") || return 1
    mapfile -td $'\x1e' rendered < <(printf '%s' "$bundle")
    ((${#rendered[@]} == ${#generated[@]} + 1)) || return 1
    eval_lua=${rendered[${#generated[@]}]}

    for file in "${generated[@]}"; do
        file=$state/$file
        if [[ -e $file || -L $file ]]; then
            [[ -f $file && ! -L $file ]] || return 1
        fi
    done
    # Remove any newly made, empty state directories if the build fails.
    dir=$state
    while [[ -n $dir && ! -e $dir && ! -L $dir ]]; do
        build_dirs+=("$dir")
        [[ $dir == */* ]] || break
        dir=${dir%/*}
    done
    mkdir -p -- "$state" || return 1

    # Stage all outputs and retain the old inodes before publishing any output.
    for i in "${!generated[@]}"; do
        file=$state/${generated[i]}
        if [[ -e $file ]]; then
            stage "$file" && ln -fT -- "$file" "$temp" || return 1
            originals+=("$temp")
        else
            originals+=("")
        fi
        stage "$file" && printf '%s' "${rendered[i]}" >"$temp" || return 1
        staged+=("$temp")
    done
    for i in "${!generated[@]}"; do
        if mv -fT -- "${staged[i]}" "$state/${generated[i]}"; then
            published+=("$i")
        else
            # Undo earlier renames if one of the commits fails.
            for j in "${published[@]}"; do
                if [[ -n ${originals[j]} ]]; then
                    mv -fT -- "${originals[j]}" "$state/${generated[j]}"
                else
                    rm -f -- "$state/${generated[j]}"
                fi
            done
            return 1
        fi
    done
    build_dirs=()
}

publish_backup() {
    # Publish the completed backup without ever overwriting an existing one.
    ln -T -- "$1" "$2" || [[ -e $2 || -L $2 ]]
}

backup() {
    local file=$1 backup=$1.pre-e6
    [[ ! -d $file ]] || return 1
    if [[ -e $backup || -L $backup || ( ! -e $file && ! -L $file ) ]]; then
        return 0
    fi
    [[ -f $file && -r $file ]] || return 1
    if head -n 1 -- "$file" | grep -aF 'hypr-theme' >/dev/null; then return 0; fi
    stage "$backup" && cat -- "$file" >"$temp" || return 1
    publish_backup "$temp" "$backup"
}

save_merged() {
    local file=$config/$1 backup=$config/$1.pre-e6
    local input='' snapshot='' needs_backup
    mkdir -p -- "${file%/*}" || return 1
    if [[ -e $file || -L $file ]]; then
        [[ -f $file ]] || return 1
        input=$file
        if [[ ! -e $backup && ! -L $backup ]]; then
            # Parse the same bytes that would be published as the backup.
            stage "$backup" && cat -- "$file" >"$temp" || return 1
            snapshot=$temp
            input=$snapshot
        fi
    fi
    stage "$file" || return 1
    needs_backup=$(lua "${script%/*}/theme_gen.lua" "${script%/*}/../theme/palette.lua" "$mode" \
        "$1" "$state" "$input" "$temp") || return 1
    if [[ -n $snapshot && $needs_backup == backup ]]; then
        publish_backup "$snapshot" "$backup" || return 1
    fi
    mv -fT -- "$temp" "$file"
}

save_kde_scheme() {
    local file=${data%/}/color-schemes/HyprTheme.colors
    mkdir -p -- "${file%/*}" && backup "$file" && stage "$file" || return 1
    lua "${script%/*}/theme_gen.lua" "${script%/*}/../theme/palette.lua" "$mode" kde-scheme >"$temp" || return 1
    mv -fT -- "$temp" "$file"
}

gtk_settings() {
    printf '%s\n' \
        '# hypr-theme: generated' \
        '[Settings]' \
        "gtk-theme-name = $gtk_theme" \
        'gtk-icon-theme-name = Adwaita' \
        'gtk-cursor-theme-name = Adwaita' \
        'gtk-font-name = IBM Plex Sans 11' \
        "gtk-application-prefer-dark-theme = $prefer_dark"
}

save() {
    local file
    local -a owned=(rofi/config.rasi gtk-3.0/settings.ini gtk-4.0/settings.ini gtk-3.0/gtk.css gtk-4.0/gtk.css)
    # qt6ct must read the quoted scheme path literally; rofi also needs one line.
    case $state in
        *,*|*\"*|*\\*|*$'\n'*|*\$*) return 1 ;;
    esac
    [[ ! -d $state/mode ]] || return 1
    for file in "${owned[@]}"; do
        file=$config/$file
        mkdir -p -- "${file%/*}" && backup "$file" && stage "$file" || return 1
        case $file in
            */rofi/config.rasi)
                printf '/* hypr-theme: generated */\n@theme "%s/rofi.rasi"\n' "$state" >"$temp" || return 1 ;;
            */settings.ini) gtk_settings >"$temp" || return 1 ;;
            */gtk-3.0/gtk.css)
                { printf '/* hypr-theme: generated */\n' && cat -- "$state/gtk3.css"; } >"$temp" || return 1 ;;
            */gtk-4.0/gtk.css)
                { printf '/* hypr-theme: generated */\n' && cat -- "$state/gtk4.css"; } >"$temp" || return 1 ;;
        esac
        mv -fT -- "$temp" "$file" || return 1
    done
    save_merged qt6ct/qt6ct.conf || return 1
    # Do not select the scheme in kdeglobals unless the scheme file was saved.
    save_kde_scheme && save_merged kdeglobals || return 1
    # Record the new mode only after the owned files have been saved.
    stage "$state/mode" && printf '%s\n' "$mode" >"$temp" && mv -fT -- "$temp" "$state/mode"
}

if [[ $mode == dark ]]; then
    gtk_theme=Adwaita-dark prefer_dark=1
else
    gtk_theme=Adwaita prefer_dark=0
fi
build || fail build
save || fail save

failed=()
gtk_failed=0
live gsettings set org.gnome.desktop.interface color-scheme "prefer-$mode" || gtk_failed=1
live gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" || gtk_failed=1
live gsettings set org.gnome.desktop.interface font-name 'IBM Plex Sans 11' || gtk_failed=1
if ((gtk_failed)); then failed+=(gtk); fi

if ! reply=$(live hyprctl eval "$eval_lua") || [[ ! $reply =~ ^[[:space:]]*ok[[:space:]]*$ ]]; then
    failed+=(hyprland)
fi
live pkill -USR1 -u "$UID" -x kitty
if (($? > 1)); then failed+=(kitty); fi

if ((${#failed[@]})); then
    names=${failed[0]}
    for component in "${failed[@]:1}"; do names+=", $component"; done
    notice "$mode saved; could not update: $names"
    exit 1
fi
if [[ $1 == toggle ]]; then
    notice "$mode (restart open GTK3 and KDE apps to update them fully)"
fi
