#!/bin/bash
# Removes what install.sh added (bell's own state too; Omarchy's history stays).
set -uo pipefail
omarchy plugin disable omext.bell >/dev/null 2>&1
[[ -L $HOME/.config/omarchy/plugins/omext.bell ]] && rm "$HOME/.config/omarchy/plugins/omext.bell"
menu_conf=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
[[ -f $menu_conf ]] && sed -i "\|^ *// BEGIN omext-bell\$|,\|^ *// END omext-bell\$|d" "$menu_conf"
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/omext/bell"
echo "uninstall: done"
