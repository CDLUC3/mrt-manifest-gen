# frozen_string_literal: true

require 'sinatra'
require 'sinatra/base'
require 'sinatra/contrib'

require_relative 'lib/app'

set :bind, '0.0.0.0'
set :public_folder, File.dirname(__FILE__) + '/public'

register Sinatra::Contrib

get '/*' do |path|
  iconfig = InventoryConfig.new(
    path: path, 
    reload: request.params.fetch('reload', 'false') == 'true'
  )
  erb :index, locals: { iconfig: iconfig }
end
