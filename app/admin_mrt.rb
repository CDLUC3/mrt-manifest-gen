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
  puts 111
  iconfig = InventoryConfig.new(
    path: params[:path]
  )
  puts 222
  if preview
    content_type 'text/plain'
    puts 333
    return iconfig.inventory_file.object_checkm_preview if params[:depth].empty?
    puts 444

    return iconfig.inventory_file.checkm_preview(params[:depth])
    puts 555
  end

  if params[:depth] =~ /^(mrt-ingest-manifest|mrt-single-file-batch-manifest)$/
    puts 666
    checkm_file = CheckmFile.new(iconfig, iconfig.batch_manifest_path, params[:depth])
    puts 777
    manifest = if params[:depth] == 'mrt-ingest-manifest'
                 puts 888
                 checkm_file.object_checkm(iconfig.inventory_file.descendant_files(iconfig.path))
               else
                 puts 999
                 checkm_file.single_file_checkm(iconfig.inventory_file.descendant_files(iconfig.path))
               end
  else
    checkm_file = CheckmFile.new(iconfig, iconfig.batch_manifest_path, :batch_checkm)
    puts 1111
    manifest = checkm_file.batch_checkm(
      iconfig.inventory_file.descendant_files_by_depth(iconfig.path, params[:depth].to_i)
    )
    puts 2222
  end

  puts 3333
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
