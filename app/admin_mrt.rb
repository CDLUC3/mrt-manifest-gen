# frozen_string_literal: true

require 'sinatra'
require 'sinatra/base'
require 'sinatra/contrib'

require_relative 'lib/app'

set :bind, '0.0.0.0'

register Sinatra::Contrib

get '/*' do |path|
  iconfig = InventoryConfig.new(
    path: path, 
    reload: request.params.fetch('reload', 'false') == 'true'
  )
  erb :index, locals: { iconfig: iconfig }
end

post '/manifest' do
  preview = params.fetch('preview', 'false') == 'true'
  iconfig = InventoryConfig.new(
    path: params[:path]
  )
  manifest = iconfig.inventory.checkm(
    params[:depth], 
    params[:objectformat],
    preview: preview
  )

  if preview
    content_type 'text/plain'
    return manifest
  end

  erb :manifest, locals: { 
    iconfig: iconfig, 
    manifest: manifest,
    name: iconfig.batch_manifest_path
  }
end

post '/download-manifest' do
  content_type 'text/plain'
  attachment params[:name]
  params[:contents].to_s
end
