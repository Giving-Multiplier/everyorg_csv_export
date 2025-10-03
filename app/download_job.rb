# frozen_string_literal: true
require 'selenium-webdriver'
require 'capybara'
require 'capybara-screenshot'
require 'securerandom'
STDOUT.sync = true

# Automation to login to every.org, download the CSV
class DownloadJob
  DOWNLOAD_FOLDER = File.expand_path(File.join(File.dirname(__FILE__), '../tmp/downloads'))

  attr_accessor :headless

  def perform(headless: true)
    @headless = headless
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO

    begin
      # Always start with completely fresh session
      setup_fresh_session

      puts "Download folder: #{DOWNLOAD_FOLDER}"

      # Login
      puts 'Logging into every.org'
      login_to_every_org

      # Navigate and download
      download_donations_csv

      puts 'Done'
    rescue Capybara::ElementNotFound => e
      log_error_details(e)
      raise e
    ensure
      cleanup_session
    end
  end

  private

  def login_to_every_org
    browser.visit "https://www.every.org/#{ENV.fetch('EVERY_ORG_PROJECT')}/admin"
    browser.fill_in 'Email', with: ENV.fetch('EVERY_ORG_LOGIN')
    browser.fill_in 'Password', with: ENV.fetch('EVERY_ORG_PASSWORD')
    browser.click_button('Log in with email')
    browser.click_link('Navigate to nonprofit admin page')
    puts '✓ Login successful'
  end

  def download_donations_csv
    # Setting filters
    puts 'Open donations page'
    browser.visit "https://www.every.org/#{ENV.fetch('EVERY_ORG_PROJECT')}/admin/donations"
    browser.find("div[role='columnheader']", text: 'Created')
    sleep 2 # first fully load page

    puts 'Setting filters'
    browser.click_button('Payment info', wait: 60)
    browser.find(:css, "input[value='Error,Expired']").find(:xpath, './/..').click
    browser.click_link('Download')

    # Downloading file
    puts 'Downloading file'
    result = wait_for_file(DOWNLOAD_FOLDER, 'donations-*.csv')
    raise 'File not downloaded correctly' unless result

    puts "✓ File downloaded: #{result}"
  end

  def setup_fresh_session
    # CRITICAL: Clean up any existing sessions first
    force_cleanup_all_sessions

    chromium_paths = [
      '/app/.chrome-for-testing/chrome-linux64/chrome',     # Heroku
      '/opt/homebrew/bin/chromium',                         # Homebrew ARM64
      '/Applications/Chromium.app/Contents/MacOS/Chromium', # Downloaded version
      '/usr/local/bin/chromium'                             # Other installations
    ]

    # Create unique driver name for each attempt (important for Rake retries)
    @driver_name = :"chrome_#{Process.pid}_#{Time.now.to_i}_#{SecureRandom.hex(4)}"

    # Config with enhanced stability options
    Capybara.register_driver @driver_name do |app|
      options = Selenium::WebDriver::Chrome::Options.new

      # Basic options
      if headless
        options.add_argument('--headless=new')  # Use new headless mode
      end

      # Essential Heroku/stability options
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-dev-shm-usage')
      options.add_argument('--disable-gpu')
      options.add_argument('--window-size=1980,1080')

      # Enhanced stability options for Heroku
      options.add_argument('--memory-pressure-off')
      options.add_argument('--disable-background-timer-throttling')
      options.add_argument('--disable-backgrounding-occluded-windows')
      options.add_argument('--disable-renderer-backgrounding')
      options.add_argument('--disable-extensions')
      options.add_argument('--disable-plugins')
      options.add_argument('--disable-default-apps')
      options.add_argument('--no-first-run')
      options.add_argument('--disable-hang-monitor')
      options.add_argument('--disable-prompt-on-repost')
      options.add_argument('--disable-features=TranslateUI')
      options.add_argument('--disable-web-security')
      options.add_argument('--disable-blink-features=AutomationControlled')
      options.add_argument('--disable-extensions')
      options.exclude_switches << 'enable-automation'

      # CRITICAL: Force completely fresh profile for each Rake retry
      options.add_argument("--user-data-dir=/tmp/chrome-#{Process.pid}-#{Time.now.to_i}")

      # Resource limits for Heroku
      options.add_argument('--max_old_space_size=512')
      options.add_argument('--memory-pressure-off')

      # Download preferences
      options.add_preference(:download, prompt_for_download: false, default_directory: DOWNLOAD_FOLDER)
      options.add_preference('plugins.plugins_disabled', ["Chrome PDF Viewer"])

      # Set binary path
      chromium_binary = chromium_paths.find { |path| File.exist?(path) }
      options.binary = chromium_binary if chromium_binary

      Capybara::Selenium::Driver.new(
        app,
        browser: :chrome,
        options: options
      )
    end

    # Configure Capybara to use our unique driver
    Capybara.current_driver = @driver_name
    Capybara.javascript_driver = @driver_name
    Capybara.configure do |config|
      config.default_max_wait_time = 30 # seconds
    end
    Capybara.enable_aria_label = true

    # Initialize browser and test session
    @browser = Capybara.current_session
    @browser.visit('about:blank')  # Quick test to ensure browser works
    @browser.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")

    puts "✓ Fresh session created with driver: #{@driver_name}"
  end

  def force_cleanup_all_sessions
    # Clean up any existing browser instance
    if defined?(@browser) && @browser
      begin
        @browser.driver.quit if @browser.driver.respond_to?(:quit)
      rescue => e
        puts "Warning: Error quitting existing browser: #{e.message}"
      end
      @browser = nil
    end

    # Reset ALL Capybara sessions (critical for Rake retries)
    Capybara.reset_sessions!

    # Force garbage collection to clean up any lingering references
    GC.start

    # Kill any zombie Chrome processes (Heroku specific)
    begin
      if ENV['DYNO'] # We're on Heroku
        system('pkill -f chrome >/dev/null 2>&1')
        sleep(1)
      end
    rescue => e
      puts "Warning: Could not kill Chrome processes: #{e.message}"
    end

    puts "✓ Forced cleanup of all existing sessions"
  end

  def cleanup_session
    return unless defined?(@browser) && @browser

    begin
      puts "Cleaning up session..."

      # Quit the specific browser instance
      if @browser.driver && @browser.driver.respond_to?(:quit)
        @browser.driver.quit
        puts "✓ Browser driver quit successfully"
      end
    rescue => e
      puts "Warning during cleanup: #{e.message}"
    ensure
      @browser = nil

      # Reset sessions after cleanup
      Capybara.reset_sessions!

      # Note: Driver registration cleanup is handled by Capybara.reset_sessions!
      # No need to manually remove driver registrations (deprecated in Capybara 3.40+)

      puts "✓ Session cleanup complete"
    end
  end

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

  def browser
    @browser || raise("Browser not initialized - call setup_fresh_session first")
  end

  def driver
    browser.driver.browser
  end

  def log_error_details(error)
    @logger.error("Error: #{error.message}")

    begin
      if defined?(@browser) && @browser && @browser.driver
        @logger.error("Browser logs: #{driver.logs.get(:browser)}")
        Capybara::Screenshot.screenshot_and_save_page
      end
    rescue => log_error
      @logger.error("Could not capture additional error details: #{log_error.message}")
    end
  end
end
