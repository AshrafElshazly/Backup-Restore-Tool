# Function to validate backup parameters
validate_backup_params() {
    while getopts ":s:b:k:d:" opt; do
        case $opt in
            s) source_dir=$OPTARG ;;
            b) backup_dir=$OPTARG ;;
            k) encryption_key=$OPTARG ;;
            d) days=$OPTARG ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done

    if [ -z "$source_dir" ] || [ -z "$backup_dir" ] || [ -z "$encryption_key" ] || [ -z "$days" ]; then
        echo "Error: Missing required arguments"
        echo "Usage: backup.sh -s <source_directory> -b <backup_directory> -k <encryption_key> -d <days>"
        exit 1
    fi

    if [ ! -d "$source_dir" ]; then
        echo "Error: Source directory does not exist."
        exit 1
    fi

    if [ ! -d "$backup_dir" ]; then
        echo "Warning: Backup directory does not exist. Creating the directory..."
        mkdir -p "$backup_dir"
    fi

    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo "Error: Days must be a positive integer"
        exit 1
    fi
}

# Function to validate restore parameters
validate_restore_params() {
    while getopts ":b:r:k:" opt; do
        case $opt in
            b) backup_dir=$OPTARG ;;
            r) restore_dir=$OPTARG ;;
            k) decryption_key=$OPTARG ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done

    if [ -z "$backup_dir" ] || [ -z "$restore_dir" ] || [ -z "$decryption_key" ]; then
        echo "Error: Missing required arguments"
        echo "Usage: restore.sh -b <backup_directory> -r <restore_directory> -k <decryption_key>"
        exit 1
    fi

    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir")" ]; then
        echo "Error: Backup directory does not exist or is empty."
        exit 1
    fi

    if [ ! -d "$restore_dir" ]; then
        echo "Warning: Restore directory does not exist. Creating the directory..."
        mkdir -p "$restore_dir"
    fi

    backup_dir="$(ls -td "$backup_dir"/* | head -n 1)"
}

# Function to perform backup
backup(){
    backup_date=$(date +%Y-%m-%d_%H-%M-%S | sed 's/[: ]/_/g')
    backup_path="$backup_dir/$backup_date"
    mkdir -p "$backup_path"
    # Loop over directories in the source directory
    for dir in "$source_dir"/*; do
        # Check for modification date to backup only modified files within the specified number of days
        if find "$dir" -type f -mtime -"$days" | grep -q .; then
            # Create a compressed tar file for each directory
            tar -czf "$backup_path/$(basename "$dir")_${backup_date}.tar.gz" -C "$source_dir" "$(basename "$dir")" || {
                echo "Error: Failed to create tar file for directory '$dir'"
                exit 1
            }
            # Encrypt the tar file using the provided encryption key
            gpg --batch --yes --passphrase "$encryption_key" -c "$backup_path/$(basename "$dir")_${backup_date}.tar.gz" || {
                echo "Error: Failed to encrypt tar file for directory '$dir'"
                exit 1
            }
            # Delete the original tar file
            rm "$backup_path/$(basename "$dir")_${backup_date}.tar.gz" || {
                echo "Error: Failed to delete original tar file for directory '$dir'"
                exit 1
            }
        fi
    done
    # Create a main tar file by adding all encrypted tar files
    find "$backup_path" -type f -name "*.gpg" -printf "%P\n" | while read -r gpgFile
    do
        tar -rf "$backup_path/${backup_date}.tar" -C "$backup_path" "$(basename "$gpgFile")" || {
            echo "Error: Failed to add file '$gpgFile' to the main tar file"
            exit 1
        }
        rm "$backup_path/$gpgFile" || {
            echo "Error: Failed to delete encrypted tar file '$gpgFile'"
            exit 1
        }
    done
    # Compress the main tar file
    if [ -f "$backup_path/${backup_date}.tar" ] ; then
        tar -czf "$backup_path/${backup_date}.tar.gz" -C "$backup_path" "$backup_date.tar"
        rm "$backup_path/$backup_date.tar"
    fi
    # Encrypt the main tar file
    if [ -f "$backup_path/${backup_date}.tar.gz" ] ; then
        gpg --batch --yes --passphrase "$encryption_key" -c "$backup_path/${backup_date}.tar.gz" || {
            echo "Error: Failed to encrypt the main tar file"
            exit 1
        }
        rm "$backup_path"/*.tar.gz || {
            echo "Error: Failed to delete original tar files"
            exit 1
        }
    fi
    # Transfer the encrypted main tar file to a remote server
    if [ -f "$backup_path/${backup_date}.tar.gz.gpg" ] && [ -f "labsuser.pem" ]; then
        scp -i labsuser.pem "$backup_path/${backup_date}.tar.gz.gpg" ubuntu@34.217.96.57:~
    else
        echo "Error: labuser.pem not found or there is problem with "${backup_date}.tar.gz.gpg" file"
    fi
}
# Function to perform restore
restore(){
    temp_dir="$restore_dir/temp/$(basename $backup_dir)"

    if [ -d $temp_dir ] ; then
        echo "This Backup Already Restored in $temp_dir"
        exit 1
    fi

    mkdir -p "$temp_dir"

    find "$backup_dir" -type f -name "*.gpg" -printf "%P\n" | while read -r encrypted
    do
        gpg --quiet --batch --passphrase "$decryption_key" -o "$temp_dir/$(basename ${encrypted%.gpg})"  -d "$backup_dir/$encrypted" || {
            echo "Error: Failed to decrypt file $(basename "$encrypted")"
            exit 1
        }
    done

    if [ -d "$temp_dir" ]; then
        find "$temp_dir" -type f -name "*.tar.gz" -printf "%P\n" | while read -r decrypted
        do
            tar -xzf "$temp_dir/$decrypted" -C $temp_dir && rm "$temp_dir/$decrypted" || {
                echo "Error: Failed to extract file '$decrypted'"
                exit 1
            }
        done

        tar -xf $temp_dir/* -C $temp_dir ; rm $temp_dir/*.tar

        find "$temp_dir" -type f -name "*.gpg" -printf "%P\n" | while read -r encrypted
        do
            gpg --quiet --batch --passphrase "$decryption_key" -o "$temp_dir/$(basename ${encrypted%.gpg})"  -d "$temp_dir/$encrypted" || {
                echo "Error: Failed to decrypt file $(basename "$encrypted")"
                exit 1
            }
        done
        rm $temp_dir/*.gpg
        find "$temp_dir" -name "*.tar.gz" -exec tar -xzf {} -C $temp_dir \;
        rm $temp_dir/*.gz
    fi
}
