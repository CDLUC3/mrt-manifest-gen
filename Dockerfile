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

# This structure assumes the following:
#   lambda_function.rb contains a module name LambdaFunctions which contains a class Handler
# That class conforms to the method signature expected for a Lambda.
CMD [ "lambda_function.LambdaFunctions::Handler.process" ]
