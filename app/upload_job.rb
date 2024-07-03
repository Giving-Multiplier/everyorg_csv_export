# frozen_string_literal: true

require 'selenium-webdriver'
require 'capybara'
require 'httparty'

# Upload file to endpoint
class UploadJob
  DOWNLOAD_FOLDER = File.expand_path(File.join(File.dirname(__FILE__), '../tmp/downloads'))

  def perform
    endpoint_url = URI(ENV.fetch('UPLOAD_ENDPOINT'))
    file_path = newest_csv_file(DOWNLOAD_FOLDER)
    raise "No CSV file found in #{DOWNLOAD_FOLDER}" unless file_path

    file = File.new(file_path)

    options = {
      body: {
        every_org_import: { file: file }
      },
      multipart: true
    }

    # Disable SSL verification if in development environment
    if ENV['ENV'] == 'development'
      options[:verify] = false
      puts 'Warning: SSL verification is disabled. This should only be used in development.'
    end

    response = HTTParty.post(endpoint_url, options)

    raise "Status #{response.code}: #{response.body}" if response.code.to_s[0] != '2'

    puts "Status #{response.code}: Uploaded successfully!"
  end

  private

  def newest_csv_file(folder_path)
    Dir.glob(File.join(folder_path, '*.csv'))
       .max_by { |f| File.mtime(f) }
  end
end
