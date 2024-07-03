# frozen_string_literal: true

require 'dotenv/tasks'
require './app/download_job'
require './app/upload_job'

desc "Downloads file from every.org through headless Chrome"
task download: :dotenv do
  DownloadJob.new.perform
end

desc "Uploads file to custom endpoint"
task upload: :dotenv do
  UploadJob.new.perform
end

task default: [:download, :upload]
