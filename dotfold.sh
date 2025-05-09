#!/bin/bash

PASS_FILE="$HOME/.config/private/.passwd"
FOLDER_FILE="$HOME/.config/private/.folders"

hash_password() {
  echo -n "$1" | sha256sum | awk '{print $1}'
}
encrypt_folder() {
  echo -n "$1" | openssl enc -aes-256-cbc -salt -pass file:<(echo -n "$user_pass") -base64 -A 2>/dev/null
}
decrypt_folder() {
  echo -n "$1" | openssl enc -d -aes-256-cbc -salt -pass file:<(echo -n "$user_pass") -base64 -A 2>/dev/null
}
input_passwd() {
  gum input --password --placeholder " 🔑 WHaats..the....PAsswd.... "
}

authenticate() {
  MAX_ATTEMPTS=3
  ATTEMPT_COUNT=0
  lockout_time=30
  while true; do
    user_pass=$(input_passwd)
    hashed_user_pass=$(hash_password "$user_pass")
    stored_pass=$(cat "$PASS_FILE" 2>/dev/null)
    if [ "$hashed_user_pass" != "$stored_pass" ]; then
      ATTEMPT_COUNT=$((ATTEMPT_COUNT + 1))
      gum style --foreground 9 "❌ Access Denied (Attempt $ATTEMPT_COUNT/$MAX_ATTEMPTS)"
      if [ "$ATTEMPT_COUNT" -ge "$MAX_ATTEMPTS" ]; then
        gum style --foreground 9 "🔒 Locked out for ${lockout_time}s..."
        sleep $lockout_time
        lockout_time=$((lockout_time + 30))
      fi
      continue
    else
      break
    fi
  done
}

case "$1" in
  "hide")
    if [ ! -f "$PASS_FILE" ]; then
      gum style --foreground 9 "🔐 First-time setup: Create a secure password."
      exit 1
    fi
   authenticate  
    target="${*:2}"
    if [ -z "$target" ]; then
      gum style --foreground 9 "❌ Please specify a folder!"
      exit 1
    fi
    abs_path=$(realpath -- "$target" 2>/dev/null)
    if [ ! -d "$abs_path" ]; then
      gum style --foreground 9 "❌ Folder not found: $target"
      exit 1
    fi
    parent_dir=$(dirname "$abs_path")
    base_name=$(basename "$abs_path")
    hidden_path="$parent_dir/.$base_name"
    if [ -e "$hidden_path" ]; then
      gum style --foreground 9 "❌ Hidden folder already exists!"
      exit 1
    fi
    if ! mv -n "$abs_path" "$hidden_path" 2>/dev/null; then
      gum style --foreground 9 "❌ Failed to hide folder!"
      exit 1
    fi
    encrypted_path=$(encrypt_folder "$hidden_path") || {
      mv "$hidden_path" "$abs_path"
      gum style --foreground 9 "❌ Encryption failed! Reverting changes."
      exit 1
    }
    echo "$encrypted_path" >> "$FOLDER_FILE"
    gum style --foreground 10 "✅ Successfully hidden: $base_name"
    ;;
  "show")
    if [ "$2" != "hidden" ]; then
      gum style --foreground 9 "❌ Invalid command. Usage: dotfold show hidden"
      exit 1
    fi
    if [ ! -f "$PASS_FILE" ]; then
      gum style --foreground 9 "❌ No password set!"
      exit 1
    fi
    authenticate
    if [ ! -f "$FOLDER_FILE" ] || [ ! -s "$FOLDER_FILE" ]; then
      gum style --foreground 10 "ℹ️ No hidden folders found."
      exit 0
    fi
    encrypted_lines=()
    names=()
    paths=()
    while IFS= read -r encrypted_line; do
      decrypted_path=$(decrypt_folder "$encrypted_line") || {
        gum style --foreground 9 "❌ Decryption failed! Check password."
        exit 1
      }
      base_name=$(basename "$decrypted_path")
      display_name="${base_name#.}"
      encrypted_lines+=("$encrypted_line")
      names+=("$display_name")
      paths+=("$decrypted_path")
    done < "$FOLDER_FILE"
    selected=$(printf "%s\n" "${names[@]}" | gum choose --limit 1)
    [ -z "$selected" ] && exit 0
    for i in "${!names[@]}"; do
      if [ "${names[$i]}" == "$selected" ]; then
        xdg-open "${paths[$i]}" 2>/dev/null || gum style --foreground 9 "❌ Failed to open File Manager."
        exit $?
      fi
    done
    ;;
  "unhide")
    if [ ! -f "$PASS_FILE" ]; then
      gum style --foreground 9 "❌ No password set!"
      exit 1
    fi
    authenticate
    if [ ! -f "$FOLDER_FILE" ] || [ ! -s "$FOLDER_FILE" ]; then
      gum style --foreground 10 "ℹ️ No hidden folders to unhide."
      exit 0
    fi
    encrypted_lines=()
    names=()
    paths=()
    while IFS= read -r encrypted_line; do
      decrypted_path=$(decrypt_folder "$encrypted_line") || {
        gum style --foreground 9 "❌ Decryption failed! Check password."
        exit 1
      }
      base_name=$(basename "$decrypted_path")
      display_name="${base_name#.}"
      encrypted_lines+=("$encrypted_line")
      names+=("$display_name")
      paths+=("$decrypted_path")
    done < "$FOLDER_FILE"
    selected=$(printf "%s\n" "${names[@]}" | gum choose --limit 1)
    [ -z "$selected" ] && exit 0
    for i in "${!names[@]}"; do
      if [ "${names[$i]}" == "$selected" ]; then
        selected_path="${paths[$i]}"
        selected_encrypted="${encrypted_lines[$i]}"
        parent_dir=$(dirname "$selected_path")
        base_name=$(basename "$selected_path")
        unhidden_dir="$parent_dir/${base_name#.}"
        if [ -e "$unhidden_dir" ]; then
          gum style --foreground 9 "❌ Target already exists: $unhidden_dir"
          exit 1
        fi
        gum confirm "Unhide folder ${names[$i]}?" && {
          mv "$selected_path" "$unhidden_dir" || {
            gum style --foreground 9 "❌ Failed to unhide folder."
            exit 1
          }
          tmp_file=$(mktemp)
          for line in "${encrypted_lines[@]}"; do
            [ "$line" != "$selected_encrypted" ] && echo "$line" >> "$tmp_file"
          done
          mv "$tmp_file" "$FOLDER_FILE"
          gum style --foreground 10 "✅ Folder ${names[$i]} unhidden successfully."
        }
        exit $?
      fi
    done
    ;;
  "change")
    if [ "$2" != "passwd" ]; then
      gum style --foreground 9 "❌ Invalid command. Usage: dotfold change passwd"
      exit 1
    fi
    authenticate
    gum confirm "Are you sure you want to change the password?" || exit 0
    new_pass=$(gum input --password --placeholder " 🔑 Enter new password")
    new_pass_confirm=$(gum input --password --placeholder " Confirm new password")
    if [ "$new_pass" != "$new_pass_confirm" ]; then
      gum style --foreground 9 "❌ Passwords do not match!"
      exit 1
    fi
    new_hashed_pass=$(hash_password "$new_pass")
    if [ -f "$FOLDER_FILE" ] && [ -s "$FOLDER_FILE" ]; then
      tmp_file=$(mktemp)
      while IFS= read -r encrypted_line; do
        decrypted_path=$(decrypt_folder "$encrypted_line") || {
          gum style --foreground 9 "❌ Failed to decrypt an entry. Aborting."
          rm "$tmp_file"
          exit 1
        }
        new_encrypted_line=$(echo -n "$decrypted_path" | openssl enc -aes-256-cbc -salt -pass file:<(echo -n "$new_pass") -base64 -A 2>/dev/null)
        echo "$new_encrypted_line" >> "$tmp_file"
      done < "$FOLDER_FILE"
      mv "$tmp_file" "$FOLDER_FILE"
    fi
    echo "$new_hashed_pass" > "$PASS_FILE"
    gum style --foreground 10 "✅ Password changed successfully!"
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