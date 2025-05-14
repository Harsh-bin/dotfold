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
eval "$(sudo cat "$LOCK_FILE" 2>/dev/null | grep -E '^(attempt_count|unlock_time|lockout)=')"
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
    eval "$(sudo cat "$LOCK_FILE" 2>/dev/null | grep -E '^(attempt_count|unlock_time|lockout)=')"
      attempt_count=$((attempt_count + 1))
      {
        echo "attempt_count=$attempt_count"
        echo "unlock_time=$unlock_time"
        echo "lockout=$lockout"
        echo "owner=$(logname)"
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
  exit 1
  fi
  if [ "$new_pass" = "$confirm_pass" ]; then
    hash_passwd "$new_pass" | sudo tee "$PASS_FILE" >/dev/null
    inti_folder_file
    init_lockfile
    gum style --foreground 10 "✅ Password set successfully!"
    exit 0
  else
    gum style --foreground 9 "❌ Passwords do not match retry..."
    exit 1
  fi
fi  

case "$1" in
  "hide"|"show"|"unhide"|"change")
    authenticate
    ;;
  *)
    ;;
esac     
case "$1" in
  "hide")   
    target="${*:2}"
    if [ -z "$target" ]; then
      gum style --foreground 9 "❌ Please specify a folder!"
      exit 1
    fi
    if [[ "$target" == "~"* ]]; then
        target="${target/\~/$USER_HOME}"
    fi
    abs_path=$(realpath -- "$target" 2>/dev/null)
    if [ $? -ne 0 ] || [ ! -d "$abs_path" ]; then
      gum style --foreground 9 "❌ Folder not found or is not a directory: $target"
      exit 1
    fi
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
    sudo chown -R "$owner":"$owner" "$selected_path" || {
    gum style --foreground 9 "❌ Failed to change ownership back to $owner."
    exit 1 
      }
    else
    gum style --foreground 9 "⚠️ Could not determine original owner"
    fi
    mv "$hidden_path" "$abs_path" 2>/dev/null
    exit 1
    fi
    if sudo grep -qFx "$encrypted_path" "$FOLDER_FILE"; then 
    gum style --foreground 9 "⚠️ Folder '$base_name' hidden and entery exists. Reverting changes."
    owner=$(sudo grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2 2>/dev/null)
    if [ -n "$owner" ]; then
    sudo chown -R "$owner":"$owner" "$selected_path" || {
    gum style --foreground 9 "❌ Failed to change ownership back to $owner."
    exit 1 
      }
    else
    gum style --foreground 9 "⚠️ Could not determine original owner"
    fi
      mv "$hidden_path" "$abs_path" 2>/dev/null
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
      if [ -e "$visible_folder" ]; then
        gum style --foreground 9 "❌ Target already exists: $visible_folder"
        exit 1
      fi
      owner=$(sudo grep '^owner=' "$LOCK_FILE" | cut -d'=' -f2 2>/dev/null)
      if [ -n "$owner" ]; then
        sudo chown -R "$owner:$owner" "$full_path" || {
          gum style --foreground 9 "❌ Failed to change ownership."
          exit 1
        }
      fi
      sudo mv "$full_path" "$visible_folder" || {
        gum style --foreground 9 "❌ Failed to move folder."
        exit 1
      }
      tmp_file=$(mktemp)
      sudo grep -vF "$encrypted_line" "$FOLDER_FILE" > "$tmp_file"
      sudo mv "$tmp_file" "$FOLDER_FILE" || {
        gum style --foreground 9 "❌ Failed to update folder file."
        exit 1
      }
      gum style --foreground 10 "✅ Folder '$selected' unhidden successfully."
    else
      gum style --foreground 11 "↩️ Unhide cancelled."
    fi
    ;;
  "change")
    if [ "$2" != "passwd" ]; then
    gum style --foreground 9 "❌ Invalid command. Usage: dotfold change passwd"
    exit 1
    fi
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
    echo "Note: Uses same password as secret.sh"
    ;;
esac