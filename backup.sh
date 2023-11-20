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
BACKUP_NAME="Backup_$BACKUP_HOSTNAME"

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

# Venus OS: check version number and if a backup of the version is already available
if [ -f "/opt/victronenergy/version" ]; then
	VENUS_VER="$(cat /opt/victronenergy/version | head -n 1)"
	echo -n "Checking if a backup file for Venus OS $VENUS_VER already exists: "
	BACKUP_NAME="${BACKUP_NAME}_${VENUS_VER}"
	if ls ${BACKUP_PATH}/${BACKUP_NAME}* 1>/dev/null 2>&1; then
		echo "found, skipping complete backup"
		exit
	fi
	echo "not found, creating complete backup."
fi

# check if dd is a symlink like in busybox
# if yes then probably the argument "status=progress" will not work, use own dd
if [[ -L "/bin/dd" ]] || [[ -f "/opt/victronenergy/version" ]]; then
    # check if backup is already running
    if [ "$(ps | grep -c 'dd if=/dev/mmcblk0')" -gt 1 ]; then
        echo "Backup already running. Exiting..."
        echo
        exit
    fi
    # create backup
	start=`date +%s`	
    echo "$(date +"%T") Using script dd for backup."
    # "$SCRIPT_DIR/ext/dd" if=/dev/mmcblk0 of="${BACKUP_PATH}/${BACKUP_NAME}_$(date +%Y%m%d_%H%M%S).img" bs=1MB status=progress
	"$SCRIPT_DIR/ext/dd" if=/dev/mmcblk0 bs=16k | gzip > ${BACKUP_PATH}/${BACKUP_NAME}_$(date +%Y%m%d_%H%M%S).img.gz

# if not use the system dd
else
    # check if backup is already running
    if [ "$(ps -aux | grep -c 'dd if=/dev/mmcblk0')" -gt 1 ]; then
        echo "Backup already running. Exiting..."
        echo
        exit
    fi
    # create backup
	start=`date +%s`
    echo "$(date +"%T") Using system dd for backup."
    # /bin/dd if=/dev/mmcblk0 of="${BACKUP_PATH}/${BACKUP_NAME}_$(date +%Y%m%d_%H%M%S).img" bs=1MB status=progress
	/bin/dd if=/dev/mmcblk0 bs=16k | gzip > ${BACKUP_PATH}/${BACKUP_NAME}_$(date +%Y%m%d_%H%M%S).img.gz
fi

end=`date +%s`
runtime=$((end-start))
if [ $? -eq 0 ]; then
    echo "$(date +"%T") Backup completed successfully after $runtime seconds."
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
	#ls -tr ${BACKUP_PATH}/${BACKUP_NAME}* 2>/dev/null | head -n ${BACKUP_COUNT} | xargs echo
    popd || exit
    echo -e "$(($BACKUP_FILES_COUNT - $BACKUP_COUNT)) old backups deleted."
fi

# unmount harddisk
umount $BACKUP_MOUNT

if [ $? -ne 0 ]; then
    echo "Error when unmounting the remote path."
fi

echo
echo
