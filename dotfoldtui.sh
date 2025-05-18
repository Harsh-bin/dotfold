#!/bin/bash

PASS_FILE="/var/lib/dotfold/"$(logname)"/.passwd"
LOCK_FILE="/var/lib/dotfold/"$(logname)"/.lock"
FOLDER_FILE="/var/lib/dotfold/"$(logname)"/.folders"
MAX_ATTEMPTS=3      # max attempt for normal lock
MAX_ATTEMPTS_1=10   # max attempts for permanent lock
INITIAL_LOCKOUT=30  # time in sec

check_deps() {
  for cmd in gum openssl sha256sum xdg-open; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd is required."; exit 1; }
  done
}
check_deps

hash_passwd() {
  local salt=$(openssl rand -hex 16)
  local hashed=$(echo -n "$1$salt" | sha256sum | awk '{print $1}')
  echo "$hashed:$salt"
}
verify_passwd() {
  local input_pass="$1"
  local stored_pass=$(sudo cat "$PASS_FILE")
  local stored_hash=$(echo "$stored_pass" | cut -d':' -f1)
  local salt=$(echo "$stored_pass" | cut -d':' -f2)
  local hashed_input=$(echo -n "$input_pass$salt" | sha256sum | awk '{print $1}')
  [ "$hashed_input" = "$stored_hash" ]
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

# reencrypts folders while changing password 
reencrypt_folders() {
  local old_pass="$1"
  local new_pass="$2"
  local temp_file=$(mktemp)
  trap 'rm -f "$temp_file"' EXIT

  while IFS= read -r encrypted_line; do
    decrypted_path=$(echo -n "$encrypted_line" | openssl enc -d -aes-256-cbc -salt -pass file:<(echo -n "$old_pass") -base64 -A 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$decrypted_path" ]; then
      gum style --foreground 9 "❌ Decryption failed for an entry. Aborting password change."
      trap 'rm -f "$temp_file"' EXIT
      return 1
    fi
    new_encrypted_path=$(echo -n "$decrypted_path" | openssl enc -aes-256-cbc -salt -pass file:<(echo -n "$new_pass") -base64 -A 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$new_encrypted_path" ]; then
      gum style --foreground 9 "❌ Encryption failed for an entry. Aborting password change."
      trap 'rm -f "$temp_file"' EXIT
      return 1
    fi
    echo "$new_encrypted_path" >> "$temp_file"
  done < <(sudo cat "$FOLDER_FILE")
  
  sudo mv "$temp_file" "$FOLDER_FILE"
}

init_folder_file() {
  if ! sudo test -f "$FOLDER_FILE"; then
    sudo touch "$FOLDER_FILE"
  fi
}

# current time
current_time=$(date +%s)

init_lockfile() {
  {
    echo "attempt_count=0"
    echo "unlock_time=$current_time"
    echo "lockout=0"
    echo "owner=$(logname)"
  } | sudo tee "$LOCK_FILE" >/dev/null
}

# check for lock file 
sudo test -f "$LOCK_FILE" || init_lockfile

authenticate() {
  # added fix for coruption of files if both cli and tui run at same time.
  exec 200>"$LOCK_FILE"
  flock -n 200 || { gum style --foreground 9 "Another instance is running."; exit 1; }  
  # First run
  if ! sudo test -f "$PASS_FILE"; then
    sudo mkdir -p "$(dirname "$PASS_FILE")"
    gum style --foreground 12 "🔐 First-time setup: Create a secure password"
    new_pass=$(gum input --password --placeholder "🔑 Set your secret key: ")
    # added support for cancellation
    if [ $? -ne 0 ] || [ "$new_pass" = "" ]; then
      gum style --foreground 11 "↩️ Cancelled...."
      exit 1
    fi
    confirm_pass=$(gum input --password --placeholder " Confirm your secret key: ")
    
    if [ $? -ne 0 ] || [ "$new_pass" = "" ]; then
      gum style --foreground 11 "↩️ Cancelled...."
      exit 1
    fi

    if [ -z "$new_pass" ]; then
      gum style --foreground 9 "❌ Password cannot be empty"
      exit 1
    fi
    if [ "$new_pass" != "$confirm_pass" ]; then
      gum style --foreground 9 "❌ Passwords do not match."
      exit 1
    fi
    hash_passwd "$new_pass" | sudo tee "$PASS_FILE" >/dev/null
    init_folder_file
    gum style --foreground 10 "✅ Password set successfully!"
  fi
  
  while true; do
    user_pass=$(input_passwd)
    if [ $? -ne 0 ] || [ "$user_pass" = "" ]; then
      gum style --foreground 11 "↩️ Cancelled...."
      exit 1
    fi
    if verify_passwd "$user_pass"; then
      init_lockfile
      break
    else
      eval "$(sudo cat "$LOCK_FILE")"
      attempt_count=$(( "${attempt_count:-0}" + 1 ))
      {
        echo "attempt_count=$attempt_count"
        echo "unlock_time=$current_time"
        echo "lockout=0"
        echo "owner=$(logname)"
      } | sudo tee "$LOCK_FILE" >/dev/null | sudo tee "$LOCK_FILE" >/dev/null
      
      gum style --foreground 9 "❌ Access Denied (Attempt $attempt_count/$MAX_ATTEMPTS)"
      
      if [ "$attempt_count" -ge "$MAX_ATTEMPTS" ]; then
        lockout=$(( ${lockout:-$INITIAL_LOCKOUT} + 30 ))
        unlock_time=$(( "$current_time" + "$lockout" ))
        remaining_time=$(( unlock_time - current_time ))
        mins=$(( remaining_time / 60 ))
        secs=$(( remaining_time % 60 ))

        {
          echo "attempt_count=$attempt_count"
          echo "unlock_time=$unlock_time"
          echo "lockout=$lockout"
          echo "owner=$(logname)"
        } | sudo tee "$LOCK_FILE" >/dev/null
        gum style --foreground 9 "🔒 Too many attempts! Locking out for ${mins}m ${secs}s..."
        exit 1
      fi
    fi
  done
}

# added to fix if someuser mistakenly type wrong password when password file is removed to protect floder data
sudo test -f "$LOCK_FILE" || authenticate

# status of lock file
eval "$(sudo cat "$LOCK_FILE" 2>/dev/null | grep -E '^(attempt_count|unlock_time|lockout)=')"

if [ "${attempt_count:-0}" -ge "$MAX_ATTEMPTS_1" ]; then
  gum style --foreground 9 "🔒 Permanent lock! Manual removal required: sudo rm $LOCK_FILE"
  exit 1
fi
if [ "${unlock_time:-0}" -gt "$current_time" ]; then
  remaining_time=$((unlock_time - current_time))
  mins=$(( remaining_time / 60 ))
  secs=$(( remaining_time % 60 ))
  gum style --foreground 9 "🔒 Locked! Try again in ${mins}m ${secs}s..."
  exit 1
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
  local root_dir="/home/$(logname)" # added path control (no navigation outside usrs's home directory)
  if sudo test -f "$LOCK_FILE"; then
    owner=$(sudo grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2)
    if [ -n "$owner" ]; then
      root_dir="/home/$owner"
    fi
  fi

  local current_dir="$root_dir"
  while true; do
    if [ "$current_dir" = "/" ] || [ "$current_dir" = "" ]; then
      current_dir="$root_dir"
    fi
    
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
            
            if sudo test -f "$LOCK_FILE"; then
              owner=$(sudo grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2)
              if [ -n "$owner" ]; then
                sudo chown -R "$owner:$owner" "$folder_to_hide"
              fi
            fi
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
      if [ "$current_dir" != "$root_dir" ]; then
        current_dir=$(dirname "$current_dir")
      fi
    else  
      new_dir="$current_dir/$selected_dir"
      case "$new_dir" in
        "$root_dir"/*|"$root_dir")
          current_dir="$new_dir"
          ;;
        *)
          gum style --foreground 9 "⚠️ Access restricted to $root_dir and subdirectories"
          ;;
      esac
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

unhide_folders() {
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
      unhide_folders
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
            gum style --foreground 10 "✅ Password changed successfully!"
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