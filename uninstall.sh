#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

sleep 0.5
echo -e "${YELLOW}🗑️ Starting dotfold Uninstaller${NC}"

sleep 0.5
if sudo test -d $HOME/.config/private/; then
    sudo rm -rf $HOME/.config/private/
    echo -e "${GREEN}✅ Deleted: $HOME/.config/private/ directory${NC}"
else
    echo -e "ℹ️ $HOME/.config/private/ directory not found"
fi
sleep 0.5

remove_alias() {
    local file=$1
    if [ -f "$file" ]; then
        if grep -q "alias dotfold=" "$file" || grep -q "alias dotfoldtui=" "$file"; then
                sed -i '/^# dotfold$/d' "$file"
                sed -i '/^alias dotfold=/d' "$file"
                sed -i '/^alias dotfoldtui=/d' "$file"
            fi
            echo -e "${GREEN}✅ Removed dotfold aliases from: $file${NC}"
        else
            echo -e "ℹ️ No dotfold aliases found in: $file"
        fi
}

sleep 0.5
echo -e "\n🔧 Cleaning up shell configurations..."
remove_alias ~/.bashrc  
remove_alias ~/.zshrc
sleep 0.3
echo -e "\n🔐 Removing root permissions"
if [ -f "/etc/sudoers.d/dotfold" ]; then
    sudo rm /etc/sudoers.d/dotfold && echo -e "✅ Removed sudo permissions${NC}"
else
    echo -e "ℹ️ No dotfold sudo rules found (already removed?)."
fi
sleep 0.5
echo -e "\n${GREEN}🎉 Uninstall complete! Thanks for trying dotfold.${NC}"
