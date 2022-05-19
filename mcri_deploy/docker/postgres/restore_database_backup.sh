#!/usr/bin/env bash

USERNAME=$1
DATABASE_NAME=$2
BACKUP_FILE=$3

if [ -z $USERNAME ]; then
    echo Database username not specified
    exit -1
fi

if [ -z $DATABASE_NAME ]; then
    echo Database name not specified
    exit -1
fi

if [ -z $BACKUP_FILE ]; then
    echo Backup file name not specified
    exit -1
fi

echo Username: $USERNAME
echo Database: $DATABASE_NAME
echo Backup File: $BACKUP_FILE

set -x
psql -U $USERNAME postgres -c "DROP DATABASE $DATABASE_NAME"
psql -U $USERNAME postgres -c "CREATE DATABASE $DATABASE_NAME"
psql -U $USERNAME $DATABASE_NAME <  <(gunzip -c $BACKUP_FILE)  # load a .txt.gz file generated by pg_dump
