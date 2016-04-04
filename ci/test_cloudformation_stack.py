#!/usr/bin/env python
#author tonynv@amazon.com
#This program does launch tests for quickstart cloudformation templates 
#Test configuration is defined in ci-config.yml
#If you override regions in test make sure to use yml array
#Version 3.2

import yaml
import boto3
import sys
import urllib
import json
import uuid
import re
import collections
import time
import datetime
import botocore


#Configuration Varibles
yml_configuration="ci-config.yml"
with open(yml_configuration, 'r') as ciconf:
    ciyml = yaml.safe_load(ciconf)

global_qsname=ciyml['global']['qsname']
global_reporting=ciyml['global']['qsname']
reporting_html="/root/" + global_qsname + ".html"


if ( ciyml['global']['qsenv'] == "prod"):
        #Prodbucket not impleemted yet need a more mature ci
        #cis3bucket=ciyml['global']['prods3bucket']
        print "prod is not implemented yet"
else:
        cis3bucket=ciyml['global']['cis3bucket']

#QuickStact Project Root Folder
qss3root=cis3bucket+"/"+global_qsname
qss3rooturl=qss3root.replace("s3://", "https://s3.amazonaws.com/")
table_header="<table width=720 style=\"border:1px solid black;\">"

# QuickStart Test Framework
def good_json(jsonparms):
  try:
    json_object = json.loads(jsonparms)
  except ValueError, e:
    return False
  return True

def regxfind(reobj,dataline):
# strip for
    sg = reobj.search(dataline)
    if (sg):
        return str(sg.group())
    else: 
        return str('Not-found')

def cfnvalidate():
        for test in ciyml['tests'].keys():
                qstemplate=qss3rooturl +"/templates/"+ str(ciyml['tests'][test]['template_file'])
                qsparmeter=qss3rooturl +"/templates/"+ str(ciyml['tests'][test]['parameter_input'])
		print "---------------------------------------------------------"
                print "Performing template validation for QuickStart project [" + test +"]"
                print "[]Template File: " + qstemplate
                print "[]Parmeter File: " + qsparmeter

                try:
                        cfnconect= boto3.client('cloudformation','us-west-1')
                        cfnconect.validate_template(TemplateURL=qstemplate)
                except Exception as e: 
                        sys.stderr.write("FATAL: QuickStart Template Validation Error:\n%s\n" % "ERROR:Check template systax")
			return
                else:
                        sys.stderr.write("PASS: QuickStart Template Validation Successful!\n")
                qstemplate=qss3rooturl +"/templates/"+ str(ciyml['tests'][test]['template_file'])
                qsparmeterdata= urllib.urlopen(qss3rooturl +"/templates/"+ str(ciyml['tests'][test]['parameter_input']))
		print "Performing validation json parmeter: " + qsparmeter
		jsonstatus = good_json(qsparmeterdata.read())
		if jsonstatus == True:
			print "PASS: QuickStart Parmeter file for " + test + "is valid [continuting]"
		else:
			sys.exit("FATAL:QuickStart Parmeter file for " + test + " is not valid [failed test]")
		print "---------------------------------------------------------"

def qstartlaunch():
	stack_ids = []
	for test in ciyml['tests'].keys():
                qstemplate=qss3rooturl +"/templates/"+ str(ciyml['tests'][test]['template_file'])
                qsparmeterdata= urllib.urlopen(qss3rooturl +"/templates/"+ str(ciyml['tests'][test]['parameter_input']))
		qsparmeter=json.loads(qsparmeterdata.read())
		cfcapabilities = []
		cfcapabilities.append('CAPABILITY_IAM')
                if 'regions' in ciyml['tests'].get(test) :
                        region_override= ciyml['tests'][test]['regions']
                        print "********************************************************"
                        print "Overriding regions in test" ":" + str(test) + "with =>" +  str(region_override)
                        print str(ciyml['tests'][test]['parameter_input'])
                        print "********************************************************"
			for region in ciyml['tests'][test]['regions']:
				id=str(uuid.uuid4())
				qsstackname="qsci-"+str(global_qsname)+"-"+region+"-"+id[:3]
				qsstack=qsstackname.replace("_","")
				print "---------------------------------------------------------"
	                	print "Performing launch tests on  QuickStart project [" + global_qsname +"]"
	                	print "\t Running Test: " + str(test)
	                	print "\t Test Region : " + str(region)
	                	print "\t Template file : " + str(qstemplate)
	                	print "\t Parmeters file : " + str(qss3rooturl +"/templates/"+ str(ciyml['tests'][test]['parameter_input']))
	                	print "\t Parmeters : " + str(qsparmeter)
				# Remove try from cfnconect for full debug
				try:
	                        	cfnconect= boto3.client('cloudformation',region)
	        			stack_ids.append(cfnconect.create_stack(StackName=qsstack, DisableRollback=True, TemplateURL=qstemplate, Parameters=qsparmeter, Capabilities=cfcapabilities))
	    			except Exception as e:
	                        	sys.stderr.write("FATAL: Unable to create stack")
					print 'e', e 
	        			print "FATAL:QuickStart Launch [failed]"
					print "\t Test Region : " + str(region)
	                        	print "\t Template file : " + str(qstemplate)
	                        	print "\t Parmeters : " + str(qsparmeter)
	return stack_ids

def cfnstackexists(stackname,region):
	exists=0
	cfnconect= boto3.client('cloudformation',region)
	try:
		current_stacks=(cfnconect.describe_stacks(StackName=stackname))
		exists="yes"
	except botocore.exceptions.ClientError as e:
		exists="no"
	return exists
		
def cfnstackstatus(listofstackdata):
    runing_stacks = dict()
    for stack in stacks:
	region=""
	stackname=""
	for current_test in stack:
		stackid=stack['StackId']
		region_re=re.compile('(?<=:)(.\w\-.+(\w*)\-\d)(?=:)')
		stackname_re=re.compile('qsci.(\w*)-(\w*)-(\w*)-(\d*)-(\w){3}')
		region=regxfind(region_re,stackid)
		stackname=regxfind(stackname_re,stackid)

		#print "[Debug] Region: " + region + "StackName: " + stackname
		still_running=cfnstackexists(stackname,region)
		if still_running == "yes":
        		cfnconect= boto3.client('cloudformation',region)
			teststatus=(cfnconect.describe_stacks(StackName=stackname))
			#print "debuging...."
			#print teststatus
			#print "debuging...."
    			run_info = []
			for run in teststatus['Stacks']:
				run_info.append(stackname)
				run_info.append(region)
				run_info.append(run.get('StackStatus'))
			runing_stacks[stackname] = run_info
		else:
			exit	
    return runing_stacks

def getteststatus(stackid):
    region_re=re.compile('(?<=:)(.\w\-.+(\w*)\-\d)(?=:)')
    stackname_re=re.compile('qsci.(\w*)-(\w*)-(\w*)-(\d*)-(\w){3}')
    region=regxfind(region_re,stackid)
    stackname=regxfind(stackname_re,stackid)
    testinfo = []
    cfnconect= boto3.client('cloudformation',region)
    try:
        testquery=(cfnconect.describe_stacks(StackName=stackname))
        status = "active"
        for result in testquery['Stacks']:
            testinfo.append(stackname)
            testinfo.append(region)
            testinfo.append(result.get('StackStatus'))
	    if result.get('StackStatus') == 'CREATE_IN_PROGRESS' or result.get('StackStatus') == 'DELETE_IN_PROGRESS':
            	testinfo.append(1)
	    else:
		testinfo.append(0)
    except botocore.exceptions.ClientError as e:
        status = "inactive"
	testinfo.append(stackname)
        testinfo.append(region)
        testinfo.append("USER_DELETED")
        testinfo.append(0)
    return testinfo

def qstestreport(stackid):
        region_re=re.compile('(?<=:)(.\w\-.+(\w*)\-\d)(?=:)')
	stackname_re=re.compile('qsci.(\w*)-(\w*)-(\w*)-(\d*)-(\w){3}')
        region=regxfind(region_re,stackid)
        stackname=regxfind(stackname_re,stackid)
        cfnconect= boto3.client('cloudformation',region)
	try:
            testquery=(cfnconect.describe_stacks(StackName=stackname))
            status = "active"
            for result in testquery['Stacks']:
               status=result.get('StackStatus')
	except botocore.exceptions.ClientError as e:
            status = "USER_DELETED"
        print stackname +"\t"+ region +"\t" + status
	if status != 'CREATE_COMPLETE':
		colorstatus="#FF3300"
	else: 
		colorstatus="#CCFF99"

	h_file.write("<tr><td>"+stackname+"</td><td>"+region+"</td><td bgcolor="+colorstatus+">"+status+"<td></tr>\n")

def cfncleanup(stackid):
        region_re=re.compile('(?<=:)(.\w\-.+(\w*)\-\d)(?=:)')
        stackname_re=re.compile('qsci.(\w*)-(\w*)-(\w*)-(\d*)-(\w){3}')
        region=regxfind(region_re,stackid)
        stackname=regxfind(stackname_re,stackid)
	still_around=cfnstackexists(stackname,region)
	if still_around == "yes":
		cfnconect= boto3.client('cloudformation',region)
		print "Cleaning up ... "+ stackname
        	cfnconect.delete_stack(StackName=stackname)

def flushfile(hfile):
    with open(hfile, 'w'): pass
    return 

if __name__ == "__main__":
    waittimer=5
    active_tests=1
    cfnvalidate()
    stacks=qstartlaunch()
    # Start Polling 
    flushfile(reporting_html)
    with open(reporting_html, "a") as h_file:
	h_file.write(table_header)
    	h_file.write("<tr><td bgcolor=black style=\"border: 1px solid black;\"><font color=white>QuickStart Test Stack</font></td>\
		      <td bgcolor=black style=\"border: 1px solid black;\"><font color=white>Tested Region</font></td>\
		      <td bgcolor=black style=\"border: 1px solid black;\"><font color=white>Test Status</font></td></tr>\n")

	while (active_tests > 0):
           current_active_tests = 0
           for stack in stacks:
	  	stackquery=getteststatus(stack['StackId'])
	    	current_active_tests = stackquery[3] + current_active_tests
	    	print stackquery[0] + "\t \t| \t" + stackquery[1] + "\t | \t" +  stackquery[2]
            	active_tests=current_active_tests
	time.sleep(waittimer)

	# Generate Report
    	for stack in stacks:
	    qstestreport(stack['StackId'])

	h_file.write("<tr><td colspan=3>Tested on: "+ datetime.datetime.now().strftime("%A, %d. %B %Y %I:%M%p") +"</td></tr>")
	h_file.write("</table>\n")
	h_file.close()
	
  	for stack in stacks:
            cfncleanup(stack['StackId'])


