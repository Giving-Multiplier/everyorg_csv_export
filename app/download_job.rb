# frozen_string_literal: true

require 'selenium-webdriver'
require 'capybara'

# Autmation to login to every.org, download the CSV
class DownloadJob
  DOWNLOAD_FOLDER = File.expand_path(File.join(File.dirname(__FILE__), '../tmp/downloads'))

  attr_accessor :headless

  def perform(headless: true)
    @headless = headless
    logger = Logger.new(STDOUT)
    setup

    puts "Download folder: #{DOWNLOAD_FOLDER}"

    # Login
    puts 'Logging into every.org'
    browser.visit "https://www.every.org/#{ENV.fetch('EVERY_ORG_PROJECT')}/admin"
    browser.fill_in 'Email', with: ENV.fetch('EVERY_ORG_LOGIN')
    browser.fill_in 'Password', with: ENV.fetch('EVERY_ORG_PASSWORD')
    browser.click_button('Log in with email')
    browser.click_link('Navigate to nonprofit admin page')

    # Setting filters
    puts 'Open donations page'
    browser.visit "https://www.every.org/#{ENV.fetch('EVERY_ORG_PROJECT')}/admin/donations"
    browser.find("div[role='columnheader']", text: 'Created')
    sleep 2 # first fully load page
    puts 'Setting filters'
    browser.click_button('Filter', wait: 60)
    browser.find(:css, "input[value='Error,Expired']").find(:xpath, './/..').click
    browser.click_link('Download')

    # Downloading file
    puts 'Downloading file'
    result = wait_for_file(DOWNLOAD_FOLDER, 'donations-*.csv')

    raise 'File not downloaded correctly' unless result

    teardown

    puts 'Done'
  rescue Capybara::ElementNotFound => e
    raise e unless ENV.fetch('ENV', 'production') == 'development'
    logger.error(e.message)
    logger.error(driver.logs.get(:browser))
    browser.save_and_open_page
  end

  private

  def wait_for_file(folder_path, file_pattern, timeout = 30)
    Timeout.timeout(timeout) do
      loop do
        matching_file = Dir.glob(File.join(folder_path, file_pattern)).first

        return matching_file if matching_file

        sleep 1
      end
    end
  rescue Timeout::Error
    nil
  end

  def teardown
    driver.quit
  end

  def setup
    chromium_paths = [
      '/app/.chrome-for-testing/chrome-linux64/chrome',     # Heroku
      '/opt/homebrew/bin/chromium',                         # Homebrew ARM64
      '/Applications/Chromium.app/Contents/MacOS/Chromium', # Downloaded version
      '/usr/local/bin/chromium'                             # Other installations
    ]

    # Config
    Capybara.register_driver :chrome do |app|
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless') if headless
      options.add_argument('--no-sandbox')
      options.add_argument('--window-size=1980,1080')
      options.add_preference(:download, prompt_for_download: false, default_directory: DOWNLOAD_FOLDER)
      options.add_preference('plugins.plugins_disabled', ["Chrome PDF Viewer"])

      chromium_binary = chromium_paths.find { |path| File.exist?(path) }
      options.binary = chromium_binary if chromium_binary

      Capybara::Selenium::Driver.new(
        app,
        browser: :chrome,
        options: options
      )
    end
    Capybara.javascript_driver = :chrome
    Capybara.configure do |config|
      config.default_max_wait_time = 30 # seconds
      config.default_driver = :chrome
    end
    Capybara.enable_aria_label = true
  end

  def browser
    @browser ||= Capybara.current_session
  end

  def driver
    @driver ||= browser.driver.browser
  end
end
