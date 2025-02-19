#!/bin/bash

# Colors for better visual appeal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Directories to clean
declare -A DIRECTORIES=(
    ["User Cache"]="$HOME/.cache"
    ["System Cache"]="/var/cache"
    ["User Logs"]="$HOME/.local/share/xorg"
    ["System Logs"]="/var/log"
    ["Temporary Files"]="/tmp"
    ["System Temporary Files"]="/var/tmp"
)

# Temporary backup directory
BACKUP_DIR="/tmp/cleaner_backup"

# Log file
LOG_FILE="/var/log/cleaner.log"

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Please run this script as root (using sudo).${NC}"
        exit 1
    fi
}

# Function to calculate directory size
calculate_size() {
    SIZE=$(du -sh "$1" 2>/dev/null | awk '{print $1}')
    echo ${SIZE:-"0B"}
}

# Function to perform backup using rsync with better error handling
backup_files() {
    echo -e "${YELLOW}Backing up $1 ...${NC}"
    mkdir -p "$BACKUP_DIR/$1"
    shopt -s nullglob  # Enable nullglob to avoid errors with empty directories
    FILES=("$2"/*)
    
    if [ ${#FILES[@]} -gt 0 ]; then
        sudo rsync -a --info=progress2 --ignore-errors "$2"/ "$BACKUP_DIR/$1/" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Backup successful for $1.${NC}"
        else
            echo -e "${YELLOW}Backup completed with warnings for $1. Some files may not have been copied.${NC}"
        fi
    else
        echo -e "${YELLOW}No files to backup in $1. Skipping...${NC}"
    fi
    shopt -u nullglob  # Disable nullglob
}


# Function to clean directory
clean_directory() {
    echo -e "${RED}Cleaning $1 ...${NC}"
    sudo rm -rf "$2"/*
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$1 cleaned successfully.${NC}"
    else
        echo -e "${RED}Failed to clean $1. Permission or file lock issue.${NC}"
    fi
}

# Function to restore from backup with better checks
restore_backup() {
    BACKUP_PATH="$BACKUP_DIR/$1"
    TARGET_PATH="$2"
    
    if [ -d "$BACKUP_PATH" ] && [ "$(ls -A "$BACKUP_PATH")" ]; then
        echo -e "${YELLOW}Restoring $1 ...${NC}"
        sudo rsync -a --info=progress2 --ignore-errors "$BACKUP_PATH/" "$TARGET_PATH/"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}$1 restored successfully.${NC}"
            sudo rm -rf "$BACKUP_PATH"
        else
            echo -e "${RED}Restore failed for $1. Check permissions or file locks.${NC}"
        fi
    else
        echo -e "${YELLOW}No backup found or the backup is empty for $1. Skipping...${NC}"
    fi
}


# Function to log cleanup
log_cleanup() {
    sudo bash -c "echo \"$(date): Cleaned $1 - Freed $2\" >> \"$LOG_FILE\""
}

# Function to scan and display junk sizes
scan_junk() {
    echo -e "${YELLOW}Junk Files Summary:${NC}"
    TOTAL_SIZE=0
    for DIR_NAME in "${!DIRECTORIES[@]}"; do
        DIR_PATH=${DIRECTORIES[$DIR_NAME]}
        SIZE=$(calculate_size "$DIR_PATH")
        echo "$DIR_NAME: $SIZE"
        
        # Handle empty directories gracefully
        SIZE_BYTES=$(du -sb "$DIR_PATH" 2>/dev/null | awk '{print $1}')
        SIZE_BYTES=${SIZE_BYTES:-0}  # Default to 0 if empty
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE_BYTES))
    done
    TOTAL_SIZE_MB=$((TOTAL_SIZE / 1024 / 1024))
    echo -e "\nTotal Junk Size: ${TOTAL_SIZE_MB} MB"
}

# Function for dry run mode
dry_run() {
    echo -e "${YELLOW}Dry Run Mode - No files will be deleted.${NC}"
    scan_junk
    echo -e "${YELLOW}Dry Run Complete.${NC}"
}

# Main Menu
while true; do
    echo -e "\n${GREEN}System Cleanup and Optimization Tool${NC}"
    echo "1. Scan Only"
    echo "2. Dry Run (Simulate Cleanup)"
    echo "3. Clean All"
    echo "4. Custom Cleanup"
    echo "5. Backup and Restore"
    echo "6. Exit"
    read -p "Choose an option: " OPTION

    case $OPTION in
        1) # Scan Only
            scan_junk
            ;;
        2) # Dry Run Mode
            dry_run
            ;;
        3) # Clean All
            scan_junk
            read -p "Do you want to clean all junk files? (y/n): " CONFIRM
            if [[ $CONFIRM == "y" || $CONFIRM == "Y" ]]; then
                for DIR_NAME in "${!DIRECTORIES[@]}"; do
                    backup_files "$DIR_NAME" "${DIRECTORIES[$DIR_NAME]}"
                    clean_directory "$DIR_NAME" "${DIRECTORIES[$DIR_NAME]}"
                    log_cleanup "$DIR_NAME" "$(calculate_size "${DIRECTORIES[$DIR_NAME]}")"
                done
                echo -e "\n${GREEN}Cleanup Completed.${NC}"
            else
                echo -e "\n${RED}Cleanup Canceled.${NC}"
            fi
            ;;
        4) # Custom Cleanup
            echo "Select directories to clean:"
            select DIR_NAME in "${!DIRECTORIES[@]}" "Cancel"; do
                if [ "$DIR_NAME" == "Cancel" ]; then
                    echo "Canceled."
                    break
                fi
                backup_files "$DIR_NAME" "${DIRECTORIES[$DIR_NAME]}"
                clean_directory "$DIR_NAME" "${DIRECTORIES[$DIR_NAME]}"
                log_cleanup "$DIR_NAME" "$(calculate_size "${DIRECTORIES[$DIR_NAME]}")"
                echo -e "${GREEN}$DIR_NAME cleaned.${NC}"
            done
            ;;
        5) # Backup and Restore
            echo "Select a directory to restore:"
            select DIR_NAME in "${!DIRECTORIES[@]}" "Cancel"; do
                if [ "$DIR_NAME" == "Cancel" ]; then
                    echo "Canceled."
                    break
                fi
                restore_backup "$DIR_NAME" "${DIRECTORIES[$DIR_NAME]}"
            done
            ;;
        6) # Exit
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid Option. Try again.${NC}"
            ;;
    esac
done
