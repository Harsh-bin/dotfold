#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color   

sleep 0.5
echo -e "${YELLOW}🗑️ Starting dotfold Uninstaller${NC}"

sleep 0.5
if sudo test -d /var/lib/dotfold/"$(logname)"; then
    sudo rm -rf /var/lib/dotfold/"$(logname)"
    echo -e "${GREEN}✅ Deleted: /var/lib/dotfold/"$(logname)"${NC}"
else
    echo -e "ℹ️ /var/lib/dotfold/"$(logname)" directory not found"
fi
sleep 0.5

remove_alias() {
    local file=$1
    if [ -f "$file" ]; then
        if [[ "$file" == *"fish/config.fish" ]]; then
            if grep -q "alias dotfold " "$file" || grep -q "alias dotfoldtui " "$file"; then
                sed -i '/^# dotfold$/d' "$file"
                sed -i '/^alias dotfold /d' "$file"
                sed -i '/^alias dotfoldtui /d' "$file"
                echo -e "${GREEN}✅ Removed dotfold aliases from: $file${NC}"
            fi
        else
            if grep -q "alias dotfold=" "$file" || grep -q "alias dotfoldtui=" "$file"; then
                sed -i '/^# dotfold$/d' "$file"
                sed -i '/^alias dotfold=/d' "$file"
                sed -i '/^alias dotfoldtui=/d' "$file"
                echo -e "${GREEN}✅ Removed dotfold aliases from: $file${NC}"
            fi
        fi
    fi
}
echo -e "\n🔧 Cleaning up previous shell configurations if exists..."
shell_configs=(
    "$HOME/.bashrc"
    "$HOME/.zshrc"
    "$HOME/.kshrc"
    "$HOME/.tcshrc"
    "$HOME/.cshrc"
    "$HOME/.config/fish/config.fish"
)
for config in "${shell_configs[@]}"; do
    if [ -f "$config" ]; then
        remove_alias "$config"
    fi
done

sleep 0.3
echo -e "\n🔐 Removing root permissions"
if [ -f "/etc/sudoers.d/dotfold-"$(logname)"" ]; then
    sudo rm /etc/sudoers.d/dotfold-"$(logname)" && echo -e "✅ Removed sudo permissions${NC}"
else
    echo -e "ℹ️ No dotfold sudo rules found (already removed?)."
fi
sleep 0.5
echo -e "\n${GREEN}🎉 Uninstall complete! Thanks for trying dotfold.${NC}"
