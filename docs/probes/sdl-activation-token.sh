#!/bin/zsh
# sdl-activation-token.sh — does SDL 3.4.16 (the Linux image's tag) honour an XDG activation token
# in SDL_RaiseWindow? (small-items item 9, SM-B / SN-L.) Usage: zsh sdl-activation-token.sh
# Recorded 2026-10-22: the token env var XDG_ACTIVATION_TOKEN is read in exactly three places:
#   SDL_waylandwindow.c:2146  at the INITIAL show of a new window (xdg_activation_v1_activate), then unset
#   SDL_waylandutil.c:68      Wayland_GetActivationTokenForExport (SDL_OpenURL / window export), then unset
#   SDL_sysurl.c:85           SDL_OpenURL's child environment
# Wayland_RaiseWindow (SDL_waylandwindow.c:2374) -> Wayland_activate_window REQUESTS A NEW token from the
# compositor with the last input serial; it never reads the environment. X11 (SDL_x11window.c): no activation
# or DESKTOP_STARTUP_ID reference. So a forwarded token cannot be applied to an existing window through SDL.
d=$(mktemp -d) && git clone -q --depth 1 --branch release-3.4.16 https://github.com/libsdl-org/SDL.git $d/sdl || exit 1
grep -rn -i "XDG_ACTIVATION_TOKEN\|DESKTOP_STARTUP" $d/sdl/src $d/sdl/include
sed -n '/^void Wayland_RaiseWindow/,/^}/p' $d/sdl/src/video/wayland/SDL_waylandwindow.c
