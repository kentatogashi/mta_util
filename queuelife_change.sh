#!/usr/local/bin/bash
# queuelife_change.sh is a tool for change queue lifetime.
#
# Usage:
#     queuelife_change.sh <mta> <lifetime>
#
# Arg:
#     <mta>:  qmail|postfix
#     <lifetime>: 30|300|600|1800

PATH=/bin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
PROGNAME=$(basename ${0})

function usage {
    echo "${PROGNAME} is a tool for change queue lifetime.

Usage:
    ${PROGNAME} <mta> <lifetime>

Arg:
    <mta>:  qmail|postfix
    <lifetime>: ${LIFETIMES}"
    exit 1
}

function settings {
    LOGFILE=/var/log/queuelife_change.log
    LOG_QUEUE_LIMIT=300
    LIFETIMES='30|300|600|1800'
    PASSWD=/etc/passwd
    QMAIL_CONF=/var/qmail/control/queuelifetime
    SERVICE_QMAIL=/var/service/qmail
    POSTFIX_CONF=/usr/local/etc/postfix/main.cf
    return 0
}

function err_exit {
    echo ${@} 1>&2
    exit 1
}

function backup {
    local f=${1}
    if [ -f ${f} ]
    then
        cp -p ${f} ${f}.$(date +"%Y%m%d") || err_exit "failed to backup."
    else
        err_exit "not found ${f} for backup."
    fi
    return 0
}

function has_postfix {
    grep -q '^postfix:' ${PASSWD}
    return ${?}
}

function log {
    mkdir -p $(dirname ${LOGFILE})
    echo -e "$(date +'%Y-%m-%dT%H:%M:%S') ($PROGNAME:${BASH_LINENO[0]}:${FUNCNAME[1]}) $@" | tee -a ${LOGFILE}
    return 0
}

function log_qmail_queue {
    log "log qmail queue"
    qmHandle -l | tail -${LOG_QUEUE_LIMIT} >> ${LOGFILE}
    return 0
}

function log_postfix_queue {
    log "log postfix queue"
    postqueue -p | tail -${LOG_QUEUE_LIMIT} >> ${LOGFILE}
    return 0
}

# qmail is running on tcpserver
function change_qmail_lifetime {
    if [ -f ${QMAIL_CONF} ]
    then
        local current_lifetime=$(cat ${QMAIL_CONF})
        echo "Change queuelifetime from ${current_lifetime} to ${LIFETIME}?"
        echo "[ yes | no ]"
        read ans
        echo
        [ "${ans}" != "yes" ] && err_exit "abort."
        log_qmail_queue
        backup ${QMAIL_CONF}
        echo ${LIFETIME} > ${QMAIL_CONF}
        log "change queuelifetime from ${current_lifetime} to ${LIFETIME}"
        pid1=$(svstat ${SERVICE_QMAIL} | sed -ne 's/.*pid \(.*\)).*$/\1/p')
        svc -d ${SERVICE_QMAIL}
        killall qmail-remote || :
        sleep 3
        svc -u ${SERVICE_QMAIL}
        log "restart qmail"
        pid2=$(svstat ${SERVICE_QMAIL} | sed -ne 's/.*pid \(.*\)).*$/\1/p')
        if [[ -z "${pid1}" ]] || [[ -z "${pid2}" ]] || [[ ${pid1} -eq ${pid2} ]]
        then
            err_exit 'qmail fails to restart'
        fi
        svstat ${SERVICE_QMAIL}
    else
        err_exit "not found ${QMAIL_CONF}."
    fi
    return 0
}

function change_postfix_lifetime {
    if has_postfix
    then
        local current_time="$(postconf | grep lifetime | sed -e 's/maximal_/and maximal_/' | xargs echo)"
        echo "Change from ${current_time} to ${LIFETIME}s?"
        echo "[ yes | no ]"
        read ans
        echo
        [ "${ans}" != "yes" ] && err_exit "abort."
        log_postfix_queue
        backup ${POSTFIX_CONF}
        log "change postfix *lifetime to ${LIFETIME}s"
        sed -i "" -e "s/^bounce_queue_lifetime = \(.*\)$/bounce_queue_lifetime = ${LIFETIME}s/" \
                  -e "s/maximal_queue_lifetime = \(.*\)$/maximal_queue_lifetime = ${LIFETIME}s/" ${POSTFIX_CONF}
        postfix check || err_exit "main.cf has syntax error."
        log "reload postfix"
        postfix reload || err_exit "failed to reload postfix."
    else
        err_exit "postfix is not installed."
    fi
    return 0
}

settings
[ -z "${1}" ] && usage
[ -z "${2}" ] && usage
MTA=${1}
LIFETIME=${2}
[ $(echo ${LIFETIME}| egrep "^(${LIFETIMES})$") ] || usage

if [ ${MTA} = qmail ]
then
    change_qmail_lifetime
elif [ ${MTA} = postfix ]
then
    change_postfix_lifetime
else
    usage
fi

exit 0
