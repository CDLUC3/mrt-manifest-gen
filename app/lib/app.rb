# frozen_string_literal: true

require 'aws-sdk-s3'
require 'csv'
require 'net/http'
require 'uri'
require 'nokogiri'
require_relative 'inventory'

## Inventory configuration options for different modes of listing an inventory
class InventoryConfig
  INVENTORY_FILE = '/tmp/inventory-file.csv'
  INVENTORY_XML = '/tmp/inventory-file.xml'

  def initialize(path: '')
    @path = path
    # Allowed values: s3api, httpsapi, inventoryfile, inventoryurl
    @mode = ENV.fetch('MANIFEST_MODE', 's3api')
    @prefix = ENV.fetch('MANIFEST_PREFIX', '')
    @source = ''

    @inventory = Inventory.new
    if File.exist?(INVENTORY_FILE)
      begin
        @inventory.load_from_csv(INVENTORY_FILE, path: path)
      rescue StandardError
        # if the file cannot be read, continue processing
      end
    end

    case @mode
    when 's3api'
      bucket = ENV.fetch('MANIFEST_BUCKET', '')
      @source = "s3://#{bucket}/#{@prefix}"
      s3_reload(bucket, @prefix, path: path) if reload_needed
    when 'inventoryfile'
      @file = ENV.fetch('MANIFEST_FILE', '')
      @source = 'file://app/inventory-file.csv'
    when 'inventoryurl'
      @url = ENV.fetch('MANIFEST_URL', '')
      @source = @url
      url_reload(@url, INVENTORY_FILE, path: path) if reload_needed
      @inventory.load_from_csv(INVENTORY_FILE, path: path)
    when 'httpsapi'
      @source = ENV.fetch('MANIFEST_BUCKET', '')
      https_reload("#{@source}/?list-type=2") if reload_needed
    end
  end

  def https_reload(url)
    url_reload(url, INVENTORY_XML)
    @inventory.file_init(INVENTORY_FILE)
    doc = Nokogiri::XML(File.read(INVENTORY_XML)).remove_namespaces!
    doc.xpath('//Contents').each do |content|
      key = content.xpath('Key').text
      size = content.xpath('Size').text.to_i
      last_modified = content.xpath('LastModified').text
      @inventory.add(key, size, last_modified, path: @path, filepath: INVENTORY_FILE)
    end
  end

  def url_reload(url, localfile, path: '')
    uri = URI.parse(url)
    raise ArgumentError, "Unsupported URL scheme: #{uri.scheme}" unless %w[http https].include?(uri.scheme)

    response = Net::HTTP.get_response(uri)
    raise "Failed to fetch #{uri}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    File.write(localfile, response.body)
  end

  def s3_reload(bucket, prefix, path: '')
    s3_client = Aws::S3::Client.new(
      region: ENV.fetch('AWS_REGION', 'us-west-2')
    )
    @inventory.file_init(INVENTORY_FILE)
    continuation_token = nil
    loop do
      response = s3_client.list_objects_v2(
        bucket: bucket,
        prefix: prefix,
        continuation_token: continuation_token
      )
      response.contents.each do |object|
        @inventory.add(object.key, object.size, object.last_modified, path: path, filepath: INVENTORY_FILE)
      end
      break unless response.is_truncated

      continuation_token = response.next_continuation_token
    end
  end

  def last_updated
    return unless File.exist?(INVENTORY_FILE)

    File.mtime(INVENTORY_FILE)
  end

  def reload_needed
    return true if last_updated.nil?
    return true if @inventory.count.zero?

    last_updated < (Time.now - 180) # Reload if older than 3 minutes
  end

  def prefix_path(folder)
    @path.empty? ? "/#{folder}" : "/#{@path}/#{File.basename(folder)}"
  end

  def top_path
    '/'
  end

  def top_name
    '/ (top)'
  end

  def parent_path
    return top_path if @path.empty?

    parent = File.dirname(@path)
    return top_path if parent == '.'

    "/#{parent}"
  end

  def parent_name
    @path.empty? ? top_name : '.. (parent)'
  end

  attr_reader :mode, :prefix, :reload, :source, :file, :url, :inventory, :path
end
