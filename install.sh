#!/bin/bash

sleep 0.5
echo "📁 Creating your personal space..."
sleep 0.5
echo -e "${RED}❌Old config files will be removed."
rm -rf $HOME/.config/private/
rm -rf $HOME/.dotfold
mkdir -p $HOME/.config/private/
sudo chown -R root:root $HOME/.config/private/
sudo chmod 700 $HOME/.config/private/
sleep 0.5
echo "✅ Created: $HOME/.config/private/"

sleep 0.5

if [ -f "dotfold.sh" ]; then
  sudo cp dotfold.sh $HOME/.config/private/
  sudo chmod +x $HOME/.config/private/dotfold.sh
  sleep 0.5
  echo -e "\n🚀 copied dotfold.sh to $HOME/.config/private/"
else
  echo "❌ Error: Couldn't find dotfold.sh in current directory!" >&2
  exit 1
fi
if [ -f "dotfoldtui.sh" ]; then
  sudo cp dotfoldtui.sh $HOME/.config/private/
  sudo chmod +x $HOME/.config/private/dotfoldtui.sh
  sleep 0.5
  echo "🚀 copied dotfoldtui.sh to $HOME/.config/private/"
else
  echo "❌ Error: Couldn't find dotfoldtui.sh in current directory!" >&2
  exit 1
fi
sleep 0.3
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
echo -e "\n🔧 Cleaning up previous shell configurations if exists..."
remove_alias ~/.bashrc  
remove_alias ~/.zshrc
sleep 0.3
add_alias() {
    local file=$1
    if [ -f "$file" ]; then
        if ! grep -q "alias dotfold=" "$file" || ! grep -q "alias dotfoldtui=" "$file"; then
            echo -e "\n# dotfold" >> "$file"
            echo "alias dotfold='sudo $HOME/.config/private/dotfold.sh'" >> "$file"
            echo "alias dotfoldtui='sudo $HOME/.config/private/dotfoldtui.sh'" >> "$file"
            echo "${GREEN}✨ Added dotfold aliases to: $file${NC}"
        else
            echo -e "${YELLOW}⏩ dotfold aliases already exist in: $file${NC}"
        fi
    fi
}
sleep 0.5
echo -e "\n🔧 Setting up shortcuts..."
  add_alias ~/.bashrc        
  add_alias ~/.zshrc   
sleep 0.5

echo -e "\n🔐 Setting up root permissions for script"
sudo touch /etc/sudoers.d/dotfold
echo "$(logname) ALL=(root) NOPASSWD: /home/$(logname)/.config/private/dotfoldtui.sh
$(logname) ALL=(root) NOPASSWD: /home/$(logname)/.config/private/dotfold.sh" | sudo tee /etc/sudoers.d/dotfold >/dev/null
echo -e "${GREEN}✅ Granted passwordless sudo access${NC}"
sleep 0.5
echo -e "\n🎉 All set! Now restart the terminal"


