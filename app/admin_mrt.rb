# frozen_string_literal: true

require 'sinatra'
require 'sinatra/base'
require 'sinatra/contrib'

require_relative 'lib/app'

set :bind, '0.0.0.0'

register Sinatra::Contrib

get '/' do
  iconfig = InventoryConfig.new(
    path: '',
    reload: request.params.fetch('reload', 'false') == 'true'
  )
  erb :index, locals: { iconfig: iconfig }
end

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
  if preview
    content_type 'text/plain'
    return iconfig.inventory_file.object_checkm_preview if params[:depth].empty?

    return iconfig.inventory_file.checkm_preview(params[:depth])

  end

  if params[:depth].empty?
    checkm_file = CheckmFile.new(iconfig, iconfig.batch_manifest_path, params[:objectformat])
    manifest = if params[:objectformat] == 'object_checkm'
                 checkm_file.object_checkm(iconfig.inventory_file.descendant_files(iconfig.path))
               else
                 checkm_file.single_file_checkm(iconfig.inventory_file.descendant_files(iconfig.path))
               end
  else
    checkm_file = CheckmFile.new(iconfig, iconfig.batch_manifest_path, :batch_checkm)
    manifest = checkm_file.batch_checkm(
      iconfig.inventory_file.descendant_files_by_depth(iconfig.path, params[:depth].to_i),
      params[:objectformat]
    )
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
