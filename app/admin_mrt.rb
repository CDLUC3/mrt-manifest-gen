# frozen_string_literal: true

require 'sinatra'
require 'sinatra/base'
require 'sinatra/contrib'

set :bind, '0.0.0.0'

register Sinatra::Contrib

get '/' do
  erb :index
end

