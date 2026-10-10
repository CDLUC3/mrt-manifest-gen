require_relative 'cachefile'
require_relative 'metadata_csv'

class CheckmFile < CacheFile
  FOLDER = 'manifests'

  def initialize(iconfig, checkmpath, manifest_type)
    @metadata = {}
    @manifest_type = manifest_type
    key = "#{iconfig.project}/#{FOLDER}/#{checkmpath}"
    localpath = "/tmp/#{FOLDER}/#{checkmpath}"
    super(iconfig, key, localpath)
  end

  def load
    File.write(@localpath, read)
  end

  def self.object_checkm_header
    %(#%checkm_0.7
#%profile | http://uc3.cdlib.org/registry/ingest/manifest/mrt-ingest-manifest
#%prefix | mrt: | http://merritt.cdlib.org/terms#
#%prefix | nfo: | http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#
#%fields | nfo:fileUrl | nfo:hashAlgorithm | nfo:hashValue | nfo:fileSize | nfo:fileLastModified | nfo:fileName | mrt:mimeType)
  end

  def self.single_file_checkm_header
    %(#%checkm_0.7
#%profile | http://uc3.cdlib.org/registry/ingest/manifest/mrt-single-file-batch-manifest
#%prefix | mrt: | http://merritt.cdlib.org/terms#
#%prefix | nfo: | http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#
#%fields | nfo:fileUrl | nfo:hashAlgorithm | nfo:hashValue | nfo:fileSize | nfo:fileLastModified | nfo:fileName | mrt:primaryIdentifier | mrt:localIdentifier | mrt:creator | mrt:title | mrt:date)
  end

  def self.batch_checkm_header
    %(#%checkm_0.7
#%profile | http://uc3.cdlib.org/registry/ingest/manifest/mrt-batch-manifest
#%prefix | mrt: | http://merritt.cdlib.org/terms#
#%prefix | nfo: | http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#
#%fields | nfo:fileUrl | nfo:hashAlgorithm | nfo:hashValue | nfo:fileSize | nfo:fileLastModified | nfo:fileName | mrt:primaryIdentifier | mrt:localIdentifier | mrt:creator | mrt:title | mrt:date)
  end

  def object_checkm(files)
    buffer = StringIO.new
    buffer.puts CheckmFile.object_checkm_header
    iconfig.metadata_file.metadata[iconfig.path] ||= MetadataCSV.metadata_record
    CSV.generate(col_sep: '|', row_sep: "\n", force_quotes: false) do |csv|
      files.each do |file|
        csv << [
          file_url(file[:key]),
          nil,
          nil,
          file[:size],
          file[:last_modified],
          file[:key],
          nil
       ]
      end
      buffer.puts csv.string
    end
    iconfig.metadata_file.save
    buffer.puts %(#%eof)
    buffer.string
  end

  def single_file_checkm(files)
    buffer = StringIO.new
    buffer.puts CheckmFile.single_file_checkm_header
    CSV.generate(col_sep: '|', row_sep: "\n", force_quotes: false) do |csv|
      files.each do |file|
        iconfig.metadata_file.metadata[file[:key]] ||= MetadataCSV.metadata_record
        csv << [
          file_url(file[:key]),
          nil,
          nil,
          file[:size],
          file[:last_modified],
          file[:key],
          iconfig.metadata_file.metadata[file[:key]][:primary_identifier],
          iconfig.metadata_file.metadata[file[:key]][:local_identifier],
          iconfig.metadata_file.metadata[file[:key]][:creator],
          iconfig.metadata_file.metadata[file[:key]][:title],
          iconfig.metadata_file.metadata[file[:key]][:date]
        ]
      end
      buffer.puts csv.string
    end
    iconfig.metadata_file.save
    buffer.puts %(#%eof)
    buffer.string
  end

  def batch_checkm(filemap, objectformat)
    batch_buffer = StringIO.new
    batch_buffer.puts CheckmFile.batch_checkm_header
    CSV.generate(col_sep: '|', row_sep: "\n", force_quotes: false) do |csv|
      filemap.each do |mapkey, files|
        mkey = manifest_key(mapkey)
        iconfig.metadata_file.metadata[mkey] ||= MetadataCSV.metadata_record
        csv << [
          manifest_url(mapkey),
          nil,
          nil,
          nil,
          nil,
          "#{File.basename(mapkey)}.checkm",
          iconfig.metadata_file.metadata[mkey][:primary_identifier],
          iconfig.metadata_file.metadata[mkey][:local_identifier],
          iconfig.metadata_file.metadata[mkey][:creator],
          iconfig.metadata_file.metadata[mkey][:title],
          iconfig.metadata_file.metadata[mkey][:date]
        ]
        ocheckm = CheckmFile.new(iconfig, manifest_key(mapkey), objectformat)
        ocheckm.write(object_checkm(files)) if objectformat == 'object_checkm'
        ocheckm.write(single_file_checkm(files)) if objectformat == 'single_file_checkm'
      end
      batch_buffer.puts csv.string
    end

    iconfig.metadata_file.save
    batch_buffer.puts %(#%eof)
    batch_buffer.string
  end

  attr_reader :manifest_type
end