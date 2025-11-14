require 'net/http'
require 'json'
require 'zip'
require 'fileutils'

def download_and_unzip(record_id, path = '.')
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
  
  # Unzip only schema_v2.json files
  extracted_file_names = []
  Zip::File.open(file_path) do |zip_file|
    zip_file.each do |entry|
      next unless entry.name.end_with?('schema_v2.json')
      
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
  record_id = '6347574'
  result = download_and_unzip(record_id)
  puts "Downloaded and extracted: #{result}" if result
end
