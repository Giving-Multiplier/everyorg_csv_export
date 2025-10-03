# frozen_string_literal: true

require 'dotenv/tasks'
require './app/download_job'
require './app/upload_job'

def with_rescue(exceptions, retries: 5)
  try = 0
  begin
    yield try
  rescue *exceptions => exc
    try += 1
    try <= retries ? retry : raise
  end
end

desc "Downloads file from every.org through headless Chrome"
task download: :dotenv do
  with_rescue([Capybara::ElementNotFound], retries: ENV.fetch('RETRIES', 2).to_i) do |try|
    puts "Download file (attempt #{try + 1})"
    DownloadJob.new.perform(headless: ENV['HEADLESS'] != 'false')
  end
end

desc "Uploads file to custom endpoint"
task upload: :dotenv do
  UploadJob.new.perform
end

task default: [:download, :upload]
