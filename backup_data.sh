#!/bin/bash

# script version 0.0.3 (2023.09.21)

# uncomment for debugging
#set -x

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ ! -f $SCRIPT_DIR/config.ini ]; then
	echo "Error - configuration file $SCRIPT_DIR/config.ini not found!"
    exit
fi

. $SCRIPT_DIR/config.ini

BACKUP_MOUNT="/mnt/backup"
BACKUP_PATH="$BACKUP_MOUNT/$BACKUP_SUBFOLDER$BACKUP_HOSTNAME"
BACKUP_NAME="DataBackup_$BACKUP_HOSTNAME"

echo

# create mount dir if not exists
if [ ! -d $BACKUP_MOUNT ]; then
    echo "$BACKUP_MOUNT does not exist. Creating folder..."
    mkdir $BACKUP_MOUNT
    echo
fi

# check if something is already mounted
if [ 1 -eq "$(mount -v | grep -c $BACKUP_MOUNT)" ]; then
    echo "WARNING: There is already mounted something to \"$BACKUP_MOUNT\". This will be unmounted now."
    echo
    mount -v | grep $BACKUP_MOUNT
    umount $BACKUP_MOUNT
    echo
fi

# mount harddisk
echo "Mounting \"$BACKUP_REMOTE_MOUNT\" to \"$BACKUP_MOUNT\"..."
mount -t cifs -o user=$BACKUP_REMOTE_MOUNT_USER,password=$BACKUP_REMOTE_MOUNT_PW,rw,file_mode=0777,dir_mode=0777 $BACKUP_REMOTE_MOUNT $BACKUP_MOUNT

if [ $? -ne 0 ]; then
    echo "Error when mounting the remote path."
    exit
fi

echo

# create folder if it does not exist
if [ ! -d "$BACKUP_PATH" ]; then
    echo "Creating \"$BACKUP_SUBFOLDER\" on backup mount..."
    mkdir -p "$BACKUP_PATH"
    if [ $? -ne 0 ]; then
        echo "Error when creating of the backup folder on the remote path."
        echo
        exit
    fi
    echo
fi

echo "$(date +"%T") Creating data backup."
tar cjf "${BACKUP_PATH}/${BACKUP_NAME}_$(date +%Y%m%d_%H%M%S).tar.bz2" /data /etc

if [ $? -eq 0 ]; then
    echo "$(date +"%T") Backup completed successfully."
    echo
else
    echo "$(date +"%T") Error during backup!"
    echo
    exit
fi

# delete old backups, but only of more than BACKUP_COUNT backups are found
BACKUP_FILES_COUNT=$(ls ${BACKUP_PATH}/${BACKUP_NAME}* 2>/dev/null | wc -l)
echo "Found $BACKUP_FILES_COUNT backup files"
if [ "$BACKUP_FILES_COUNT" -gt "${BACKUP_COUNT}" ]; then
    pushd ${BACKUP_PATH} || exit
    ls -tr ${BACKUP_PATH}/${BACKUP_NAME}* | head -n ${BACKUP_COUNT} | xargs rm
    popd || exit
    echo -e "$BACKUP_FILES_TO_DELETE_COUNT old backups deleted."
fi

# unmount harddisk
umount $BACKUP_MOUNT

if [ $? -ne 0 ]; then
    echo "Error when unmounting the remote path."
fi

echo
echo
