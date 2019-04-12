#!/bin/bash

MONGODB_HOST=${MONGODB_PORT_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_HOST=${MONGODB_PORT_1_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_PORT=${MONGODB_PORT_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_PORT=${MONGODB_PORT_1_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_USER=${MONGODB_USER:-${MONGODB_ENV_MONGODB_USER}}
MONGODB_PASS=${MONGODB_PASS:-${MONGODB_ENV_MONGODB_PASS}}

ROOT_PATH=${ROOT_PATH:-/backups}
BACKUP_PATH="$ROOT_PATH/$BACKUP_FOLDER"

[[ ( -z "${MONGODB_USER}" ) && ( -n "${MONGODB_PASS}" ) ]] && MONGODB_USER='admin'

[[ ( -n "${MONGODB_USER}" ) ]] && USER_STR=" --username ${MONGODB_USER}"
[[ ( -n "${MONGODB_PASS}" ) ]] && PASS_STR=" --password ${MONGODB_PASS}"
[[ ( -n "${MONGODB_DB}" ) ]] && DB_STR=" --db ${MONGODB_DB}"


echo "=> Deleting backup scripts if exist"
files=(/backup.sh /restore.sh /list.sh)
for f in "${files[@]}" ; do
    [ -e "$f" ] && rm -f $f
done
echo "=> Deleting soft links if exist"
files=(/usr/bin/restore /usr/bin/backup /usr/bin/list)
for f in "${files[@]}" ; do
    [ -h "$f" ] && rm -f $f
done


echo "=> Creating backup script"
cat <<EOF >> /backup.sh
#!/bin/bash
err_exit() {
  echo \$@
  exit 1
}
TIMESTAMP=\`/bin/date +"%Y%m%dT%H%M%S"\`
BACKUP_NAME=\${TIMESTAMP}.dump.gz
BACKUP=${BACKUP_PATH}\${BACKUP_NAME}
if [ -f \${BACKUP} ];then
    echo "Deleting todays previous backup..."
    rm \${BACKUP} || err_exit "Failed to rm \${BACKUP}"
fi
echo "=> Backup started"
cd ${BACKUP_PATH} || err_exit "Cannot cd ${BACKUP_PATH}"
if mongodump --host ${MONGODB_HOST} --port ${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} --archive=\${BACKUP_NAME} --gzip ${EXTRA_OPTS}; then
    echo "   > Backup succeeded"
else
    echo "   > Backup failed"
fi
echo "=> Done"
EOF
chmod +x /backup.sh
echo "=> Backup script created"

echo "=> Creating restore script"
cat <<EOF >> /restore.sh
#!/bin/bash
err_exit() {
  echo \$@
  exit 1
}
cd ${BACKUP_PATH} || err_exit "Cannot cd ${BACKUP_PATH}"
if [[( -n "\${1}" )]];then
    RESTORE_ME=\${1}.dump.gz
else
    RESTORE_ME=latest.dump.gz
fi
RESTORE=${BACKUP_PATH}\${RESTORE_ME}
echo "=> Restore database from \${RESTORE_ME}"
if mongorestore --host ${MONGODB_HOST} --port ${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} --drop --archive=\${RESTORE_ME} --gzip; then
    echo "   Restore succeeded"
else
    echo "   Restore failed"
fi
echo "=> Done"
EOF
chmod +x /restore.sh
echo "=> Restore script created"

echo "=> Creating list script"
cat <<EOF >> /list.sh
#!/bin/bash
err_exit() {
  echo \$@
  exit 1
}
cd ${BACKUP_PATH} || err_exit "Cannot cd ${BACKUP_PATH}"
[ `ls -1 . | wc -l` -eq 0 ] && echo "No backups" && exit 0
ls -1 *.dump.gz | sed -e 's/\..*\$//'
EOF
chmod +x /list.sh
echo "=> List script created"

ln -s /restore.sh /usr/bin/restore
ln -s /backup.sh /usr/bin/backup
ln -s /list.sh /usr/bin/list

touch /mongo_backup.log

if [ -n "${INIT_BACKUP}" ]; then
    echo "=> Create a backup on the startup"
    /backup.sh
fi

if [ -n "${INIT_RESTORE}" ]; then
    echo "=> Restore store from lastest backup on startup"
    /restore.sh
fi

if [ -z "${DISABLE_CRON}" ]; then
    echo "${CRON_TIME} /backup.sh >> /mongo_backup.log 2>&1" > /crontab.conf
    crontab  /crontab.conf
    echo "=> Running cron job"
    cron && tail -f /mongo_backup.log
fi
