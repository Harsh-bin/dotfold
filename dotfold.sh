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

case "$1" in
  "hide") 
    authenticate  
    target="${*:2}"
    if [ -z "$target" ]; then
      gum style --foreground 9 "❌ Please specify a folder!"
      exit 1
    fi
    
    # added path control no hiding outside user's home directory
    USER_HOME="/home/$(logname)"
    if sudo test -f "$LOCK_FILE"; then
      owner=$(sudo grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2)
      if [ -n "$owner" ]; then
        USER_HOME="/home/$owner"
      fi
    fi

    if [[ "$target" == "~"* ]]; then
      target="${target/\~/$USER_HOME}"
    fi
    
    abs_path=$(readlink -f "$target" 2>/dev/null)
    if [ $? -ne 0 ] || [ ! -d "$abs_path" ]; then
      gum style --foreground 9 "❌ Folder not found or is not a directory: $target"
      exit 1
    fi
    if [ "$(dirname "$abs_path")" = "/home" ] && [ "$abs_path" != "$USER_HOME" ]; then
      gum style --foreground 9 "❌ Error: Cannot hide other users' home directories"
      exit 1
    fi
    if [ "$abs_path" = "$USER_HOME" ]; then
      gum style --foreground 9 "❌ Error: Cannot hide your own home directory"
      exit 1
    fi
    case "$abs_path" in
      "$USER_HOME/"*) ;;
      *)
        gum style --foreground 9 "❌ Error: Can only hide folders within your home directory ($USER_HOME)"
        exit 1
        ;;
    esac    
    
    parent_dir=$(dirname "$abs_path")
    base_name=$(basename "$abs_path")
    hidden_path="$parent_dir/.$base_name"
    
    if [ -e "$hidden_path" ]; then
      gum style --foreground 9 "❌ Hidden folder already exists!"
      encrypted_existing_path=$(encrypt_folder "$hidden_path")
      if [ $? -eq 0 ] && sudo grep -qFx "$encrypted_existing_path" "$FOLDER_FILE"; then
        gum style --foreground 9 "⚠️ Folder '$base_name' is already hidden and registered."
      else
        gum style --foreground 9 "⚠️ Hidden file/folder '$hidden_path' exists"
      fi
      exit 1
    fi
    
    if ! sudo mv -n "$abs_path" "$hidden_path" 2>/dev/null; then
      gum style --foreground 9 "❌ Failed to hide folder!"
      exit 1
    fi
    
    sudo chown -R root:root "$hidden_path"
    sudo chmod 700 "$hidden_path"
    encrypted_path=$(encrypt_folder "$hidden_path")
    
    if [ $? -ne 0 ] || [ -z "$encrypted_path" ]; then 
      gum style --foreground 9 "❌ Encryption failed! Reverting changes."
      owner=$(sudo grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2 2>/dev/null)
      if [ -n "$owner" ]; then
        sudo chown -R "$owner":"$owner" "$abs_path" || {
          gum style --foreground 9 "❌ Failed to change ownership back to $owner."
          exit 1 
        }
      else
        gum style --foreground 9 "⚠️ Could not determine original owner"
      fi
      sudo mv "$hidden_path" "$abs_path" 2>/dev/null
      exit 1
    fi
    
    if sudo grep -qFx "$encrypted_path" "$FOLDER_FILE"; then 
      gum style --foreground 9 "⚠️ Folder '$base_name' hidden and entry exists. Reverting changes."
      owner=$(sudo grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2 2>/dev/null)
      if [ -n "$owner" ]; then
        sudo chown -R "$owner":"$owner" "$abs_path" || {
          gum style --foreground 9 "❌ Failed to change ownership back to $owner."
          exit 1 
        }
      else
        gum style --foreground 9 "⚠️ Could not determine original owner"
      fi
      sudo mv "$hidden_path" "$abs_path" 2>/dev/null
      exit 1
    else
      echo "$encrypted_path" | sudo bash -c 'cat >> "$0"' "$FOLDER_FILE" >/dev/null
      gum style --foreground 10 "✅ Successfully hidden: $base_name"
    fi
    ;;
    
  "show")    
    if [ "$2" != "hidden" ]; then
      gum style --foreground 9 "❌ Invalid command. Usage: dotfold show hidden"
      exit 1
    fi
    authenticate

    hidden_folders=()
    while IFS= read -r encrypted_line; do
      decrypted_path=$(decrypt_folder "$encrypted_line")
      if [ $? -eq 0 ] && [ -n "$decrypted_path" ] && sudo test -d "$decrypted_path"; then
        base=$(basename "$decrypted_path")
        display="${base#.}"
        hidden_folders+=("$display|$decrypted_path")
      fi
    done < <(sudo cat "$FOLDER_FILE")
    
    if [ ${#hidden_folders[@]} -eq 0 ]; then
      gum style --foreground 10 "ℹ️ No hidden folders found."
      exit 0
    fi
    
    display_names=()
    for entry in "${hidden_folders[@]}"; do
      display_names+=("$(echo "$entry" | cut -d'|' -f1)")
    done
    
    selected=$(gum choose --limit 1 "${display_names[@]}")
    if [ -z "$selected" ]; then
      gum style --foreground 11 "↩️ Selection cancelled."
      exit 0
    fi
    
    for entry in "${hidden_folders[@]}"; do
      if [ "$(echo "$entry" | cut -d'|' -f1)" = "$selected" ]; then
        full_path=$(echo "$entry" | cut -d'|' -f2)
        break
      fi
    done
    
    if [ -d "$full_path" ]; then
      xdg-open "$full_path" 2>/dev/null || gum style --foreground 9 "❌ Failed to open File Manager."
    else
      gum style --foreground 9 "❌ Folder not found: $full_path"
    fi
    ;;
    
"unhide")
    authenticate
    hidden_folders=()
    while IFS= read -r encrypted_line; do
      decrypted_path=$(decrypt_folder "$encrypted_line")
      if [ $? -eq 0 ] && [ -n "$decrypted_path" ] && sudo test -d "$decrypted_path"; then
        base=$(basename "$decrypted_path")
        display="${base#.}"
        hidden_folders+=("$display|$decrypted_path|$encrypted_line")
      fi
    done < <(sudo cat "$FOLDER_FILE")
    
    if [ ${#hidden_folders[@]} -eq 0 ]; then
      gum style --foreground 10 "ℹ️ No hidden folders to unhide."
      exit 0
    fi
    
    display_names=()
    for entry in "${hidden_folders[@]}"; do
      display_names+=("$(echo "$entry" | cut -d'|' -f1)")
    done
    
    selected=$(gum choose --limit 1 "${display_names[@]}")
    if [ -z "$selected" ]; then
      gum style --foreground 11 "↩️ Selection cancelled."
      exit 0
    fi
    
    for entry in "${hidden_folders[@]}"; do
      if [ "$(echo "$entry" | cut -d'|' -f1)" = "$selected" ]; then
        full_path=$(echo "$entry" | cut -d'|' -f2)
        encrypted_line=$(echo "$entry" | cut -d'|' -f3)
        break
      fi
    done
    
    if gum confirm "🔓 Un-hide folder '$selected'?"; then
      parent_dir=$(dirname "$full_path")
      base=$(basename "$full_path")
      new_name="${base#.}"
      visible_folder="$parent_dir/$new_name"
      
      owner=$(sudo grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2 2>/dev/null)
      [ -n "$owner" ] && sudo chown -R "$owner:$owner" "$full_path"
      
      sudo mv "$full_path" "$visible_folder" || exit 1
      remove_hidden_entry "$full_path" || exit 1
      
      gum style --foreground 10 "✅ Folder unhidden"
    fi
    ;;
    
  "change")    
    if [ "$2" != "passwd" ]; then
      gum style --foreground 9 "❌ Invalid command. Usage: dotfold change passwd"
      exit 1
    fi
    authenticate

    gum confirm "🔑 Do you want to change your password?" || exit 0
    
    while true; do
      new_pass=$(gum input --password --placeholder " 🔑 Enter new password")
      new_pass_confirm=$(gum input --password --placeholder " Confirm new password")
      
      if [ -z "$new_pass" ]; then
        gum style --foreground 9 "❌ Password cannot be empty!"
        continue
      fi
      
      if [ "$new_pass" != "$new_pass_confirm" ]; then
        gum style --foreground 9 "❌ Passwords do not match!"
        continue
      fi
      
      if reencrypt_folders "$user_pass" "$new_pass"; then
        new_hashed_pass=$(hash_passwd "$new_pass")
        echo "$new_hashed_pass" | sudo tee "$PASS_FILE" >/dev/null
        gum style --foreground 10 "✅ Password changed successfully!"
        exit 0
      else
        gum style --foreground 9 "❌ Password change failed."
        exit 1
      fi
    done
    ;;
    
  *)
    echo "Folder Hider CLI"
    echo "Usage:"
    echo "  dotfold hide <folder>      Hide a folder in current directory"
    echo "  dotfold hide /path/to/dir  Hide using absolute path"
    echo "  dotfold show hidden        List all hidden folders"
    echo "  dotfold unhide             Unhide a selected folder"
    echo "  dotfold change passwd      Change the encryption password"
    echo ""
    echo "Note: Uses same password as dotfoldtui"
    ;;
esac