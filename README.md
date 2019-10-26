1. Clone the repository
2. docker build -t mediaaccesssinsights .
3. Make configuration changes in file deploy/cfanalysis.auto.tfvars
4. docker run -v ~/repos/mediaaccessinsights/deploy/:/mnt/mediaaccessinsights/deploy/ -v ~/.ssh/:/root/.ssh/ -it mediaaccesssinsights:latest /bin/bash
5. aws configure
6. terraform init
7. terraform plan
8. terraform apply