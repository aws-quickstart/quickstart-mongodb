#!/bin/bash


# Install jq to parse meta-data
# MISC=/home/ec2-user/misc/bin/
# mkdir -p ${MISC}
JQ_COMMAND=jq
# [ ! -e ${JQ_COMMAND} ] && wget http://stedolan.github.io/jq/download/linux64/jq -O ${JQ_COMMAND}
# chmod 755 ${JQ_COMMAND}
# sudo yum -y install jq

# export PATH=${PATH}:/sbin:/usr/sbin:/usr/local/sbin:/root/bin:/usr/local/bin:/usr/bin:/bin:/usr/bin/X11:/usr/X11R6/bin:/usr/games:/usr/lib/AmazonEC2/ec2-api-tools/bin:/usr/lib/AmazonEC2/ec2-ami-tools/bin:/usr/lib/mit/bin:/usr/lib/mit/sbin:${MISC}


# ---------------------------------------------------------------------
#          env vars to configure aws cli on Amazon Linux
#          No need for keys etc if run on instance with correct IAM role
# ---------------------------------------------------------------------


export AWS_DEFAULT_REGION=${REGION}
export AWS_DEFAULT_AVAILABILITY_ZONE=${AVAILABILITY_ZONE}

if [ -z ${AWS_DEFAULT_REGION} ]; then
   export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
          | ${JQ_COMMAND} '.region'  \
          | sed 's/^"\(.*\)"$/\1/' )
fi
if [ -z ${AWS_DEFAULT_AVAILABILITY_ZONE} ]; then
   export AWS_DEFAULT_AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
            | ${JQ_COMMAND} '.availabilityZone' \
            | sed 's/^"\(.*\)"$/\1/' )
fi

if [ -z ${AWS_INSTANCEID} ]; then
   export AWS_INSTANCEID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
            | ${JQ_COMMAND} '.instanceId' \
            | sed 's/^"\(.*\)"$/\1/' )
fi

# ------------------------------------------------------------------
#          remove double quotes, if any. cli doesn't like it!
# ------------------------------------------------------------------

export AWS_DEFAULT_REGION=$(echo ${AWS_DEFAULT_REGION} | sed 's/^"\(.*\)"$/\1/' )
export AWS_DEFAULT_AVAILABILITY_ZONE=$(echo ${AWS_DEFAULT_AVAILABILITY_ZONE} | sed 's/^"\(.*\)"$/\1/' )
export AWS_INSTANCEID=$(echo ${AWS_INSTANCEID} | sed 's/^"\(.*\)"$/\1/' )
export AWS_CMD=/usr/bin/aws

MYSTACKID=$(${AWS_CMD} ec2 describe-tags --filters "Name=resource-id,Values=${AWS_INSTANCEID}" | ${JQ_COMMAND} '.Tags[] | select(.Key=="aws:cloudformation:stack-id") | .Value')
MYSTACKID=$(echo ${MYSTACKID} | sed 's/^"\(.*\)"$/\1/' )
MYSTACKPARENT=$(echo ${MYSTACKID} | awk -F '/' '{print $2}' | awk -F'-' '{print $1}')

MYPRIVATEIP=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
            | ${JQ_COMMAND} '.privateIp' \
            | sed 's/^"\(.*\)"$/\1/' )


log() {
  echo $* 2>&1
}

usage() {
    cat <<EOF
    Usage: $0 [options]
        -h print usage
        -c Create DyanamoDB Table
        -b Block until table is created
        -d Delete table
        -s Update "Status" column
        -i Insert/Update Item (key=value pair)
        -n Table Name (optional. Default name is CFN stackname)
        -q Query number of nodes in a given state
        -w Wait until N nodes reach a specific state (COMPLETE=N)
        -p Print Table
        -g Print IPv4 Adrresses
EOF
#    exit 0
}



# ------------------------------------------------------------------
#          Read all inputs
# ------------------------------------------------------------------


CREATE=0
PRINT=0
BLOCK_UNTIL_TABLE_LIVE=0
DELETE_TABLE=0
GET_IPv4=0

[[ $# -eq 0 ]] && usage;

while getopts "hcbpdgis:i:n:q:w:" o; do
  case "${o}" in
    h) usage && exit 0
    ;;
    c) CREATE=1
    ;;
    p) PRINT=1
    ;;
    b) BLOCK_UNTIL_TABLE_LIVE=1
    ;;
    d) DELETE_TABLE=1
    ;;
    g) GET_IPv4=1
    ;;
    q) QUERY_STATUS=${OPTARG}
    ;;
    s) NEW_STATUS=${OPTARG}
    ;;
    i) NEW_ITEM_PAIR=${OPTARG}
    ;;
    n) TABLE_NAME=${OPTARG}
    ;;
    w) WAIT_STATUS_COUNT_PAIR=${OPTARG}
    ;;
    i) INIT_ENV=1
    ;;
  esac
done

# ------------------------------------------------------------------
#          Make sure all input parameters are filled
# ------------------------------------------------------------------

shift $((OPTIND-1))
[[ $# -gt 0 ]] && usage;

if [ -z ${TABLE_NAME} ]; then
  export TABLE_NAME=${MYSTACKPARENT}-DDB-Table
  echo "Table name not specified. Using ${TABLE_NAME}"
fi



# ------------------------------------------------------------------
#          Status of Table creation
# ------------------------------------------------------------------

GetCreationStatus() {
    status=$(${AWS_CMD} dynamodb describe-table --table-name ${TABLE_NAME} --query Table.TableStatus)
    echo $status
}

# ------------------------------------------------------------------
#          Wait until Table is created and Active
# ------------------------------------------------------------------

WaitUntilTableActive() {
    while true; do
    status=$(GetCreationStatus)
    log "${TABLE_NAME}:${status}"
    log ${status}
        case "$status" in
          *ACTIVE* ) break;;
        esac
    sleep 10
    done
}


IfTableFound() {
  status=$(${AWS_CMD} dynamodb describe-table --table-name ${TABLE_NAME} 2>&1)
  [[ ${status} == *"not found"* ]] && echo 0 && return
  echo 1
}


# ------------------------------------------------------------------
#  Used in multinode scenario when master created the table
#	 Worker nodes will just wait until table is ready
# ------------------------------------------------------------------

WaitUntilTableLive() {
    while true; do
    status=$(IfTableFound)
    if [ $status -eq 0 ]; then
      echo "Waiting for Master to create table.."
      sleep 10
    else
      echo "Master has created table!"
      break
    fi
  done
}


# ------------------------------------------------------------------
#          Create dynamodb table to do handshake of multinodes
#          Remember you can add other columns anytime!
# ------------------------------------------------------------------

CreateTable() {
  log "CreateTable ${TABLE_NAME}..."
    ${AWS_CMD} dynamodb create-table \
        --table-name ${TABLE_NAME} \
        --attribute-definitions \
            AttributeName=PrivateIpAddress,AttributeType=S \
        --key-schema \
            AttributeName=PrivateIpAddress,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1

    log "Waiting for table creation"
    WaitUntilTableActive
    log "DynamoDB Table: ${TABLE_NAME} Ready!"
}



# ------------------------------------------------------------------
#          Delete table to make a clean start deploy
# ------------------------------------------------------------------

DeleteTable() {
  status=$(IfTableFound)
  if [ $status -eq 0 ]; then
    echo "Table doesn't exist. No need to delete"
    return
  fi
  status=$(${AWS_CMD} dynamodb delete-table --table-name ${TABLE_NAME})
  WaitUntilTableDead
}

# ------------------------------------------------------------------
#    Wait until table is fully deleted!
# ------------------------------------------------------------------

WaitUntilTableDead() {
    while true; do
        status=$(IfTableFound)
    if [ $status -eq 1 ]; then
      echo "Waiting for table delete to complete!.."
      sleep 10
    else
      echo "Master has deleted table!"
      break
    fi
  done
}


# ------------------------------------------------------------------
#          Initialize the dynamodb table
#          PrivateIpAddress, Status and InstanceId columns init
# ------------------------------------------------------------------

InitMyTable() {
    myip=${MYPRIVATEIP}
    json_template='{ "PrivateIpAddress": {"S": "myip" }}'
    json=$(echo ${json_template} | sed "s/myip/${myip}/g")
    ${AWS_CMD} dynamodb put-item --table-name ${TABLE_NAME}  --item "${json}"
    instanceid=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    InsertMyKeyValueS "InstanceId=${instanceid}"
}




# ------------------------------------------------------------------
#          Update or insert table item with new key=value pair
#          New attributes get added, old attributes get updated
#          Use private ip as primary hash key
#          Usage InsertMyKeyValueS key=value
# ------------------------------------------------------------------

InsertMyKeyValueS() {

    keyvalue=$1
    if [ -z "$keyvalue" ]; then
        echo "Invalid KeyPair Values!"
        return
    fi
    key=$(echo $keyvalue | awk -F'=' '{print $1}')
    value=$(echo $keyvalue | awk -F'=' '{print $2}')

    keyjson_template='{"PrivateIpAddress": {
        "S": "myip"
        }}'
    myip=${MYPRIVATEIP}
    keyjson=$(echo -n ${keyjson_template} | sed "s/myip/${myip}/g")

    insertjson_template='{"key": {
                "Value": {
                    "S": "value"
                },
                "Action": "PUT"
            }
        }'

    insertjson=$(echo -n ${insertjson_template} | sed "s/key/${key}/g")
    insertjson=$(echo -n ${insertjson} | sed "s/value/${value}/g")
    cmd=$(echo  "${AWS_CMD} dynamodb update-item --table-name ${TABLE_NAME} --key '${keyjson}' --attribute-updates '${insertjson}'")
  log "${cmd}"
    echo ${cmd} | sh
}


# ------------------------------------------------------------------
#          Use private ip as primary hash key
#          Set Status of node
#          Usage SetMyStatus "INSTALL_STARTED"
#                SetMyStatus "INSTALL_COMPLETE" etc
# ------------------------------------------------------------------

SetMyStatus() {
    status=$1
    if [ -z "$status" ]; then
        echo "Invalid Status Update!"
        return
    fi
    keyjson_template='{"PrivateIpAddress": {
        "S": "myip"
        }}'
    myip=${MYPRIVATEIP}
    keyjson=$(echo -n ${keyjson_template} | sed "s/myip/${myip}/g")

    updatejson_template='{"Status": {
                "Value": {
                    "S": "mystatus"
                },
                "Action": "PUT"
            }
        }'

    updatejson=$(echo -n ${updatejson_template} | sed "s/mystatus/${status}/g")
    cmd=$(echo  "${AWS_CMD} dynamodb update-item --table-name ${TABLE_NAME} --key '${keyjson}' --attribute-updates '${updatejson}'")
    echo "${AWS_CMD} dynamodb update-item --table-name ${TABLE_NAME} --key '${keyjson}' --attribute-updates '${updatejson}'"
    echo ${cmd} | sh

}


# ------------------------------------------------------------------
#          Use Status column in DDB to orchestrate
#          Count number of hosts in specific state
#          Usage: QueryStatusCount "INSTALL_COMPLETE"
#                 Get total hosts which have Status=INSTALL_COMPLETE
# ------------------------------------------------------------------

QueryStatusCount(){
    status=$1
    if [ -z "$status" ]; then
        echo "StatusCountQuery invalid!"
        return
    fi
    count=$(${AWS_CMD} dynamodb scan --table-name ${TABLE_NAME} --scan-filter '
            { "Status" : {
                "AttributeValueList": [
                    {
                        "S": '\"${status}\"'
                    }
                ],
                "ComparisonOperator":"EQ"
                }} ' | ${JQ_COMMAND}  '.Items[]|.PrivateIpAddress|.S' | wc -l)
    
    
    re='^[0-9]+$'
    if ! [[ $count =~ $re ]] ; then
        count=0
    fi
    
    echo ${count}
}

# ------------------------------------------------------------------
#          Get Local IPv4 Addresses from DDB
#          Usage: GetIPv4Addrs 
#                 Get list of IPv4 Adrresses
# ------------------------------------------------------------------

GetIPv4Addrs(){
    IPv4=$(${AWS_CMD} dynamodb scan --table-name ${TABLE_NAME} | ${JQ_COMMAND}  '.Items[]|.PrivateIpAddress|.S')
    IPv4=$(echo ${IPv4} | sed s/\"//g)
    echo ${IPv4}
}


# ------------------------------------------------------------------
#          Wait until specific number hosts reach specific state
#          To wait until 5 nodes reach "INSTALL_COMPLETE" status:
#          Usage: WaitForSpecificStatus "INSTALL_COMPLETE=5" etc.
# ------------------------------------------------------------------

WaitForSpecificStatus() {
	log "WaitForSpecificStatus START ($1) in cluster-watch-engine.sh"

    status_count_pair=$1
    if [ -z "$status_count_pair" ]; then
        echo "Invalid Status=count Values!"
        return
    fi
    log "Received ${status_count_pair} in cluster-watch-engine.sh"
    status=$(echo $status_count_pair | /usr/bin/awk -F'=' '{print $1}')
    expected_count=$(echo $status_count_pair | /usr/bin/awk -F'=' '{print $2}')
    log "Checking for ${status} = ${expected_count} times"

    while true; do
      count=$(QueryStatusCount ${status})
      log "${count}..."
      if [ "${count}" -lt "${expected_count}" ]; then
        log "${count}/${expected_count} in ${status} status...Waiting"
        sleep 10
      else
        log "${count} out of ${expected_count} in ${status} status!"
        log "WaitForSpecificStatus END ($1) in cluster-watch-engine.sh"
        return
      fi
    done

}

# ------------------------------------------------------------------
#          Print table
# ------------------------------------------------------------------

Print() {
    ${AWS_CMD} dynamodb scan --table-name ${TABLE_NAME}
}


if [ $CREATE -eq 1 ]; then
    CreateTable ${TABLE_NAME}
    InitMyTable
fi

if [ $GET_IPv4 -eq 1 ]; then
    GetIPv4Addrs
fi

if [ $NEW_STATUS ]; then
    SetMyStatus ${NEW_STATUS}
fi

if [ $NEW_ITEM_PAIR ]; then
    InsertMyKeyValueS ${NEW_ITEM_PAIR}
fi

if [ $QUERY_STATUS ]; then
    QueryStatusCount $QUERY_STATUS
fi


if [ $WAIT_STATUS_COUNT_PAIR ]; then
    WaitForSpecificStatus $WAIT_STATUS_COUNT_PAIR
fi


if [ $PRINT -eq 1 ]; then
    Print
fi

if [ $BLOCK_UNTIL_TABLE_LIVE -eq 1 ]; then
	WaitUntilTableLive
fi

if [ $DELETE_TABLE -eq 1 ]; then
	DeleteTable
fi
