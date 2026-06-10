require "test_helper"
require "capybara/rails"
require "selenium/webdriver"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  if ENV["SELENIUM_REMOTE_URL"].present?
    driven_by :selenium,
              using: :headless_chrome,
              screen_size: [ 1400, 900 ],
              options: {
                browser: :remote,
                url: ENV["SELENIUM_REMOTE_URL"]
              }

    Capybara.server_host         = "0.0.0.0"
    Capybara.always_include_port = true
    Capybara.app_host            = "http://#{ENV.fetch("APP_HOSTNAME", "rails-test")}"
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]
  end
end
