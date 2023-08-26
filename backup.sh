#!/bin/bash

source ~/Backup-Restore-Tool/backup_restore_lib.sh

validate_backup_params $@

backup
