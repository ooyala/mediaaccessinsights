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
* Streaming Errors

## High level System View
![alt text](https://github.com/cloudaffair/mediaaccessinsights/blob/master/misc/media_access_insights_schematic_view.png)

## Prerequisite
* AWS Cloud Account
* IAM access for Elastic Search, Cloudfront Logs S3 [ Read Access ] & EC2 Access
* Docker
* Git

## Understanding the configuration

## Steps to Deploy
1. Clone the repository
2. docker build -t mediaaccesssinsights .
3. Make configuration changes in file deploy/cfanalysis.auto.tfvars
4. docker run -v ~/repos/mediaaccessinsights/deploy/:/mnt/mediaaccessinsights/deploy/ -v ~/.ssh/:/root/.ssh/ -it mediaaccesssinsights:latest /bin/bash
5. aws configure
6. terraform init
7. terraform plan
8. terraform apply