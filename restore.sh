#!/bin/bash

source /home/elshazlii/blnk-task-v2/backup_restore_lib.sh

validate_restore_params $@

restore
