# quickstart-mongodb
## MongoDB on the AWS Cloud

This Quick Start sets up a flexible, scalable AWS environment for MongoDB, and launches MongoDB into a configuration of your choice.

MongoDB is an open source, NoSQL database that provides support for JSON-styled, document-oriented storage systems. 
Its flexible data model enables you to store data of any structure, and it provides full index support, sharding, and replication.

The Quick Start offers two deployment options:

- Deploying MongoDB into a new virtual private cloud (VPC) on AWS
- Deploying MongoDB into an existing VPC on AWS

You can also use the AWS CloudFormation templates as a starting point for your own implementation.

![Quick Start architecture for MongoDB on AWS](https://d0.awsstatic.com/partner-network/QuickStart/datasheets/mongodb-architecture-on-aws.png)

For architectural details, best practices, step-by-step instructions, and customization options, see the 
[deployment guide](https://fwd.aws/3d33d).

To post feedback, submit feature ideas, or report bugs, use the **Issues** section of this GitHub repo.
If you'd like to submit code for this Quick Start, please review the [AWS Quick Start Contributor's Kit](https://aws-quickstart.github.io/). 

## Deploy with Control Tower
You can deploy MongoDB in a customized AWS Control Tower environment to help you set up a secure, multi-account AWS environment using AWS best practices. For details, see [Customizations for AWS Control Tower](https://aws.amazon.com/solutions/implementations/customizations-for-aws-control-tower/). 

The root directory of the MongoDB Quick Start repo includes a `ct` folder with a `manifest.yaml` file to assist you with the AWS Control Tower deployment. This file has been customized for the MongoDB Quick Start. 

In the following sections, you will review and update the settings in this file and then upload it to the S3 bucket that is used for the deployment.

### Review the manifest.yaml file

1. Navigate to the root directory of the MongoDB Quick Start, and open the `manifest.yaml` file, located in the `ct` folder.
2. Confirm that the `region` attribute references the Region where AWS Control Tower is deployed. The default Region is us-east-1. You will update the `regions` attribute (located in the *resources* section) in a later step. 
3. Confirm that the `resource_file` attribute points to the public S3 bucket for the MongoDB Quick Start. Using a public S3 bucket ensures a consistent code base across the different deployment options. 

If you prefer to deploy from your own S3 bucket, update the path as needed.

4. Review each of the `parameters` attributes and update them as needed to match the requirements of your deployment. 
5. Confirm that the `deployment_targets` attribute is configured for either your target accounts or organizational units (OUs). 
6. For the `regions` attribute, add the Region where you plan to deploy the MongoDB Quick Start. The default Region is us-east-1.

### Upload the manifest.yaml file
1. Compress the `manifest.yaml` file and name it `custom-control-tower-configuration.zip`.
2. Upload the `custom-control-tower-configuration.zip` file to the S3 bucket that was created for the AWS Control Tower deployment (`custom-control-tower-configuration-<accountnumber>-<region>`).

The file upload initiates the customized pipeline that deploys the Quick Start to your target accounts.

To post feedback, submit feature ideas, or report bugs, use the **Issues** section of this GitHub repo.
If you'd like to submit code for this Quick Start, please review the [AWS Quick Start Contributor's Kit](https://aws-quickstart.github.io/).

