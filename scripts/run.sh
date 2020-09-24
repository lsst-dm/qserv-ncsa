#!/bin/sh

# Launch Docker containers for Qserv master and workers

# @author Fabrice Jammes IN2P3

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)

. "${DIR}/env.sh"

if [ -n "$HOST_CUSTOM_DIR" ]; then
    CUSTOM_VOLUME_OPT="--volume $HOST_CUSTOM_DIR:/qserv/custom"
fi
if [ -n "$HOST_DATA_DIR" ]; then
    DATA_VOLUME_OPT="--volume $HOST_DATA_DIR:/qserv/data"
fi
if [ -n "$HOST_LOG_DIR" ]; then
    LOG_VOLUME_OPT="--volume $HOST_LOG_DIR:/qserv/run/var/log"
fi
if [ -n "$HOST_TMP_DIR" ]; then
    TMP_VOLUME_OPT="--volume $HOST_TMP_DIR:/qserv/run/tmp/"
fi
if [ -n "$ULIMIT_MEMLOCK" ]; then
    ULIMIT_OPT="--ulimit memlock=$ULIMIT_MEMLOCK"
fi

# Capture the local timezone as it needs to be passed down
# into the containers.
SET_CONTAINER_TIMEZONE=false
# Debian way to get timezone
if [ -f /etc/timezone ]; then
    CONTAINER_TIMEZONE=$(cat /etc/timezone)
# Redhat way
elif [ -h /etc/localtime ]; then
    CONTAINER_TIMEZONE=$(readlink -e /etc/localtime | sed "s/\/usr\/share\/zoneinfo\///")
fi
if [ -n "$CONTAINER_TIMEZONE" ]; then
    SET_CONTAINER_TIMEZONE=true
fi

echo
echo "Check for existing Qserv containers"
echo "==================================="
echo
EXIST_MSG="${CONTAINER_NAME} container exists"
STDOUT=$(shmux -Bm -S all -c "
    if docker inspect ${CONTAINER_NAME} 2> /dev/null
    then
        echo '${EXIST_MSG}'
    fi" "$SSH_MASTER" $SSH_WORKERS)

if echo "$STDOUT" | grep "${EXIST_MSG}"
then
    echo
    echo "ERROR: Qserv containers are existing on nodes listed above,
       Remove them using ${DIR}/stop.sh"
    exit 1
else
    echo
    echo "No existing ${CONTAINER_NAME} container on any nodes"
fi

echo
echo "Launch Qserv containers on master"
echo "================================="
echo
shmux -Bm -c "docker run --detach=true \
    --privileged \
    --cap-add=SYS_PTRACE \
    -e "QSERV_MASTER=$MASTER" \
    $CUSTOM_VOLUME_OPT \
    $DATA_VOLUME_OPT \
    $LOG_VOLUME_OPT \
    $TMP_VOLUME_OPT \
    -e "SET_CONTAINER_TIMEZONE=$SET_CONTAINER_TIMEZONE" \
    -e "CONTAINER_TIMEZONE=$CONTAINER_TIMEZONE" \
    $ULIMIT_OPT \
    --name $CONTAINER_NAME --net=host \
    $MASTER_IMAGE" "$SSH_MASTER"

echo
echo "Launch Qserv containers on worker"
echo "================================="
echo
shmux -Bm -S all -c "docker run --detach=true \
    --privileged \
    --cap-add=SYS_PTRACE \
    -e "QSERV_MASTER=$MASTER" \
    $CUSTOM_VOLUME_OPT \
    $DATA_VOLUME_OPT \
    $LOG_VOLUME_OPT \
    $TMP_VOLUME_OPT \
    -e "SET_CONTAINER_TIMEZONE=$SET_CONTAINER_TIMEZONE" \
    -e "CONTAINER_TIMEZONE=$CONTAINER_TIMEZONE" \
    $ULIMIT_OPT \
    --name $CONTAINER_NAME --net=host \
    $WORKER_IMAGE" $SSH_WORKERS


echo
echo "Wait for Qserv services to be up and running on all nodes"
echo "========================================================="
echo
shmux -Bm -S all -c "docker exec $CONTAINER_NAME /qserv/scripts/wait.sh" "$SSH_MASTER" $SSH_WORKERS
