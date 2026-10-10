# frozen_string_literal: true

require 'aws-sdk-s3'
require 'csv'
require 'net/http'
require 'uri'
require 'cgi'
require 'nokogiri'
require_relative 'inventory_csv'
require_relative 'metadata_csv'
require_relative 'checkm_file'

## Inventory configuration options for different modes of listing an inventory
class InventoryConfig
  INVENTORY_XML = '/tmp/inventory/inventory-file.xml'
  MAXKEYS = 1000
  MAX_PREFIXES = 250
  MAX_FILES = 25
  MAX_EXTENSIONS = 5
  RELOAD_MINUTES = 30

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

    @inventory_file = InventoryCSV.new(self)
    @metadata_file = MetadataCSV.new(self)

    @inventory_file.load
    @metadata_file.load

    case @mode
    when 's3api'
      @bucket = ENV.fetch('MANIFEST_BUCKET', '')
      @source = "s3://#{@bucket}/#{@prefix}"
      if reload_needed
        @inventory_file.reset
        s3_reload(@bucket, @prefix)
      end
    when 'httpsapi'
      @source = ENV.fetch('MANIFEST_BUCKET', '')
      match = @source.match(%r{^https://([^.]+)\.})
      @bucket = match ? match[1] : ''
      if reload_needed
        @inventory_file.reset
        https_reload("#{@source}/?list-type=2")
      end

    # Not yet implemented
    when 'inventoryfile'
      @file = ENV.fetch('MANIFEST_FILE', '')
      @source = 'file://app/inventory-file.csv'
    when 'inventoryurl'
      @url = ENV.fetch('MANIFEST_URL', '')
      @source = @url
      if reload_needed
        @inventory_file.reset
        url_reload(@url, INVENTORY_LOCALFILE)
      end
      @inventory_file.load
    end
  end

  def https_reload(url, token = '')
    turl = url.dup
    turl += "&max-keys=#{MAXKEYS}"
    turl += "&continuation-token=#{CGI.escape(token)}" unless token.empty?
    url_reload(turl, INVENTORY_XML)
    doc = Nokogiri::XML(File.read(INVENTORY_XML)).remove_namespaces!
    doc.xpath('//Contents').each do |content|
      key = content.xpath('Key').text
      size = content.xpath('Size').text.to_i
      last_modified = content.xpath('LastModified').text
      @inventory_file.add(key, size, last_modified)
    end
    token = ''
    doc.xpath('//NextContinuationToken').each do |nct|
      token = nct.text
    end
    return https_reload(url, token) unless token.empty?

    @inventory_file.save
  end

  # Add path param to perform partial reload
  def url_reload(url, localfile)
    uri = URI.parse(url)
    raise ArgumentError, "Unsupported URL scheme: #{uri.scheme}" unless %w[http https].include?(uri.scheme)

    response = Net::HTTP.get_response(uri)
    raise "Failed to fetch #{uri}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    File.write(@inventory_file.localpath, response.body)
  end

  # Add path param to perform partial reload
  def s3_reload(bucket, prefix)
    s3_client = Aws::S3::Client.new(
      region: ENV.fetch('AWS_REGION', 'us-west-2')
    )
    @inventory_file.init
    continuation_token = nil
    loop do
      response = s3_client.list_objects_v2(
        bucket: bucket,
        prefix: prefix,
        continuation_token: continuation_token,
        max_keys: MAXKEYS
      )
      response.contents.each do |object|
        @inventory_file.add(object.key, object.size, object.last_modified)
      end
      break unless response.is_truncated

      continuation_token = response.next_continuation_token
    end
    @inventory_file.save
  end

  def reload_needed
    return true if @inventory_file.last_updated.nil?
    return true if @inventory_file.count.zero?
    return true if @reload

    @inventory_file.last_updated < (Time.now - (RELOAD_MINUTES * 60)) # Reload if older than 30 minutes
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

    parent
  end

  def parent_name
    @path.empty? ? top_name : '.. (parent)'
  end

  def batch_manifest_path
    return "#{@project}_manifest.checkm" if @path.empty?

    "#{@project}_manifest_#{@path.gsub('/', '_')}.checkm"
  end

  def max_prefixes
    MAX_PREFIXES
  end

  def max_files
    MAX_FILES
  end

  def max_extensions
    MAX_EXTENSIONS
  end

  attr_reader :bucket, :mode, :prefix, :reload, :source, :file, :url, :inventory_file, :metadata_file, :path, :cache_bucket, :project,
    :region
end
