#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

sleep 0.5

echo -e "${YELLOW}🗑️ Starting dotfold Uninstaller${NC}"

sleep 0.5
if [ -d ~/.dotfold ]; then
    rm -rf ~/.dotfold
    echo -e "${GREEN}✅ Deleted: ~/.dotfold directory${NC}"
else
    echo -e "ℹ️ ~/.dotfold directory not found"
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
    fi
}

sleep 0.5
echo -e "\n🔧 Cleaning up shell configurations..."
remove_alias ~/.bashrc  
remove_alias ~/.zshrc
sleep 0.5
echo -e "\n${GREEN}🎉 Uninstall complete! Thanks for trying dotfold.${NC}"
