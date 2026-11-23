#!/usr/bin/env bash

if [[ $# != 1 || ( $1 != cycle && $1 != schedule ) ]]; then
    printf 'Usage: %s <cycle|schedule>\n' "$0" >&2
    exit 2
fi

export LC_ALL=C
exec {lock_fd}<"${BASH_SOURCE[0]}" || exit 1
flock -x "$lock_fd" || exit 1

notify() {
    timeout --foreground --signal=KILL 2 hyprctl notify -1 2000 0 "night light: $1" >/dev/null 2>&1 || :
}

fail() {
    notify "$1"
    exit 1
}

hypr_reply() {
    # Stay in the polling process group so the startup deadline covers in-flight probes too.
    reply=$(timeout --foreground --signal=KILL 2 hyprctl hyprsunset "$@" 2>/dev/null) || return
    reply=${reply#"${reply%%[![:space:]]*}"}
    reply=${reply%"${reply##*[![:space:]]}"}
}

identity_get() {
    hypr_reply identity get || return
    [[ $reply == true || $reply == false ]]
}

wait_for_sunset() (
    export -f hypr_reply identity_get
    # The child prints its own final probe reply.
    # shellcheck disable=SC2016
    timeout --signal=KILL 3 bash -c '
        until identity_get; do sleep 0.1; done
        printf "%s\n" "$reply"
    '
)

identity_get
probe_status=$?
if (( probe_status != 0 )); then
    # Only a missing IPC endpoint warrants a launch. A daemon may also still be
    # starting (from autostart or a previous press) with no socket yet.
    if [[ $probe_status == 3 ]] && ! pgrep -x -u "$EUID" -r R,S,D,T,t,I,W,P \
        --env "HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE-}" hyprsunset >/dev/null; then
        setsid -f hyprsunset {lock_fd}<&- </dev/null >/dev/null 2>&1
    fi
    reply=$(wait_for_sunset) || fail 'hyprsunset is not running'
fi

request() {
    hypr_reply "$@" || fail 'hyprsunset is not responding'
}

apply() {
    request "$@"
    [[ $reply == ok ]] || fail "$reply"
}

current_setting() {
    case $reply in
        true) setting=neutral ;;
        false)
            request temperature
            [[ $reply =~ ^[0-9]+$ ]] || fail "unexpected reply: $reply"
            # Normalize decimal digits without arithmetic (no octal or overflow).
            setting=${reply#"${reply%%[!0]*}"}
            setting=${setting:-0}
            ;;
        *) fail "unexpected reply: $reply" ;;
    esac
}

if [[ $1 == schedule ]]; then
    apply reset
    request identity get
    current_setting
    [[ $setting == neutral ]] || setting+=K
    notify "schedule ($setting)"
else
    current_setting
    # Only use arithmetic for numbers short enough to fit without overflow.
    if [[ $setting == neutral || ${#setting} -gt 4 ]] || (( setting > 4500 )); then
        next=4500
    elif (( setting > 3500 )); then
        next=3500
    elif (( setting > 2700 )); then
        next=2700
    else
        apply identity true
        notify neutral
        exit 0
    fi
    apply temperature "$next"
    notify "${next}K"
fi
