# frozen_string_literal: true

require 'sinatra'
require 'sinatra/base'
require 'sinatra/contrib'

require_relative 'lib/app'

set :bind, '0.0.0.0'

register Sinatra::Contrib

get '/favicon.ico' do
  content_type 'image/x-icon'
  File.open(File.join(settings.public_folder, 'favicon.ico'), 'rb').read
end

get '/*' do |path|
  iconfig = InventoryConfig.new(
    path: path, 
    reload: request.params.fetch('reload', 'false') == 'true'
  )
  erb :index, locals: { iconfig: iconfig }
end