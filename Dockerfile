#*********************************************************************
#   Copyright 2019 Regents of the University of California
#   All rights reserved
#*********************************************************************
# See https://itnext.io/docker-rails-puma-nginx-postgres-999cd8866b18

FROM public.ecr.aws/lambda/ruby:3.4
ARG BUILD_TAG

RUN dnf -y update && dnf -y upgrade
RUN dnf -y install gcc make git

ENV RACK_CONFIG=app/config_mrt.ru
ENV TZ=America/Los_Angeles

WORKDIR /var/task
# Add Admin Tool Code to the image
COPY Gemfile* /var/task/

# Bundle dependencies
RUN bundle install

COPY . /var/task
COPY .bundle/config /var/task/.bundle/config
RUN bundle install

ENTRYPOINT ["bundle", "exec", "puma", "app/config_mrt.ru"]
