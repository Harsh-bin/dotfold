#!/bin/bash

sleep 0.5

echo "📁 Creating your personal space..."
sleep 0.5
mkdir -p ~/.dotfold
sleep 0.5
echo "  ✅ Created: ~/.dotfold/"

sleep 0.5

if [ -f "dotfold.sh" ]; then
  cp dotfold.sh ~/.dotfold/
  chmod +x ~/.dotfold/dotfold.sh
  sleep 0.5
  echo -e "\n🚀 copied dotfold.sh to ~/.dotfold/"
else
  echo "❌ Error: Couldn't find dotfold.sh in current directory!" >&2
  exit 1
fi
if [ -f "dotfoldtui.sh" ]; then
  cp dotfoldtui.sh ~/.dotfold/
  chmod +x ~/.dotfold/dotfoldtui.sh
  sleep 0.5
  echo "🚀 copied dotfoldtui.sh to ~/.dotfold/"
else
  echo "❌ Error: Couldn't find dotfoldtui.sh in current directory!" >&2
  exit 1
fi

add_alias() {
    local file=$1
    if [ -f "$file" ]; then
        if ! grep -q "alias dotfold=" "$file" || ! grep -q "alias dotfoldtui=" "$file"; then
            echo -e "\n# dotfold" >> "$file"
            echo "alias dotfold='~/.dotfold/dotfold.sh'" >> "$file"
            echo "alias dotfoldtui='~/.dotfold/dotfoldtui.sh'" >> "$file"
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
echo -e "\n🎉 All set! Now restart the terminal"


