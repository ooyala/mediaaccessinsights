# Media Streaming Access Insights
This Application orchestrates the AWS cloud to enable media streaming access insights by introspecting the give cloudfront logs. 
In addition, this application auto creates all necessary dashboard (Kibana) views for the media access insights.
Following Info Graphs Shall be generated automatically for analysis and enhancements

* Access Count across Geolocation (Country, City)
* Heat Map on media access
* Media type Access classification (Video / Audio)
* Bitrate access (Average, Max and Min) across Geolocation
* Latency across (Average, Max and Min) Geolocation
* CDN Edge node level access and latency tracking
* Customer Experience Index (Overall & Geo specific)
* Access classified against Device Type and OS Name
* Unique Framerate , Codec, etc. Usage
* CDN cache Hit & Miss Ratio
* Bitrate Ladder view across countries (0-1Mbps, 1-3Mbps, 3-6Mbps, 6-8Mbps)
* Streaming Errors

## Screen Snapshots
![alt text](https://github.com/cloudaffair/mediaaccessinsights/blob/master/misc/Screenshot1.png)
![alt text](https://github.com/cloudaffair/mediaaccessinsights/blob/master/misc/Screenshot2.png)
![alt text](https://github.com/cloudaffair/mediaaccessinsights/blob/master/misc/Screenshot3.png)
![alt text](https://github.com/cloudaffair/mediaaccessinsights/blob/master/misc/Screenshot4.png)
![alt text](https://github.com/cloudaffair/mediaaccessinsights/blob/master/misc/Screenshot5.png)


## High level System View
![alt text](https://github.com/cloudaffair/mediaaccessinsights/blob/master/misc/media_access_insights_schematic_view.png)

## Prerequisite
* AWS Cloud Account
* IAM access for Elastic Search, Cloudfront Logs S3 [ Read Access ] & EC2 Access
* Docker
* Git

## Understanding the configuration

### AWS region that we are going to operate on ..!
aws_region = "<<AWS Region>>"

### Cloudfront Access Bucket Configuration
##### Bucket Name that holds cloudfront access logs
cf_access_bucket = "<<Bucket Name>>"
##### CloudFront Bucket prefix for cloud front logs
cf_prefix = "<<Prefix>>"
##### If some Cloudfront logs need to be excluded from processing, add the pattern here.
cf_access_exclude = "(E1WPESNRTPW3LO.201[7,8]-[0-9]{2})|(E1WPESNRTPW3LO.2019-[0-10]{2}-[0-28]{2})"
##### If the cloudfront logs are available in a different AWS account, add the access key for that account; Optional if the logs are available on the same account 
cf_access_key_id = ""
##### If the cloudfront logs are available in a different AWS account, add the secret key for that account; Optional if the logs are available on the same account
cf_access_secret = ""

### Logstash EC2 configuration
##### Configure SSH Keys that might need access to the Logstash EC2 instance
addition_auth_keys = ["ssh_key_1","ssh_key_2",...]
##### AWS AMI instance ID
logstash_ami = "ami-*********"
##### AWS Subnet ID
logstash_subnet_id = "subnet-XXXXXXXXX"
##### AWS Security groups ID
logstash_security_group_ids = ["sg-******","sg-&&&&&&&&&"...]
##### AWS EC2 instance type
logstash_instance_type = "t2.****"

### Logstash deployer keys
##### SSH public key of the deployer
deployer_key = "ssh-rsa ******"

##### SSH private key for the corresponding deployer key, This will get mounted on the Docker, align the Docker run command appropriately.
ssh_private_key_path = "/root/.ssh/id_rsa"

## Steps
1. Create a Directory "app" and move to the created directory
```ruby
$ mkdir ~/app
$ cd ~/app
```
2. Clone the repository
```ruby
$ git clone https://github.com/cloudaffair/mediaaccessinsights.git
$ cd mediaaccessinsights
```
3. Build Docker Image for `mediaaccessinsights`  
```ruby
$ docker build -t mediaaccessinsights .

#Once the build is complete; check image created
$ docker images
```
![alt text](https://github.com/cloudaffair/mediaaccessinsights/blob/master/misc/docker_images.png)

4. Make configuration changes in file deploy/cfanalysis.auto.tfvars 
(use understanding configuration information to configure)

5. Run Docker using the image created #3. 
```ruby
$ docker run -v ~/repos/mediaaccessinsights/deploy/:/mnt/mediaaccessinsights/deploy/ -v ~/.ssh/:/root/.ssh/ -it mediaaccesssinsights:latest /bin/bash 

# Configure AWS Key , AWS Secret and AWS region
$ aws configure

# Terraform initialisation
$ terraform init

# Below prompting appears
# Initializing the backend...
# bucket
#  The name of the S3 bucket
#
#  Enter a value: <<Bucket Name>>

# key
#  The path to the state file inside the bucket

#  Enter a value: <<Prefix>>

# region
#  The region of the S3 bucket.

#  Enter a value: <<Region>>

$ terraform plan

$ terraform apply

$ terraform output

# This will output the Kibana Url that shall be used to view the access insights Kibana Dashboard
```
![alt text](https://github.com/cloudaffair/mediaaccessinsights/blob/master/misc/terraform_output.png)

## Steps to De-provision the application

1. terraform destroy