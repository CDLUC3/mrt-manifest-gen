# frozen_string_literal: true

require_relative 'cachefile'

## Inventory cache to speed up lambda navigation
class PreviewFile < CacheFile
  FOLDER = 'preview'
  FILENAME = 'preview-file.csv'

  def initialize(iconfig, data)
    key = "#{iconfig.project}/#{FOLDER}/#{FILENAME}"
    localpath = "/tmp/#{FOLDER}/#{FILENAME}"
    @data = data
    super(iconfig, key, localpath)
  end

  def save
    write(@data)
  end

end
