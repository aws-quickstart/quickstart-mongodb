# MongoDB on the AWS Cloud
> MongoDB version 3.6

## Deployment Options
AWS Quick Start Team

This Quick Start reference deployment guide includes architectural considerations and configuration steps for deploying a MongoDB cluster on the Amazon Web Services (AWS) cloud. It discusses best practices for deploying MongoDB on AWS using services such as Amazon Elastic Compute Cloud (Amazon EC2) and Amazon Virtual Private Cloud (Amazon VPC). It also provides links to automated AWS CloudFormation templates that you can leverage for your deployment or launch directly into your AWS account.

The guide is for IT infrastructure architects, administrators, and DevOps professionals who are planning to implement or extend their MongoDB workloads on the AWS cloud.

The following links are for your convenience. Before you launch the Quick Start, please review the architecture, configuration, network security, and other considerations discussed in this guide.

## Change Log
### April 2017
* Changed version to MongoDB 3.6
* Removed Sharding Option and Configuration Parameters.
* Simplified init script init_replica.sh
* Added test cases
* Implemented MongoDB Security Checklist
  * Enabled User Auth. A root admin user is setup during quick start launch
  * All the replica set nodes are setup with a keyfile to enable internal key authentication. 

### March 2017
* Disabled transparent hugepages
* Changed file system to xfs
* Refactored template into nested modules.
  * mongodb-master.template - launches MongoDB replica set in a new VPC
  * mongodb.template - launches MongoDB replica set in an existing VPC
  * mongodb-node.template - launches one node in MongoDB replica set
* Added quickstart-aws-vpc and quickstart-linux-bastion as submodules