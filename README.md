# ▪️📂 dotfold
A small, 🔐 password-protected TUI + CLI tool that hides folders by prefixing them with "." and securely stores folder metadata using OpenSSL and a SHA-256 hashed password.
### Preview
![](/preview/dotfold.png)
--
![](/preview/dotfold.gif)
--
# 🔵 CLI USAGES
### Hiding folders
1. Type full path of folder
   ```
   dotfold hide "/path/to/folder"
   ```
2. or open the terminal in any directory and type the name of a folder that exists in that directory.
   ```
   dotfold hide "folder name"
   ```
### Other commands
1. shows all the hidden folders
   ```
   dotfold show hidden
   ```
2. lets you to unhide a folder
   ```
   dotfold unhide
   ```
3. lets you change password
   ```
   dotfold change passwd
   ```
### 🛠️ **Setup**  
  Install dependencies: 
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
   **📢 For any other distro install these "gum fzf and openssl" this should work with no errors.**
---
