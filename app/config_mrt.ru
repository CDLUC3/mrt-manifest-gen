# frozen_string_literal: true

require 'rack'
require 'rack/contrib'
require 'logger'
require_relative 'admin_mrt'

Sinatra::Application.set :root, File.dirname(__FILE__)
Sinatra::Application.set :views, proc { File.join(root, 'views') }
Sinatra::Application.set :logger, Logger.new($stdout)
Sinatra::Application.set :logging, Logger::DEBUG if ENV.key?('DEBUG')
Sinatra::Application.set :server_settings, :timeout => 300

Sinatra::Application.set :host_authorization => { permitted_hosts: [] }

puts "TB 11111"

run Sinatra::Application
