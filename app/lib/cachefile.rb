require 'aws-sdk-s3'
require 'csv'
require 'uri'
require 'stringio'

class CacheFile
  def initialize(iconfig, key, localpath)
    @iconfig = iconfig
    @key = key
    @localpath = localpath
    @last_updated = nil
  end

  def exists?
    s3_client.head_object(bucket: iconfig.cache_bucket, key: @key)
    true
  rescue Aws::S3::Errors::NotFound
    false
  end

  def read
    if exists?
      obj = s3_client.get_object(bucket: iconfig.cache_bucket, key: @key)
      @last_updated = obj.last_modified
      obj.body.read
    else
      init
    end
  end

  def write(content)
    s3_client.put_object(bucket: iconfig.cache_bucket, key: @key, body: content)
  end

  def load
  end

  def save
    write('')
  end

  def init
    `mkdir -p #{File.dirname(@localpath)}`
    File.write(@localpath, '')
    @last_updated = Time.now
    ''
  end

  def file_url(file)
    "https://#{iconfig.bucket}.s3.#{iconfig.region}.amazonaws.com/#{pathencode(file)}"
  end

  def manifest_key(mapkey)
    key = "#{iconfig.project}/#{CheckmFile::FOLDER}/"
    key += "#{pathencode(iconfig.path)}/" unless iconfig.path.empty?
    key += "#{pathencode(mapkey)}.checkm"
    key
  end

  def pathencode(path)
    path.split('/').map { |s| CGI.escape(s) }.join('/')
  end

  def manifest_url(mapkey)
    manifest = "https://#{iconfig.cache_bucket}.s3.us-west-2.amazonaws.com/" \
               "#{iconfig.project}/#{CheckmFile::FOLDER}/"
    manifest += "#{pathencode(iconfig.path)}/" unless iconfig.path.empty?
    manifest += "#{pathencode(mapkey)}.checkm"
    manifest
  end

  def self.format_int(vint)
    vint.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  attr_reader :last_updated, :localpath, :iconfig, :key

  private

  def s3_client
    @s3_client ||= Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
  end
end