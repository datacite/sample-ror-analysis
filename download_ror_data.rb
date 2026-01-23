require 'net/http'
require 'json'
require 'zip'
require 'fileutils'
require 'optparse'

def download_and_unzip(record_id, path = 'data_files')
  # Create directory if it doesn't exist
  FileUtils.mkdir_p(path)
  
  # Downloading the record from Zenodo using the latest API endpoint
  uri = URI("https://zenodo.org/api/records/#{record_id}")
  
  # Follow redirects
  response = nil
  redirect_count = 0
  
  loop do
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      request['Accept'] = 'application/json'
      response = http.request(request)
    end
    
    break unless response.is_a?(Net::HTTPRedirection) && redirect_count < 5
    
    redirect_count += 1
    location = response['location']
    
    # Handle relative redirects
    uri = if location.start_with?('http')
            URI(location)
          else
            URI.join("https://#{uri.host}", location)
          end
  end
  
  unless response.is_a?(Net::HTTPSuccess)
    puts "Error fetching record: #{response.code} #{response.message}"
    puts response.body
    return nil
  end
  
  record = JSON.parse(response.body)
  
  download_link = record['files'][0]['links']['self']
  file_name = record['files'][0]['key']
  file_path = File.join(path, file_name)
  
  # Detect format based on zip filename
  # v2 format: zip filename starts with "v2", files end with schema.json
  # Legacy v1 format: otherwise, files end with schema_v2.json
  is_v2_format = file_name.start_with?('v2')
  schema_suffix = is_v2_format ? 'schema.json' : 'schema_v2.json'
  
  # Download the file
  uri = URI(download_link)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    request = Net::HTTP::Get.new(uri)
    http.request(request) do |response|
      File.open(file_path, 'wb') do |file|
        response.read_body do |chunk|
          file.write(chunk)
        end
      end
    end
  end
  
  # Unzip schema files based on format
  # v2 format: extract files ending with schema.json
  # Legacy v1 format: extract files ending with schema_v2.json
  extracted_file_names = []
  Zip::File.open(file_path) do |zip_file|
    zip_file.each do |entry|
      next unless entry.name.end_with?(schema_suffix)
      
      extracted_file_names << entry.name
      extract_path = File.join(path, entry.name)
      
      # Remove existing file if it exists
      File.delete(extract_path) if File.exist?(extract_path)
      
      entry.extract(extract_path)
    end
  end
  
  if extracted_file_names.any?
    return File.basename(extracted_file_names[0], File.extname(extracted_file_names[0]))
  end
  
  nil
end

# Download the current ROR data file
# Record ID 6347574 is always the ID for the current data file
if __FILE__ == $0
  options = {
    data_dir: 'data_files',
    record_id: '6347574'
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby download_ror_data.rb [options]"
    
    opts.on('--data-dir DIR', 'Directory to download files to (default: data_files/)') do |dir|
      options[:data_dir] = dir
    end
    
    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      puts "\nDownloads the latest ROR data file from Zenodo and extracts schema JSON files."
      puts "Files are downloaded to the specified data directory (default: data_files/)."
      exit
    end
  end.parse!
  
  result = download_and_unzip(options[:record_id], options[:data_dir])
  if result
    puts "Downloaded and extracted: #{result}"
    puts "Files saved to: #{options[:data_dir]}/"
  end
end
