#!/bin/bash
USER_HOME="/home/$(logname)"
PASS_FILE="$USER_HOME/.config/private/.passwd"
LOCK_FILE="$USER_HOME/.config/private/.lock"
FOLDER_FILE="$USER_HOME/.config/private/.folders"
MAX_ATTEMPTS=3
INITIAL_LOCKOUT=30
LOCKOUT_INCREMENT=30

hash_passwd() {
  echo -n "$1" | sha256sum | awk '{print $1}'
}
encrypt_folder() {
  local folder="$1"
  echo -n "$folder" | openssl enc -aes-256-cbc -salt -pass file:<(echo -n "$user_pass") -base64 -A 2>/dev/null
}
decrypt_folder() {
  local folder="$1"
  echo -n "$folder" | openssl enc -d -aes-256-cbc -salt -pass file:<(echo -n "$user_pass") -base64 -A 2>/dev/null
}
input_passwd() {
  gum input --password --placeholder " 🔑 WHaats..the....PAsswd.... "
}
reencrypt_folders() {
  local old_pass="$1"
  local new_pass="$2"
  local temp_file=$(mktemp)
  while IFS= read -r encrypted_line; do
    decrypted_path=$(echo -n "$encrypted_line" | openssl enc -d -aes-256-cbc -salt -pass file:<(echo -n "$old_pass") -base64 -A 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$decrypted_path" ]; then
      gum style --foreground 9 "❌ Decryption failed for an entry. Aborting password change."
      rm -f "$temp_file"
      return 1
    fi
    new_encrypted_path=$(echo -n "$decrypted_path" | openssl enc -aes-256-cbc -salt -pass file:<(echo -n "$new_pass") -base64 -A 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$new_encrypted_path" ]; then
      gum style --foreground 9 "❌ Encryption failed for an entry. Aborting password change."
      rm -f "$temp_file"
      return 1
    fi
    echo "$new_encrypted_path" >> "$temp_file"
  done < <(sudo cat "$FOLDER_FILE")
  sudo mv "$temp_file" "$FOLDER_FILE"
}

inti_folder_file(){
  if ! sudo test -f "$FOLDER_FILE"; then
  sudo touch "$FOLDER_FILE"
  fi
}

init_lockfile() {
  {
     echo "attempt_count=0"
     echo "unlock_time=0"
     echo "lockout=$INITIAL_LOCKOUT"
     echo "owner=$(logname)"
  } | sudo tee "$LOCK_FILE" >/dev/null
}
if ! sudo test -f "$LOCK_FILE"; then
  init_lockfile
fi
eval "$(sudo cat "$LOCK_FILE")"
current_time=$(date +%s)
if [ "$unlock_time" -gt "$current_time" ]; then
  remaining_time=$((unlock_time - current_time))
  gum style --foreground 9 "🔒 Locked! Try again in $remaining_time seconds."
  exit 1
fi

authenticate() {
  while true; do
    user_pass=$(input_passwd)
    hashed_user_pass=$(hash_passwd "$user_pass")
    stored_pass=$(sudo cat "$PASS_FILE" 2>/dev/null)
    if [ "$hashed_user_pass" != "$stored_pass" ]; then
    eval "$(sudo cat "$LOCK_FILE" 2>/dev/null)"
      attempt_count=$((attempt_count + 1))
      {
        echo "attempt_count=$attempt_count"
        echo "unlock_time=$unlock_time"
        echo "lockout=$lockout"
      } | sudo tee "$LOCK_FILE" >/dev/null
      gum style --foreground 9 "❌ Access Denied (Attempt $attempt_count/$MAX_ATTEMPTS)"
      if [ "$attempt_count" -ge "$MAX_ATTEMPTS" ]; then
        unlock_time=$((current_time + lockout))
        lockout=$((lockout + LOCKOUT_INCREMENT))
        {
          echo "attempt_count=$attempt_count"
          echo "unlock_time=$unlock_time"
          echo "lockout=$lockout"
          echo "owner=$(logname)"
        } | sudo tee "$LOCK_FILE" >/dev/null
        gum style --foreground 9 "🔒 Too many attempts! Locking out for $((lockout - 30)) seconds..."
        sleep "$lockout"
        exit 1
      fi
    else
      init_lockfile
      break
    fi
  done
}
if ! sudo test -f "$PASS_FILE"; then
  sudo mkdir -p "$(dirname "$PASS_FILE")"
  gum style --foreground 12 "🔐 First-time setup: Create a secure password"
  new_pass=$(gum input --password --placeholder "🔑 Set your secret key: ")
  confirm_pass=$(gum input --password --placeholder " Confirm your secret key: ")
  if [ -z "$new_pass" ]; then
     gum style --foreground 9 "❌ Password cannot be empty"
  continue
  fi
  if [ "$new_pass" != "$confirm_pass" ]; then
     gum style --foreground 9 "❌ Passwords do not match."
  continue
  fi
  if [ "$new_pass" = "$confirm_pass" ]; then
    hash_passwd "$new_pass" | sudo tee "$PASS_FILE" >/dev/null
    inti_folder_file
    gum style --foreground 10 "✅ Password set successfully!"
  else
    gum style --foreground 9 "❌ Passwords do not match retry..."
    exit 1
  fi
fi  
authenticate

menu() {
  local menu_options
  if sudo test -s "$FOLDER_FILE"; then
    menu_options="🌌 my-space\n📁 hide-folder\n🔓 un-hide-folder\n🔑 change-passwd\n🚪 Exit"
  else
    menu_options="🌌 my-space\n📁 hide-folder\n🔑 change-passwd\n🚪 Exit"
  fi
  echo -e "$menu_options" | fzf --prompt=" FOLDER HIDER " \
                                --border=rounded \
                                --reverse \
                                --color=border:bright-blue \
                                --height=15% \
                                --color='fg:white,fg+:bright-white,bg+:bright-black' 
}
hide_folder() {
  if sudo test -f "$LOCK_FILE"; then
  owner=$(sudo grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2)
  if [ -n "$owner" ]; then
  local current_dir="/home/$owner"
  fi
  fi
  while true; do
    selection=$(find "$current_dir" -maxdepth 1 -mindepth 1 -type d -not -name '.*' -printf '%f\n' | 
      awk 'BEGIN {print ".."} {print}' | 
      fzf --prompt="┏ FOLDER NAVIGATOR ┓" \
          --header="┃ Current: $current_dir
┗━━━━━━━━━━━━━━━━━━━━━━┛" \
          --border=rounded \
          --reverse \
          --border-label="┤ Keys: Enter=Navigate | Ctrl+h=Hide | Esc=Back ├" \
          --color=border:bright-blue \
          --bind 'ctrl-h:print(hide)+accept' \
          --expect=ctrl-h \
          --height=50% \
          --color='fg:white,fg+:bright-white,bg+:bright-black' \
          --prompt="  Search-» ")
    keypress=$(echo "$selection" | head -1)
    selected_dir=$(echo "$selection" | tail -1)
    if [ "$keypress" = "ctrl-h" ]; then
      if [ -n "$selected_dir" ] && [ "$selected_dir" != ".." ]; then
        folder_to_hide="$current_dir/$selected_dir"
        hidden_path="$current_dir/.$selected_dir"
        if mv -n "$folder_to_hide" "$hidden_path" 2>/dev/null; then
        sudo chown -R root:root "$hidden_path"
        sudo chmod 700 "$hidden_path"
          encrypted_path=$(encrypt_folder "$hidden_path")
          if [ $? -eq 0 ]; then
          if ! sudo grep -qF "$encrypted_path" "$FOLDER_FILE"; then
             echo "$encrypted_path" | sudo tee -a "$FOLDER_FILE" >/dev/null
          else
            gum style --foreground 9 "⚠️ Folder already hidden!"
          fi
            gum style --foreground 9 "✅ Successfully hidden: $(basename "$folder_to_hide")"
            return
          else
           gum style --foreground 9 "❌ Error: Encryption failed!"
            sudo mv "$hidden_path" "$folder_to_hide"
            sudo chown -R "$owner:$owner" "$folder_to_hide"
            return 1
          fi
        else
          gum style --foreground 9 "❌ Error: Couldn't hide folder!"
          return 1
        fi
      else
        gum style --foreground 9 "⚠️ Please select a folder first (can't hide parent directory)"
      fi
    fi
    if [ -z "$selected_dir" ]; then 
      return
    elif [ "$selected_dir" = ".." ]; then
      if [ "$current_dir" != "$HOME" ]; then
        current_dir=$(dirname "$current_dir")
      fi
    else  
      current_dir="$current_dir/$selected_dir"  
    fi
  done
}
list_hidden_folders() {
  if sudo test -s "$FOLDER_FILE"; then
    sudo cat "$FOLDER_FILE" | while IFS= read -r encrypted_path; do
      decrypted_path=$(decrypt_folder "$encrypted_path")
      if [ $? -eq 0 ] && [ -n "$decrypted_path" ] && sudo test -d "$decrypted_path"; then
        base=$(basename "$decrypted_path")
        display="${base#.}"
        echo "$decrypted_path|$display"
      fi
    done 
  fi
}
remove_hidden_entry() {
  local folder_to_remove="$1"
  sudo bash -c '
    temp_file=$(mktemp)
    found=0
    while IFS= read -r encrypted_path; do
      decrypted_path=$(echo -n "$encrypted_path" | openssl enc -d -aes-256-cbc -salt -pass file:<(echo -n "'"$user_pass"'") -base64 -A 2>/dev/null)
      if [ "$decrypted_path" = "'"$folder_to_remove"'" ]; then
        found=1
      else
        echo "$encrypted_path" >> "$temp_file"
      fi
    done < "'"$FOLDER_FILE"'"
    
    if [ "$found" -eq 1 ]; then
      sudo mv "$temp_file" "'"$FOLDER_FILE"'"
      sudo chmod 600 "'"$FOLDER_FILE"'"
    else
      rm "$temp_file"
    fi
  '
}
while true; do
  choice=$(menu)
  case "$choice" in
    "🌌 my-space")
      hidden_list=$(list_hidden_folders)
      if [ -z "$hidden_list" ]; then
        if gum confirm "❓ You haven't created a private space yet! Would you like to create one now?"; then
          hide_folder
        fi
      else
        selected=$(echo -e "$(echo "$hidden_list" | cut -d"|" -f2)\n↩️ Back" | fzf --prompt=" 👇️ Select a private space: " --border --height=50% --reverse)
        if [ "$selected" = "↩️ Back" ] || [ -z "$selected" ]; then
          continue
        fi
        fullpath=$(echo "$hidden_list" | grep -F "|$selected" | cut -d"|" -f1)
        if [ -d "$fullpath" ]; then
          xdg-open "$fullpath" 2>/dev/null || gum style --foreground 9 "❌ Failed to open File Manager."
        else
          gum style --foreground 9 "❌ Folder not found."
        fi
      fi
      ;;
    "📁 hide-folder")
      hide_folder
      ;;
    "🔓 un-hide-folder")
      hidden_list=$(list_hidden_folders)
      if [ -z "$hidden_list" ]; then
        gum style --foreground 9 "❌ No hidden folder found."
      else
        selected=$(echo -e "$(echo "$hidden_list" | cut -d"|" -f2)\n↩️ Back" | fzf --prompt=" 👇️ Select a folder to un-hide: " --border --height=50% --reverse)
        if [ "$selected" = "↩️ Back" ] || [ -z "$selected" ]; then
          continue
        fi
        fullpath=$(echo "$hidden_list" | grep -F "|$selected" | cut -d"|" -f1)
        if gum confirm "🔓 Un-hide folder \"$selected\"?"; then
          dir=$(dirname "$fullpath")
          base=$(basename "$fullpath")
          new_name="${base#.}"
          visible_folder="${dir}/${new_name}"
          sudo mv "$fullpath" "$visible_folder"
          remove_hidden_entry "$fullpath"
        if sudo test -f "$LOCK_FILE"; then
        owner=$(grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2)
        if [ -n "$owner" ]; then
           sudo chown -R "$owner:$owner" "$visible_folder"
        fi
        fi
          gum style --foreground 10 "✅ Folder un-hidden successfully."
      fi
      fi
      ;;
    "🔑 change-passwd")
      if gum confirm "🔑 Do you want to change your password?"; then
        while true; do 
        new_pass=$(gum input --password --placeholder "🔑 New Password: ")
       confirm_pass=$(gum input --password --placeholder " Confirm Password: ")
      if [ -z "$new_pass" ]; then
        gum style --foreground 9 "❌ Password cannot be empty!"
        continue
      fi
      if [ "$new_pass" != "$confirm_pass" ]; then
        gum style --foreground 9 "❌ Passwords do not match."
        continue
      fi
      if reencrypt_folders "$user_pass" "$new_pass"; then
        hash_passwd "$new_pass" | sudo tee "$PASS_FILE" >/dev/null
        user_pass="$new_pass"
        gum style --foreground 10 "✅ New password set successfully."
        break
      else
        gum style --foreground 9 "❌ Password change failed. Please try again."
      fi
    done
  else
    gum style --foreground 11 "↩️ Cancelled...."
  fi
      ;;
    "🚪 Exit")
      exit 0
      ;;
    *)
      ;;
  esac
done