#
# ------------------------------------------------------------------
#         Signal SUCCESS OR FAILURE of Wait Handle
# ------------------------------------------------------------------


SCRIPT_DIR=/home/ec2-user/mongodb
if [ -z "${INSTALL_LOG_FILE}" ] ; then
    INSTALL_LOG_FILE=${SCRIPT_DIR}/install.log
fi

log() {
    echo $* 2>&1 | tee -a ${INSTALL_LOG_FILE}
}

usage() {
    cat <<EOF
    Usage: $0 [0 or 1] #1=FAILURE 0=SUCCESS
EOF
    exit 0
}

source ./config.sh


# ------------------------------------------------------------------
#          Read all inputs
# ------------------------------------------------------------------


[[ $# -ne 1 ]] && usage;

SIGNAL=$*

log `date` signalFinalStatus.sh

if [ "${SIGNAL}" == "0" ]; then
##  curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "SUCCESS","Reason" : "The MongoDB cluster has been installed and is ready","UniqueId" : "MongoDBCluster","Data" : "Done"}'  ${WAITHANDLER}
   /opt/aws/bin/cfn-signal -e 0 -r "MongoDB Node install success." "${WAITHANDLER}"
else
##  curl -X PUT -H 'Content-Type:' --data-binary '{"Status" : "FAILURE","Reason" : "The MongoDB cluster did not complete. Will delete all resources.","UniqueId" : "MongoDBCluster","Data" : "Failed"}'  ${WAITHANDLER}
  /opt/aws/bin/cfn-signal -e 1 -r "MongoDB Node install did not succeed." "${WAITHANDLER}"
fi

log `date` END signalFinalStatus.sh


exit 0
