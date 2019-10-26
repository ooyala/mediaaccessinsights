1. Clone the repository

2. docker build -t mediaaccesssinsights .
3. docker run -v ~/repos/mediaaccessinsights/deploy/:/mnt/mediaaccessinsights/deploy/ -v ~/.ssh/:/root/.ssh/ -it mediaaccesssinsights:latest /bin/bash

4. aws configure
5. terraform init
6. terraform plan
7. terraform apply