#!/bin/bash



#################################################################
# Update the OS, install packages, initialize environment vars,
# and get the instance tags
#################################################################
yum -y update
yum install -y jq

source ./orchestrator.sh -i
source ./config.sh

tags=`aws ec2 describe-tags --filters "Name=resource-id,Values=${AWS_INSTANCEID}"`

#################################################################
#  gatValue() - Read a value from the instance tags
#################################################################
getValue() {
    index=`echo $tags | jq '.[]' | jq '.[] | .Key == "'$1'"' | grep -n true | sed s/:.*//g | tr -d '\n'`
    (( index-- ))
    filter=".[$index]"
    result=`echo $tags | jq '.[]' | jq $filter.Value | sed s/\"//g | sed s/Primary.*/Primary/g | tr -d '\n'`
    echo $result
}

##version=`getValue MongoDBVersion`

# MongoDBVersion set inside config.sh
version=${MongoDBVersion}

if [ -z "$version" ] ; then
  version="3.4"
fi

if [ "${version}" == "2.6" ]; then
    echo "[mongodb-org-${version}]
name=MongoDB 2.6 Repository
baseurl=http://downloads-distro.mongodb.org/repo/redhat/os/x86_64/
gpgcheck=0
enabled=1" > /etc/yum.repos.d/mongodb-org-${version}.repo

else
    echo "[mongodb-org-${version}]
name=MongoDB Repository
baseurl=http://repo.mongodb.org/yum/amazon/2013.03/mongodb-org/${version}/x86_64/
gpgcheck=0
enabled=1" > /etc/yum.repos.d/mongodb-org-${version}.repo

fi

# To be safe, wait a bit for flush
sleep 5

yum --enablerepo=epel install node npm -y

yum install -y mongodb-org
yum install -y munin-node
yum install -y libcgroup
yum -y install mongo-10gen-server mongodb-org-shell
yum -y install sysstat

#################################################################
#  Figure out what kind of node we are and set some values
#################################################################
NODE_TYPE=`getValue Name`
IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
SHARD=s`getValue NodeShardIndex`
NODES=`getValue ClusterReplicaSetCount`
MICROSHARDS=`getValue ShardsPerNode`
CONFIGINDEX=`getValue ConfigServerIndex`
SHARDCOUNT=`getValue ClusterShardCount`


#################################################################
#  When there is no sharding, it's a replica set
#################################################################

if [ "${SHARDCOUNT}" == "0" ]; then
  MICROSHARDS=0
fi

#################################################################
#  When there is sharding, make sure atleast one microshard
#################################################################

if [ "${SHARDCOUNT}" != "0" ]; then
  if [ "${MICROSHARDS}" == "0" ]; then
    MICROSHARDS=1
  fi
fi

#  Do NOT use timestamps here!!
# This has to be unique across multiple runs!
UNIQUE_NAME=MONGODB_${TABLE_NAMETAG}_${VPC}


#################################################################
#  Wait for all the nodes to synchronize so we have all IP addrs
#################################################################
if [ "${NODE_TYPE}" == "Primary" ]; then
    ./orchestrator.sh -c -n "${SHARD}_${UNIQUE_NAME}"
    ./orchestrator.sh -s "WORKING" -n "${SHARD}_${UNIQUE_NAME}"
    ./orchestrator.sh -w "WORKING=${NODES}" -n "${SHARD}_${UNIQUE_NAME}"
    IPADDRS=$(./orchestrator.sh -g -n "${SHARD}_${UNIQUE_NAME}")
    read -a IPADDRS <<< $IPADDRS
elif [ "${CONFIGINDEX}" == "0" ]; then
    ./orchestrator.sh -c -n "CONFIG_${UNIQUE_NAME}"
    ./orchestrator.sh -s "WORKING" -n "CONFIG_${UNIQUE_NAME}"
    NODE_TYPE="Config"
elif [ "${CONFIGINDEX}" == "1" ] || [ "${CONFIGINDEX}" == "2" ]; then
    ./orchestrator.sh -b -n "CONFIG_${UNIQUE_NAME}"
    ./orchestrator.sh -w "WORKING=1" -n "CONFIG_${UNIQUE_NAME}"
    ./orchestrator.sh -s "WORKING" -n "CONFIG_${UNIQUE_NAME}"
    NODE_TYPE="Config"
else
    ./orchestrator.sh -b -n "${SHARD}_${UNIQUE_NAME}"
    ./orchestrator.sh -w "WORKING=1" -n "${SHARD}_${UNIQUE_NAME}"
    ./orchestrator.sh -s "WORKING" -n "${SHARD}_${UNIQUE_NAME}"
    NODE_TYPE="Secondary"
    ./orchestrator.sh -w "WORKING=${NODES}" -n "${SHARD}_${UNIQUE_NAME}"
fi


#################################################################
# Make filesystems, set ulimits and block read ahead on ALL nodes
#################################################################
mkfs -t ext4 /dev/xvdf
echo "/dev/xvdf /data ext4 defaults,auto,noatime,noexec 0 0" | tee -a /etc/fstab
mkdir -p /data
mount /data
chown -R mongod:mongod /data
blockdev --setra 32 /dev/xvdf
rm -rf /etc/udev/rules.d/85-ebs.rules
touch /etc/udev/rules.d/85-ebs.rules
echo 'ACTION=="add", KERNEL=="'$1'", ATTR{bdi/read_ahead_kb}="16"' | tee -a /etc/udev/rules.d/85-ebs.rules
echo "* soft nofile 64000
* hard nofile 64000
* soft nproc 32000
* hard nproc 32000" > /etc/limits.conf
#################################################################
# End All Nodes
#################################################################

#################################################################
# Listen to all interfaces, not just local
#################################################################

enable_all_listen() {
  for f in /etc/mongo*.conf
  do
    sed -e '/bindIp/s/^/#/g' -i ${f}
    sed -e '/bind_ip/s/^/#/g' -i ${f}
    echo " Set listen to all interfaces : ${f}"
  done
}


#################################################################
# Setup MongoDB servers and config nodes
#################################################################
mkdir /var/run/mongod
chown mongod:mongod /var/run/mongod

echo "net:" > mongod.conf
echo "  port:" >> mongod.conf
echo "" >> mongod.conf
echo "systemLog:" >> mongod.conf
echo "  destination: file" >> mongod.conf
echo "  logAppend: true" >> mongod.conf
echo "  path: /log/mongod.log" >> mongod.conf
echo "" >> mongod.conf
echo "storage:" >> mongod.conf
echo "  dbPath: /data" >> mongod.conf
echo "  journal:" >> mongod.conf
echo "    enabled: true" >> mongod.conf
echo "" >> mongod.conf
echo "processManagement:" >> mongod.conf
echo "  fork: true" >> mongod.conf
echo "  pidFilePath: /var/run/mongod/mongod.pid" >> mongod.conf
    
if [ "${NODE_TYPE}" != "Config" ]; then
    #################################################################
    #  Enable munin plugins for iostat and iostat_ios
    #################################################################
    ln -s /usr/share/munin/plugins/iostat /etc/munin/plugins/iostat
    ln -s /usr/share/munin/plugins/iostat_ios /etc/munin/plugins/iostat_ios
    touch /var/lib/munin/plugin-state/iostat-ios.state
    chown munin:munin /var/lib/munin/plugin-state/iostat-ios.state

    #################################################################
    # Make the filesystems, add persistent mounts
    #################################################################
    mkfs -t ext4 /dev/xvdg
    mkfs -t ext4 /dev/xvdh

    echo "/dev/xvdg /journal ext4 defaults,auto,noatime,noexec 0 0" | tee -a /etc/fstab
    echo "/dev/xvdh /log ext4 defaults,auto,noatime,noexec 0 0" | tee -a /etc/fstab

    #################################################################
    # Make directories for data, journal, and logs
    #################################################################
    mkdir -p /journal
    mount /journal

    #################################################################
    #  Figure out how much RAM we have and how to slice it up
    #################################################################
    memory=$(vmstat -s | grep "total memory" | sed -e 's/ total.*//g' | sed -e 's/[ ]//g' | tr -d '\n')
    if [ "${MICROSHARDS}" != "0" ]; then
      memory=$(printf %.0f $(echo "${memory} / 1024 / ${MICROSHARDS} * .9 / 1024" | bc))
    else
      memory=$(printf %.0f $(echo "${memory} / 1024 / 1 * .9 / 1024" | bc))
    fi

    if [ ${memory} -lt 1 ]; then
        memory=1
    fi

    #################################################################
    #  Make data directories and add symbolic links for journal files
    #################################################################


    #  Handle case when core sharding count is 0 - Karthik

    if [ "${MICROSHARDS}" != "0" ]; then
      c=0
      while [ $c -lt $MICROSHARDS ]
      do
          mkdir -p /data/${SHARD}-rs${c}
          mkdir -p /journal/${SHARD}-rs${c}

          # Add links for journal to data directory
          ln -s /journal/${SHARD}-rs${c} /data/${SHARD}-rs${c}/journal
          (( c++ ))
      done
    else
      mkdir -p /data/
      mkdir -p /journal/

      # Add links for journal to data directory
      ln -s /journal/ /data/journal
    fi

    mkdir -p /log
    mount /log

    #################################################################
    # Change permissions to the directories
    #################################################################
    chown -R mongod:mongod /journal
    chown -R mongod:mongod /log
    chown -R mongod:mongod /data

    #################################################################
    # Clone the mongod config file and create cgroups for mongod
    #################################################################
    c=0
    port=27017

    #  Handle case when core sharding count is 0 - Karthik
    if [ "${MICROSHARDS}" != "0" ]; then
      echo "" > /etc/cgconfig.conf
      while [ $c -lt $MICROSHARDS ]
      do
          cp mongod.conf /etc/mongod${c}.conf
          (( port++ ))
	
	  #Line below overwrites the conf (fix reported by rick)
          #cp /etc/mongod.conf /etc/mongod${c}.conf
          sed -i "s/.*path:.*/  path: \/log\/mongod${c}.log/g" /etc/mongod${c}.conf
          sed -i "s/.*port:.*/  port: ${port}/g" /etc/mongod${c}.conf
          sed -i "s/.*dbPath:.*/  dbPath: \\/data\\/${SHARD}-rs${c}/g" /etc/mongod${c}.conf
          sed -i "s/.*pidFilePath:.*/  pidFilePath: \/var\/run\/mongod\/mongod${c}.pid/g" /etc/mongod${c}.conf
          echo "replication:" >> /etc/mongod${c}.conf
          echo "  replSetName: ${SHARD}-rs${c}" >> /etc/mongod${c}.conf

          cp /etc/init.d/mongod /etc/init.d/mongod${c}
          sed -i "s/CONFIGFILE=.*/CONFIGFILE=\"\/etc\/mongod${c}\.conf\"/g" /etc/init.d/mongod${c}
          sed -i "s/SYSCONFIG=.*/SYSCONFIG=\"\/etc\/sysconfig\/mongod${c}\"/g" /etc/init.d/mongod${c}

          echo "mount {
                cpuset  = /cgroup/cpuset;
                cpu     = /cgroup/cpu;
                cpuacct = /cgroup/cpuacct;
                memory  = /cgroup/memory;
                devices = /cgroup/devices;
              }

              group mongod${c} {
                perm {
                  admin {
                    uid = mongod;
                    gid = mongod;
                  }
                  task {
                    uid = mongod;
                    gid = mongod;
                  }
                }
                memory {
                  memory.limit_in_bytes = ${memory}G;
                  }
              }" >> /etc/cgconfig.conf


          echo CGROUP_DAEMON="memory:mongod${c}" > /etc/sysconfig/mongod${c}

          (( c++ ))
      done
    else #Karthik
     cp mongod.conf /etc/mongod.conf
     sed -i "s/.*port:.*/  port: ${port}/g" /etc/mongod.conf
     echo "replication:" >> /etc/mongod.conf
     echo "  replSetName: ${SHARD}" >> /etc/mongod.conf

     echo CGROUP_DAEMON="memory:mongod" > /etc/sysconfig/mongod

      echo "mount {
            cpuset  = /cgroup/cpuset;
            cpu     = /cgroup/cpu;
            cpuacct = /cgroup/cpuacct;
            memory  = /cgroup/memory;
            devices = /cgroup/devices;
          }

          group mongod {
            perm {
              admin {
                uid = mongod;
                gid = mongod;
              }
              task {
                uid = mongod;
                gid = mongod;
              }
            }
            memory {
              memory.limit_in_bytes = ${memory}G;
              }
          }" > /etc/cgconfig.conf

      fi


    #################################################################
    #  Start cgconfig, munin-node, and all mongod processes
    #################################################################
    chkconfig cgconfig on
    service cgconfig start

    chkconfig munin-node on
    service munin-node start

    #  Handle case when core sharding count is 0 - Karthik
    if [ "${MICROSHARDS}" != "0" ]; then
      c=0
      while [ $c -lt $MICROSHARDS ]
      do
          chkconfig mongod${c} on
          enable_all_listen
          service mongod${c} start
          (( c++ ))
      done
    else
      chkconfig mongod on
      enable_all_listen
      service mongod start
    fi

    #################################################################
    #  Primaries initiate replica sets
    #################################################################
    if [[ "$NODE_TYPE" == "Primary" ]]; then

        #################################################################
        # Wait unitil all the hosts for the replica set are responding
        #################################################################
        for addr in "${IPADDRS[@]}"
        do
            addr="${addr%\"}"
            addr="${addr#\"}"

            echo ${addr}:${port}
            while [ true ]; do

            echo "mongo --host ${addr} --port ${port}"

mongo --host ${addr} --port ${port} << EOF
use admin
EOF

                if [ $? -eq 0 ]; then
                    break
                fi
                sleep 5
            done
        done

        #################################################################
        # Configure the replica sets, set this host as Primary with
        # highest priority
        #################################################################
        port=27018
        c=0
        while [ $c -lt ${MICROSHARDS} ]; do

            conf="{\"_id\" : \"${SHARD}-rs${c}\", \"version\" : 1, \"members\" : ["
            node=1
            for addr in "${IPADDRS[@]}"
            do
                addr="${addr%\"}"
                addr="${addr#\"}"

                priority=5
                if [ "${addr}" == "${IP}" ]; then
                    priority=10
                fi
                conf="${conf}{\"_id\" : ${node}, \"host\" :\"${addr}:${port}\", \"priority\":${priority}}"

                if [ $node -lt ${NODES} ]; then
                    conf=${conf}","
                fi

                (( node++ ))
            done

            conf=${conf}"]}"
            echo ${conf}

mongo --port ${port} << EOF
rs.initiate(${conf})
EOF

        if [ $? -ne 0 ]; then
            # Houston, we've had a problem here...
            ./signalFinalStatus.sh 1
        fi

            (( port++ ))
            (( c++ ))
        done

        if [ ${SHARDCOUNT} -gt 0 ]; then
            #################################################################
            # Let the replica sets initialize
            #################################################################
            sleep 20

            #################################################################
            # Make sure the config servers are up
            #################################################################
            ./orchestrator.sh -w "WORKING=3" -n "CONFIG_${UNIQUE_NAME}"
            CONFIGADDRS=$(./orchestrator.sh -g -n "CONFIG_${UNIQUE_NAME}")
            read -a CONFIGADDRS <<< $CONFIGADDRS

            for addr in "${CONFIGADDRS[@]}"
            do
                while [ true ]; do

mongo --host ${addr} --port 27030 << EOF
use admin
EOF

                    if [ $? -eq 0 ]; then
                        break
                    fi
                    sleep 5
                done
            done

            #################################################################
            #Setup a mongos service
            #################################################################
            cp mongod.conf /etc/mongos.conf
            sed -i 's/.*path:.*/  path: \/log\/mongos.log/g' /etc/mongos.conf
            sed -i 's/.*port:.*/  port: 27017/g' /etc/mongos.conf
            sed -i 's/.*dbPath:.*/#/g' /etc/mongos.conf
            sed -i 's/.*storage:.*/#/g' /etc/mongos.conf
            sed -i 's/.*journal:.*/#/g' /etc/mongos.conf
            sed -i 's/.*enabled:.*/#/g' /etc/mongos.conf
            sed -i 's/.*pidFilePath:.*/  pidFilePath: \/var\/run\/mongod\/mongos.pid/g' /etc/mongos.conf
            echo "" >> /etc/mongos.conf
            echo "sharding: " >> /etc/mongos.conf
            echo "  configDB: ${CONFIGADDRS[0]}:27030,${CONFIGADDRS[1]}:27030,${CONFIGADDRS[2]}:27030" >> /etc/mongos.conf

            cp /etc/init.d/mongod /etc/init.d/mongos
            sed -i 's/CONFIGFILE=.*/CONFIGFILE="\/etc\/mongos\.conf"/g' /etc/init.d/mongos
            sed -i 's/mongod=.*/mongod="\/usr\/bin\/mongos"/g' /etc/init.d/mongos

            #################################################################
            # Launch mongos and add the shards
            #################################################################
            chkconfig mongos on
            enable_all_listen
            service mongos start

            c=0
            port=27018
            while [ ${c} -lt ${MICROSHARDS} ]
            do

mongo << EOF
sh.addShard("${SHARD}-rs${c}/${IP}:${port}")
EOF

                if [ $? -ne 0 ]; then
                    # Houston, we've had a problem here...
                    ./signalFinalStatus.sh 1
                fi

                (( c++ ))
                (( port++ ))
            done
        fi

        #################################################################
        #  Update status to FINISHED, if this is s0 then wait on the rest
        #  of the nodes to finish and remove orchestration tables
        #################################################################
        ./orchestrator.sh -s "FINISHED" -n "${SHARD}_${UNIQUE_NAME}"

        if [ "${SHARD}" == "s0" ]; then
            last=$(echo "${SHARDCOUNT} - 1" | bc)
            if [ ${last} -lt 0 ]; then
                last=0
            fi

            for i in `seq 0 ${last}` ; do
                ./orchestrator.sh -w "FINISHED=${NODES}" -n "s${i}_${UNIQUE_NAME}"
                ./orchestrator.sh -d -n "s${i}_${UNIQUE_NAME}"
            done
            ./orchestrator.sh -d -n "CONFIG_${UNIQUE_NAME}"
        fi
    else
        #################################################################
        #  Update status of Secondary to FINISHED
        #################################################################
        ./orchestrator.sh -s "FINISHED" -n "${SHARD}_${UNIQUE_NAME}"
    fi

else
    #################################################################
    # Modify the mongod.conf file and make this a config server
    #################################################################
    cp mongod.conf /etc/mongod.conf
    sed -i 's/.*path:.*/  path: \/data\/mongod.log/g' /etc/mongod.conf
    sed -i 's/.*port:.*/  port: 27030/g' /etc/mongod.conf
    sed -i '#s/.*dbPath:.*/  dbpath: \/data/g' /etc/mongod.conf
    sed -i 's/# location.*/configsvr=true/g' /etc/mongod.conf
    echo "" >> /etc/mongod.conf
    echo "sharding:" >> /etc/mongod.conf
    echo "  clusterRole: configsvr" >> /etc/mongod.conf

    mkdir -p /data/configdb/
    chown mongod:mongod /data/configdb/
    chkconfig mongod on
    enable_all_listen
    service mongod start
fi

# TBD - Add custom CloudWatch Metrics for MongoDB

# exit with 0 for SUCCESS
exit 0
