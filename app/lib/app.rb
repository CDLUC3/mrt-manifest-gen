# frozen_string_literal: true

require 'aws-sdk-s3'
require 'csv'
require 'net/http'
require 'uri'
require 'cgi'
require 'nokogiri'
require_relative 'inventory'

## Inventory configuration options for different modes of listing an inventory
class InventoryConfig
  INVENTORY_FILE = '/tmp/inventory/inventory-file.csv'
  INVENTORY_XML = '/tmp/inventory/inventory-file.xml'
  MAXKEYS = 5

  def initialize(path: '', reload: false)
    @path = path
    @reload = reload
    # Allowed values: s3api, httpsapi, inventoryfile, inventoryurl
    @cache_bucket = ENV.fetch('CACHE_BUCKET', '')
    @project = ENV.fetch('PROJECT_NAME', 'not-applicable')
    @mode = ENV.fetch('MANIFEST_MODE', 's3api')
    @prefix = ENV.fetch('MANIFEST_PREFIX', '')
    @region = ENV.fetch('AWS_REGION', 'us-west-2')
    @source = ''

    @inventory = Inventory.new(self)
    @inventory.load_csv

    case @mode
    when 's3api'
      @bucket = ENV.fetch('MANIFEST_BUCKET', '')
      @source = "s3://#{@bucket}/#{@prefix}"
      if reload_needed
        @inventory.reset
        s3_reload(@bucket, @prefix, path: path)
      end
    when 'httpsapi'
      @source = ENV.fetch('MANIFEST_BUCKET', '')
      match = @source.match(%r{^https://([^.]+)\.})
      @bucket = match ? match[1] : ''
      if reload_needed
        @inventory.reset
        https_reload("#{@source}/?list-type=2&max-keys=#{MAXKEYS}")
      end

    # Not yet implemented
    when 'inventoryfile'
      @file = ENV.fetch('MANIFEST_FILE', '')
      @source = 'file://app/inventory-file.csv'
    when 'inventoryurl'
      @url = ENV.fetch('MANIFEST_URL', '')
      @source = @url
      if reload_needed
        @inventory.reset
        url_reload(@url, INVENTORY_FILE, path: path)
      end
      @inventory.load_from_csv(path: path)
    end
  end

  def https_reload(url, token = '')
    turl = url.dup
    turl += "&continuation-token=#{CGI.escape(token)}" unless token.empty?
    url_reload(turl, INVENTORY_XML)
    @inventory.file_init
    doc = Nokogiri::XML(File.read(INVENTORY_XML)).remove_namespaces!
    doc.xpath('//Contents').each do |content|
      key = content.xpath('Key').text
      size = content.xpath('Size').text.to_i
      last_modified = content.xpath('LastModified').text
      @inventory.add(key, size, last_modified)
    end
    doc.xpath('//NextContinuationToken').each do |token|
      return https_reload(url, token.text)
    end
    @inventory.save
  end

  def url_reload(url, localfile, path: '')
    uri = URI.parse(url)
    raise ArgumentError, "Unsupported URL scheme: #{uri.scheme}" unless %w[http https].include?(uri.scheme)

    response = Net::HTTP.get_response(uri)
    raise "Failed to fetch #{uri}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    `mkdir -p /tmp/inventory`
    File.write(localfile, response.body)
  end

  def s3_reload(bucket, prefix, path: '')
    s3_client = Aws::S3::Client.new(
      region: ENV.fetch('AWS_REGION', 'us-west-2')
    )
    @inventory.file_init
    continuation_token = nil
    loop do
      response = s3_client.list_objects_v2(
        bucket: bucket,
        prefix: prefix,
        continuation_token: continuation_token,
        max_keys: MAXKEYS
      )
      response.contents.each do |object|
        @inventory.add(object.key, object.size, object.last_modified)
      end
      break unless response.is_truncated

      continuation_token = response.next_continuation_token
    end
    @inventory.save
  end

  def reload_needed
    return true if @inventory.last_updated.nil?
    return true if @inventory.count.zero?
    return true if @reload

    @inventory.last_updated < (Time.now - 180) # Reload if older than 3 minutes
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

  def parent_path
    parent = File.dirname(@path)
    parent == '.' ? '' : parent
  end

  def batch_manifest_path
    return "#{@project}_manifest.checkm" if @path.empty?

    "#{@project}_manifest_#{@path.gsub('/', '_')}.checkm"
  end

  attr_reader :bucket, :mode, :prefix, :reload, :source, :file, :url, :inventory, :path, :cache_bucket, :project,
    :region
end
