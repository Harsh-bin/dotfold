# ▪️📂 dotfold
A small, 🔐 password-protected TUI + CLI tool that hides folders by prefixing them with "." and securely stores folder metadata using OpenSSL and a SHA-256 hashed password.
### 🔍 Preview
![](/preview/dotfold.png)
--
![](/preview/dotfold.gif)
--
# 🔵 CLI Usages
### Hiding folders
1. Type full path of folder
   ```
   dotfold hide "/path/to/folder"
   ```
2. Or, open a terminal in the folder’s parent directory and provide just the folder name.
   ```
   dotfold hide "folder name" 
   ```
## 💡Tips
- Move your folder to a complex path like /folder/folder3/folder2/.folder/MY-folder — somewhere even you might have trouble finding it.
- Exclude those folders from being indexed by tools like tracker3 and locate
- Now you’ve got the perfect hidden folder setup.
 ----
### Other commnands 
   ```
   dotfold show hidden   # shows all hidden folders 
   ```
   ```
   dotfold unhide   # lets you unhide a folder
   ```
   ```
   dotfold change passwd  # Changes your password
  ```

### 🛠️ **Setup**  
  📦 Install Dependencies
   # For Linux:
### ubuntu/debian
   ```
   sudo mkdir -p /etc/apt/keyrings
   curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
   echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
   sudo apt update && sudo apt install gum fzf openssl
   ```
### Archlinux
   ```
   sudo pacman -S gum fzf openssl # Arch based system
   ```
### Fedora
   ```
   sudo dnf install gum openssl fzf
   ```

   📢 For any other distro: install gum, fzf, and openssl manually — it should work without issues.
---
### 🛠️ Installation 
   1. Clone this repository
   ```
    git clone https://github.com/Harsh-bin/dotfold.git
   ```
   ```
    cd dotfold
   ```
   ```
    chmod +x ./install.sh
   ```
   ```
    ./install.sh
   ```
   2. Restart terminal and run
   ```
     dotfoldtui   # TUI MODE
   ```
   ```
     dotfold [command]   # CLI MODE
   ```
  3. Everything's done. NOW, enjoy!✌️
### Uninstalling dotfold
   ```
   chmod +x ./uninstall.sh
   ```
   ```
   ./uninstall.sh
   ```
