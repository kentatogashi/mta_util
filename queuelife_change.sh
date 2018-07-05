#!/usr/local/bin/bash
PATH=/bin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
PROGNAME=$(basename $0)

function usage {
    echo "$PROGNAME is a tool for change queue lifetime.

Usage:
    $PROGNAME <mta> <lifetime>

Arg:
    <mta>:  qmail | postfix
    <lifetime>: $LIFETIMES"
    exit 1
}

function settings {
    LIFETIMES='30|300|600|1800'
    PASSWD=/etc/passwd
    QMAIL_CONF=/var/qmail/control/queuelifetime
    SERVICE_QMAIL=/var/service/qmail
    POSTFIX_CONF=/usr/local/etc/postfix/main.cf
}

function err_exit {
    echo $@ 1>&2
    exit 1
}

function backup {
    local f=$1
    if [ -f $f ]
    then
        cp -p $f $f.$(date +"%Y%m%d") || err_exit "failed to backup."
    else
        err_exit "not found $f for backup."
    fi
}

function has_postfix {
    grep -q '^postfix:' $PASSWD
    return $?
}

# qmail is running on tcpserver
function change_qmail_lifetime {
    if [ -f $QMAIL_CONF ]
    then
        CURRENT_LIFETIME=$(cat $QMAIL_CONF)
        echo "Change queuelifetime? [$CURRENT_LIFETIME => $LIFETIME] [ yes | no ]"
        read ans
        echo
        [ "${ans}" != "yes" ] && err_exit "abort."
        backup $QMAIL_CONF
        echo $LIFETIME > $QMAIL_CONF
        pid1=`svstat $SERVICE_QMAIL | sed -ne 's/.*pid \(.*\)).*$/\1/p'`
        svc -d $SERVICE_QMAIL
        killall qmail-remote || :
        sleep 3
        svc -u $SERVICE_QMAIL
        pid2=`svstat $SERVICE_QMAIL | sed -ne 's/.*pid \(.*\)).*$/\1/p'`
        if [[ -z "$pid1" ]] || [[ -z "$pid2" ]] || [[ $pid1 -eq $pid2 ]]
        then
            err_exit 'qmail fails to restart'
        fi
        svstat $SERVICE_QMAIL
    else
        err_exit "not found $QMAIL_CONF."
    fi
}

function change_postfix_lifetime {
    if has_postfix
    then
        CURRENT_LIFETIME="$(postconf | grep lifetime)"
        echo "Change queuelifetime? ["
        echo "$CURRENT_LIFETIME => ${LIFETIME}s] [ yes | no ]"
        read ans
        echo
        [ "${ans}" != "yes" ] && err_exit "abort."
        backup $POSTFIX_CONF
        sed -i "" -e "s/^bounce_queue_lifetime = \(.*\)$/bounce_queue_lifetime = ${LIFETIME}s/" \
                  -e "s/maximal_queue_lifetime = \(.*\)/maximal_queue_lifetime = ${LIFETIME}s/" $POSTFIX_CONF
        postfix check || err_exit "main.cf has syntax error."
        postfix reload || err_exit "failed to reload postfix."
    else
        err_exit "postfix is not installed."
    fi
}

settings

[ -z "$1" ] && usage
[ -z "$2" ] && usage

MTA=$1
LIFETIME=$2

[ $(echo $LIFETIME | egrep "^($LIFETIMES)$") ] || usage

if [ $MTA = qmail ]
then
    change_qmail_lifetime
elif [ $MTA = postfix ]
then
    change_postfix_lifetime
else
    usage
fi

exit 0
