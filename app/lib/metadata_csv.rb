# frozen_string_literal: true

require_relative 'cachefile'

## Metadata file CSV. Metadata will be injected into checkm entries with matching keys.
class MetadataCSV < CacheFile
  FOLDER = 'metadata'
  FILENAME = 'metadata-file.csv'

  def initialize(iconfig)
    @metadata = {}
    ENV.fetch('CACHE_BUCKET', '')
    key = "#{iconfig.project}/#{FOLDER}/#{FILENAME}"
    localpath = "/tmp/#{FOLDER}/#{FILENAME}"
    super(iconfig, key, localpath)
  end

  def init
    super
    CSV.open(@localpath, 'w', col_sep: ',', row_sep: "\n") do |csv|
      csv << %w[key primary_identifier local_identifier creator title date]
    end
    File.read(@localpath)
  end

  def load
    @metadata = {}
    CSV.parse(read, headers: true, col_sep: ',', row_sep: "\n") do |row|
      key = row['key']
      @metadata[key] = {
        primary_identifier: row['primary_identifier'],
        local_identifier: row['local_identifier'],
        creator: row['creator'],
        title: row['title'],
        date: row['date']
      }
    end
  end

  def save
    CSV.open(@localpath, 'a', col_sep: ',', row_sep: "\n") do |csv|
      @metadata.each do |key, meta_info|
        csv << [
          key,
          meta_info[:primary_identifier],
          meta_info[:local_identifier],
          meta_info[:title],
          meta_info[:creator],
          meta_info[:date]
        ]
      end
    end
    write(File.read(@localpath))
  end

  def self.metadata_record
    {
      primary_identifier: nil,
      local_identifier: nil,
      title: nil,
      creator: nil,
      date: nil
    }
  end

  attr_reader :metadata
end
