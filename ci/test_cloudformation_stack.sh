#!/bin/bash +ex
# author tonynv@amazon.com
#

VERSION=3.3
# This script validates the cloudformation template then executes stack creation
# Note: build server need to have aws cli install and configure with proper permissions

# Setup Core
cd /root/qs_*/ci

EXEC_DIR=`pwd`
echo "--------------------START--------------------"
echo "Timestamp: `date`"
echo "Starting execution in ${EXEC_DIR}"

# Parms functions

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

# Not implememted eyt
QSENV=$config_global_qsenv
	if [ $QSENV == "prod" ]; then
S3LOCATION=$config_global_prods3location
	else
S3LOCATION=$config_global_cis3bucket
fi

# Check for AWS Cli
if which aws >/dev/null; then
    echo "Looking for awscli:(found)"
else
    echo "Looking for awscli:(not found)"
    echo "Please install awscli and add it to the runtime path"
    exit 1;
fi

### Main ####
if [ -f test_cloudformation_stack.py ];then
        echo "Starting QSPython Test Framework"
        python test_cloudformation_stack.py
else
        echo "Unable to start QSPython Test Framework file:test_cloudformation_stack.py [not found]"
	exit 1
fi

if [ $? -eq 0 ]; then
    echo OK
else
    echo FAIL
    exit 1
fi

if [ -f /root/${config_global_qsname}.html ]; then
	echo "Uploading report ${config_global_qsname}.html"
	REPORTFILE=/root//${config_global_qsname}.html
	aws s3 cp $REPORTFILE s3://quickstart-ci-reports/
fi
