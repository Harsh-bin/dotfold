#!/bin/bash

PASS_FILE="$HOME/.config/private/.passwd"
FOLDER_FILE="$HOME/.config/private/.folders"

hash_password() {
  echo -n "$1" | sha256sum | awk '{print $1}'
}
encrypt_floder() {
  echo -n "$1" | openssl enc -aes-256-cbc -salt -pass file:<(echo -n "$user_pass") -base64 -A 2>/dev/null
}
decrypt_folder() {
  echo -n "$1" | openssl enc -d -aes-256-cbc -salt -pass file:<(echo -n "$user_pass") -base64 -A 2>/dev/null
}
input_passwd() {
  gum input --password --placeholder " 🔑 WHaats..the....PAsswd.... "
}

if [ ! -f "$PASS_FILE" ]; then
  mkdir -p "$(dirname "$PASS_FILE")"
  gum style --foreground 12 "🔐 First-time setup: Create a secure password"
  new_pass=$(gum input --password --placeholder "🔑 Set your secret key: ")
  confirm_pass=$(gum input --password --placeholder " Confirm your secret key: ")
  if [ "$new_pass" = "$confirm_pass" ]; then
    hash_password "$new_pass" > "$PASS_FILE"
    chmod 600 "$PASS_FILE"
    gum style --foreground 10 "✅ Password set successfully!"
  else
    gum style --foreground 9 "❌ Passwords do not match retry..."
    exit 1
  fi
fi

menu() {
  local menu_options
  if [ -s "$FOLDER_FILE" ]; then
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
  local current_dir="$HOME"
  while true; do
    selection=$(find "$current_dir" -maxdepth 1 -mindepth 1 -type d -not -name '.*' -printf '%f\n' | 
      awk 'BEGIN {print ".."} {print}' | 
      fzf --prompt="┏ FOLDER NAVIGATOR ┓" \
          --header="┃ Current: $current_dir
┗━━━━━━━━━━━━━━━━━━━━━━┛" \
          --border=rounded \
          --reverse \
          --border-label="┤ Keys: Enter to navigate, Ctrl+h to hide, Esc to go back ├" \
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
          encrypted_path=$(encrypt_floder "$hidden_path")
          if [ $? -eq 0 ]; then
            echo "$encrypted_path" >> "$FOLDER_FILE"
            gum style --foreground 9 "✅ Successfully hidden: $(basename "$folder_to_hide")"
            return
          else
           gum style --foreground 9 "❌ Error: Encryption failed!"
            mv "$hidden_path" "$folder_to_hide"
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
  if [ -s "$FOLDER_FILE" ]; then
    while IFS= read -r encrypted_path; do
      decrypted_path=$(decrypt_folder "$encrypted_path")
      if [ $? -eq 0 ] && [ -n "$decrypted_path" ] && [ -d "$decrypted_path" ]; then
        base=$(basename "$decrypted_path")
        display="${base#.}"
        echo "$decrypted_path|$display"
      fi
    done < "$FOLDER_FILE"
  fi
}
remove_hidden_entry() {
  local folder_to_remove="$1"
  if [ -f "$FOLDER_FILE" ]; then
    temp_file=$(mktemp)
    while IFS= read -r encrypted_path; do
      decrypted_path=$(decrypt_folder "$encrypted_path")
      if [ "$decrypted_path" != "$folder_to_remove" ]; then
        echo "$encrypted_path" >> "$temp_file"
      fi
    done < "$FOLDER_FILE"
    mv "$temp_file" "$FOLDER_FILE"
  fi
}

MAX_ATTEMPTS=3 
ATTEMPT_COUNT=0
lockout_time=30
while true; do
  user_pass=$(input_passwd)
  hashed_user_pass=$(hash_password "$user_pass")
  stored_pass=$(cat "$PASS_FILE")
  if [ "$hashed_user_pass" != "$stored_pass" ]; then
    ATTEMPT_COUNT=$((ATTEMPT_COUNT + 1))
    gum style --foreground 9 "❌ Access Denied (Attempt $ATTEMPT_COUNT/$MAX_ATTEMPTS)"
    if [ "$ATTEMPT_COUNT" -ge "$MAX_ATTEMPTS" ]; then    
      gum style --foreground 9 "🔒 Too many failed attempts. Locking out for $lockout_time seconds..."
      sleep "$lockout_time"    
      lockout_time=$((lockout_time + 30))
    fi
    continue
  else
    break
  fi
done

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
          xdg-open "$fullpath" &
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
          mv "$fullpath" "$visible_folder"
          remove_hidden_entry "$fullpath"
          gum style --foreground 10 "✅ Folder un-hidden successfully."
        fi
      fi
      ;;
    "🔑 change-passwd")
      if gum confirm "🔑 Do you want to change your password?"; then
        new_pass=$(gum input --password --placeholder "🔑 New Password: ")
        confirm_pass=$(gum input --password --placeholder " Confirm Password: ")
        if [ "$new_pass" = "$confirm_pass" ]; then
          hash_password "$new_pass" > "$PASS_FILE"
          chmod 600 "$PASS_FILE"
          gum style --foreground 10 "✅ New password set successfully."
        else
          gum style --foreground 9 "❌ Passwords do not match."
        fi
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