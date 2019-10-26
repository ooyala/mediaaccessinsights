FROM mbalasubramanian/ubuntu-ruby-terraform-base:latest

ENV APP_PATH /mnt/mediaaccessinsights
RUN mkdir -p $APP_PATH

COPY . $APP_PATH

WORKDIR $APP_PATH/deploy