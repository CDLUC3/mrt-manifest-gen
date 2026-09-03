# frozen_string_literal: true

require 'sinatra'
require 'sinatra/base'
require 'sinatra/contrib'

require_relative 'lib/app.rb'

set :bind, '0.0.0.0'

register Sinatra::Contrib

get '/*' do |path|
  iconfig = InventoryConfig.new(path: path)
  erb :index, locals: { iconfig: iconfig }
end

