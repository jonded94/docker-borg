#!/bin/bash

set -euo pipefail

function echoerr {
    cat <<< "$@" 1>&2;
}

function quit {
    if [ -n "${SSHFS:-}" ]; then
        fusermount -u "$BORG_REPO"
    fi

    if [ -n "${1:-}" ]; then
        exit "$1"
    fi

    exit 0
}

if [ -n "${SSHFS:-}" ]; then
    if [ -n "${SSHFS_IDENTITY_FILE:-}" ]; then
        if [ ! -f "$SSHFS_IDENTITY_FILE" ] && [ -n "${SSHFS_GEN_IDENTITY_FILE:-}" ]; then
            ssh-keygen -t ed25519 -N '' -f "$SSHFS_IDENTITY_FILE"
            cat "${SSHFS_IDENTITY_FILE}.pub"
            exit 0
        fi
        SSHFS_IDENTITY_FILE="-o IdentityFile=${SSHFS_IDENTITY_FILE}"
    else
        SSHFS_IDENTITY_FILE=''
    fi
    if [ -n "${SSHFS_PASSWORD:-}" ]; then
        SSHFS_PASSWORD="echo \"${SSHFS_PASSWORD}\" |"
        SSHFS_PASSWORD_OPT='-o password_stdin'
    else
        SSHFS_PASSWORD=''
        SSHFS_PASSWORD_OPT=''
    fi
    mkdir -p /mnt/sshfs
    eval "${SSHFS_PASSWORD} sshfs ${SSHFS} /mnt/sshfs ${SSHFS_IDENTITY_FILE} ${SSHFS_PASSWORD_OPT}"
    BORG_REPO=/mnt/sshfs
fi

if [ -z "${BORG_REPO:-}" ]; then
    echoerr 'Variable $BORG_REPO is required. Please set it to the repository location.'
    quit 1
fi

# Borg just needs this
export BORG_REPO

if [ -z "${BORG_PASSPHRASE:-}" ]; then
    INIT_ENCRYPTION='--encryption=none'
    echoerr 'Not using encryption. If you want to encrypt your files, set $BORG_PASSPHRASE variable.'
else
    INIT_ENCRYPTION='--encryption=repokey'
fi

DEFAULT_ARCHIVE="${HOSTNAME}_$(date +%Y-%m-%d)"
ARCHIVE="${ARCHIVE:-$DEFAULT_ARCHIVE}"

if [ -n "${EXTRACT_TO:-}" ]; then
    mkdir -p "$EXTRACT_TO"
    cd "$EXTRACT_TO"
    borg extract -v --list --show-rc ::"$ARCHIVE" ${EXTRACT_WHAT:-}
    quit
fi

if [ -n "${BORG_PARAMS:-}" ]; then
    borg $BORG_PARAMS
    quit
fi

if [ -z "${BACKUP_DIRS:-}" ]; then
    echoerr 'Variable $BACKUP_DIRS is required. Please fill it with directories you would like to backup.'
    quit 1
fi

# If the $BORG_REPO is a local path and the directory is empty, init it
if [ "${BORG_REPO:0:1}" == '/' ] && [ ! "$(ls -A $BORG_REPO)" ]; then
    INIT_REPO=1
fi

if [ -n "${INIT_REPO:-}" ]; then
    borg init -v --show-rc $INIT_ENCRYPTION
fi

if [ -n "${COMPRESSION:-}" ]; then
    COMPRESSION="--compression=${COMPRESSION}"
else
    COMPRESSION=''
fi

if [ -n "${EXCLUDE:-}" ]; then
    OLD_IFS=$IFS
    IFS=';'

    EXCLUDE_BORG=''
    for i in $EXCLUDE; do
        EXCLUDE_BORG="${EXCLUDE_BORG} --exclude ${i}"
    done

    IFS=$OLD_IFS
else
    EXCLUDE_BORG=''
fi

borg create -v --stats --show-rc $COMPRESSION $EXCLUDE_BORG ::"$ARCHIVE" $BACKUP_DIRS

if [ -n "${PRUNE:-}" ]; then
    if [ -n "${PRUNE_PREFIX:-}" ]; then
        PRUNE_PREFIX="--prefix=${PRUNE_PREFIX}"
    else
        PRUNE_PREFIX=''
    fi
    if [ -z "${KEEP_DAILY:-}" ]; then
        KEEP_DAILY=7
    fi
    if [ -z "${KEEP_WEEKLY:-}" ]; then
        KEEP_WEEKLY=4
    fi
    if [ -z "${KEEP_MONTHLY:-}" ]; then
        KEEP_MONTHLY=6
    fi

    borg prune -v --stats --show-rc $PRUNE_PREFIX --keep-daily=$KEEP_DAILY --keep-weekly=$KEEP_WEEKLY --keep-monthly=$KEEP_MONTHLY
fi

if [ "${BORG_SKIP_CHECK:-}" != '1' ] && [ "${BORG_SKIP_CHECK:-}" != "true" ]; then
    borg check -v --show-rc
fi

quit
