#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color   

sleep 0.5
echo "📁 Creating your personal space..."
sleep 0.5
echo -e "${RED}❌ Old config files will be removed.${NC}"
sudo rm -rf $HOME/.config/private/   # Previous version folders
sudo rm -rf $HOME/.dotfold
if sudo test -d /var/lib/dotfold/"$(logname)"; then
    sudo rm -rf /var/lib/dotfold/"$(logname)"
    echo -e "${GREEN}✅ Deleted: /var/lib/dotfold/"$(logname)"${NC}"
fi

sudo mkdir -p /var/lib/dotfold/"$(logname)"
sudo chown -R root:root /var/lib/dotfold/"$(logname)"
sudo chmod 700 /var/lib/dotfold/"$(logname)"
sleep 0.5
echo "✅ Created: /var/lib/dotfold/$(logname)"

if [ -f "dotfold.sh" ]; then
  sudo cp dotfold.sh /var/lib/dotfold/"$(logname)"
  sudo chmod +x /var/lib/dotfold/"$(logname)"/dotfold.sh
  sleep 0.5
  echo -e "\n🚀 Copied dotfold.sh to /var/lib/dotfold/$(logname)"
else
  echo "❌ Error: Couldn't find dotfold.sh in current directory!" >&2
  exit 1
fi

if [ -f "dotfoldtui.sh" ]; then
  sudo cp dotfoldtui.sh /var/lib/dotfold/"$(logname)"
  sudo chmod +x /var/lib/dotfold/"$(logname)"/dotfoldtui.sh
  sleep 0.5
  echo "🚀 Copied dotfoldtui.sh to /var/lib/dotfold/$(logname)"
else
  echo "❌ Error: Couldn't find dotfoldtui.sh in current directory!" >&2
  exit 1
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

add_alias() {
    local file=$1
    if [ -f "$file" ]; then
        if [[ "$file" == *"fish/config.fish" ]]; then
            if ! grep -q "alias dotfold " "$file"; then
                echo -e "\n# dotfold" >> "$file"
                echo "alias dotfold \"sudo /var/lib/dotfold/$(logname)/dotfold.sh\"" >> "$file"
                echo "alias dotfoldtui \"sudo /var/lib/dotfold/$(logname)/dotfoldtui.sh\"" >> "$file"
                echo -e "${GREEN}✨ Added aliases to: $file${NC}"
            fi
        else
            if ! grep -q "alias dotfold=" "$file"; then
                echo -e "\n# dotfold" >> "$file"
                echo "alias dotfold='sudo /var/lib/dotfold/$(logname)/dotfold.sh'" >> "$file"
                echo "alias dotfoldtui='sudo /var/lib/dotfold/$(logname)/dotfoldtui.sh'" >> "$file"
                echo -e "${GREEN}✨ Added aliases to: $file${NC}"
            fi
        fi
    fi
}


sleep 0.5
echo -e "\n🔧 Setting up shortcuts..."
for config in "${shell_configs[@]}"; do
    if [ -f "$config" ]; then
        add_alias "$config"
    fi
done

sleep 0.5
echo -e "\n🔐 Setting up root permissions for script"
sudo touch /etc/sudoers.d/dotfold-"$(logname)"
echo "$(logname) ALL=(root) NOPASSWD: /var/lib/dotfold/$(logname)/dotfold.sh
$(logname) ALL=(root) NOPASSWD: /var/lib/dotfold/$(logname)/dotfoldtui.sh" | sudo tee /etc/sudoers.d/dotfold-"$(logname)" >/dev/null
sudo chown root:root /etc/sudoers.d/dotfold-"$(logname)"
sudo chmod 0440 /etc/sudoers.d/dotfold-"$(logname)"
echo -e "${GREEN}✅ Granted passwordless sudo access${NC}"

sleep 0.5
echo -e "\n🎉 All set! Now restart your terminal and use either:"
echo -e "  - 'dotfold' for the CLI version"
echo -e "  - 'dotfoldtui' for the TUI version\n"