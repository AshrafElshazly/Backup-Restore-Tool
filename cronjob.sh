# This script is invoked by the crontab to run a daily backup at 5:00 AM.
# It executes the backup.sh script, 
# pipes the output to a while loop for date formatting, 
# and redirects the output to the backup log file.
# Example : 0 5 * * * /home/elshazlii/Backup-Restore-Tool/cronjob.sh

BACKUP_SCRIPT_PATH="/home/elshazlii/Backup-Restore-Tool/backup.sh"
SOURCE_DIR="/home/elshazlii/Backup-Restore-Tool/data"
BACKUP_DIR="/home/elshazlii/Backup-Restore-Tool/backup"
ENCRYPTION_KEY="1a2b3c"
DAYS=1

{ $BACKUP_SCRIPT_PATH -s $SOURCE_DIR -b $BACKUP_DIR -k $ENCRYPTION_KEY -d $DAYS 2>&1 | while IFS= read -r line; 
        do 
            printf "[%s]: " "$(date "+%F %T")"; echo "$line"; 
        done 
} >> /home/elshazlii/cron_backup_logs.log