#!/bin/bash +ex
# author tonynv@amazon.com
#

VERSION=3.3
# This script validates the cloudformation template then executes stack creation
# Note: build server need to have aws cli install and configure with proper permissions

# check for cli
if which aws >/dev/null; then
    echo "Looking for awscli:(found)"
else
    echo "Looking for awscli:(not found)"
    echo "Please install awscli and add it to the runtime path"
    exit 1;
fi

cd /root/qs_*/ci



EXEC_DIR=`pwd`
echo "----------START-----------"
echo "Timestamp: `date`"
echo "Starting execution in ${EXEC_DIR}"

# Allow sudo without tty
echo "allowing sudo with out tty"
sed -i -e "s/Defaults    requiretty/Defaults    \!requiretty/" /etc/sudoers

# GET PARMS
get_yml_values() {
local elementkey=$2
local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
awk -F$fs '{
      dlimit = length($1)/2;
      valname[dlimit] = $2;
      for (i in valname) {if (i > dlimit) {delete valname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<dlimit; i++) {vn=(vn)(valname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$elementkey'",vn, $2, $3);
      }
   }'
}

# read yaml file
CI_CONFIG=ci-config.yml
eval $(get_yml_values ${CI_CONFIG} "config_")

if [ $? -eq 0 ];then
echo "YMAL source [complete]"
else
echo "YMAL source [failed]"
exit 1
fi

echo "/root/$config_global_qsname => $config_global_cis3bucket/$config_global_qsname"

aws s3 sync /root/$config_global_qsname $config_global_cis3bucket/$config_global_qsname   --exclude=.git/* --acl public-read
aws s3 ls $config_global_cis3bucket/$config_global_qsname/templates

if [ $? -eq 0 ];then
echo "Templates uploaded to s3 init [complete]"
else 
echo "Template upload failed [error]"
exit 1
fi
#install python dependancies
sudo yum install python-setuptools -y
sudo yum install python-pip -y

echo "Working in `pwd`"

pip >/dev/null
if [ $? -eq 0 ];then
echo "Check Python pip install correctly [installed]"
sudo pip --disable-pip-version-check install -r requirements.txt
chmod 755 test_cloudformation_stack.py
else
echo "Python pip install [failed]"
exit 1
fi

