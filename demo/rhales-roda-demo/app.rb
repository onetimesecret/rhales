require 'logger'
require 'roda'
require 'sequel'
require 'securerandom'
require 'bcrypt'
require 'rack/session'

# Add the lib directory to the load path
$:.unshift(File.expand_path('../../lib', __dir__))
require 'rhales'
require 'rhales/integrations/tilt'
require 'mail'

Mail.defaults do
  delivery_method :smtp, {
    address: 'localhost',
    port: 1025,
    domain: 'localhost.localdomain',
    enable_starttls_auto: false,
  }
end

class RhalesDemo < Roda
  # Demo accounts for testing - matches migration seed data
  DEMO_ACCOUNTS = [
    {
      email: 'demo@example.com',
      password: 'demo123',
      role: 'user',
    },
    {
      email: 'admin@example.com',
      password: 'admin123',
      role: 'admin',
    },
  ].freeze

  # Database setup - use file-based SQLite for persistence
  DB = Sequel.sqlite(File.join(__dir__, 'db', 'demo.db'))

  DB.extension :date_arithmetic

  logger = Logger.new($stdout)

  class << self
    def get_secret
      secret = DB[:_demo_secrets].get(:value) # `get` automatically gets the first row

      if secret.nil?
        secret = SecureRandom.hex(64)
        DB[:_demo_secrets].insert_conflict.insert(
          name: 'migration-default',
          value: secret,
        )
      end

      secret
    end
  end

  # Run migrations if needed
  Sequel.extension :migration
  Sequel::Migrator.run(DB, File.join(__dir__, 'db', 'migrate'))

  secret_value = RhalesDemo.get_secret
  logger.info("[demo] Secret value: #{secret_value}")

  opts[:root] = File.dirname(__FILE__)

  # Configure Rhales with Tilt integration
  Rhales.configure do |config|
    config.template_paths  = [File.join(opts[:root], 'templates')]
    config.cache_templates = false
  end

  # Use Roda's render plugin with Rhales engine
  # Note: Layout handling is done by Rhales ViewComposition, not Roda
  plugin :render,
    engine: 'rue',
    views: File.join(opts[:root], 'templates'),
    layout: true

  plugin :flash
  plugin :sessions, secret: secret_value, key: 'rhales-demo.session'
  plugin :route_csrf

  # Simple Rodauth configuration
  plugin :rodauth do
    db DB

    # Used for HMAC operations in various Rodauth features like password reset
    # tokens, email verification, etc. If it changes, existing tokens become
    # invalid (users lose pending password resets, etc).
    # e.g. SecureRandom.hex(64)
    hmac_secret ENV['RODAUTH_HMAC_SECRET'] || secret_value

    enable :change_login, :change_password, :close_account, :create_account,
      :lockout, :login, :logout, :remember, :reset_password, :verify_account,
      :otp_modify_email, :otp_lockout_email, :recovery_codes, :sms_codes,
      :disallow_password_reuse, :password_grace_period, :active_sessions,
      :verify_login_change, :change_password_notify, :confirm_password,
      :email_auth, :disallow_common_passwords

    login_redirect '/'
    logout_redirect '/'
    create_account_redirect '/'

    # Set custom routes to match our templates
    create_account_route 'register'

    # Skip status checks for demo simplicity
    skip_status_checks? true

    # Use email as login - param name should match form field
    login_param 'login'
    login_confirm_param 'login'

    # The following hooks are kept to document their availability and naming.
    # They can be implemented with custom logic as needed.
    # before_login
    # before_create_account
    # after_login_failure
    # after_create_account
    # login_error_flash
    # create_account_error_flash
    # account_from_login
    # password_match?

    # AVAILABLE VARIABLES FOR ALL RODAUTH VIEWS:
    # Global (auto-injected by plugin):
    #   - rodauth.* : Full Rodauth object (csrf_tag, logged_in?, etc.)
    #   - flash_notice : Success message from flash[:notice]
    #   - flash_error : Error message from flash[:error]
    #   - current_path : Current URL path
    #   - request_method : HTTP method
    #   - demo_accounts : Demo credentials array
    #
    # View-specific variables available via rodauth object:
    #   - login.rue: rodauth.login, rodauth.login_error_flash
    #   - create_account.rue: rodauth.login_confirm, rodauth.create_account_error_flash
    #   - verify_account.rue: rodauth.verify_account_key_value
    #   - change_login.rue: rodauth.login, rodauth.login_confirm
    #   - change_password.rue: rodauth.new_password_param, rodauth.password_confirm_param
    #   - reset_password.rue: rodauth.reset_password_key_value
    #   - close_account.rue: (requires current password confirmation)
    #   - logout.rue: (minimal data, typically POST-only)
    #
    # Additional enabled features (templates auto-created if needed):
    #   - lockout.rue: rodauth.lockout_error_flash (account lockout after failed attempts)
    #   - remember.rue: rodauth.remember_param (remember login checkbox)
    #   - verify_login_change.rue: rodauth.verify_login_change_key_value (email change verification)
    #   - change_password_notify.rue: (notification after password change)
    #   - confirm_password.rue: rodauth.password_param (password confirmation for sensitive operations)
    #   - email_auth.rue: rodauth.email_auth_key_value (passwordless email authentication)
    #   - recovery_codes.rue: rodauth.recovery_codes (backup 2FA codes)
    #   - sms_codes.rue: rodauth.sms_phone, rodauth.sms_code (SMS 2FA)
    #   - otp_modify_email.rue: rodauth.otp_* (TOTP setup/modification)
    #   - active_sessions.rue: rodauth.active_sessions (manage multiple login sessions)
    #
    # Templates automatically discovered in templates/ directory:
    #   login.rue, create_account.rue, logout.rue, verify_account.rue,
    #   change_login.rue, change_password.rue, reset_password.rue, close_account.rue
  end

  # Simple auth helper - uses Rodauth's session management
  def current_user
    return nil unless rodauth.logged_in?

    @current_user ||= DB[:accounts].where(id: rodauth.session_value).first
  end

  def roda_secret
    @roda_secret ||= RhalesDemo.get_secret
  end

  def logged_in?
    rodauth.logged_in?
  end

  # Set CSP header using upstream Rhales functionality
  def set_csp_header
    # Get CSP header from request env (set by Rhales view rendering)
    csp_header                                  = request.env['csp_header']
    response.headers['Content-Security-Policy'] = csp_header if csp_header
  end

  route do |r|
    r.rodauth

    # Home route - shows different content based on auth state
    r.root do
      result = if logged_in?
        locals = {
          'welcome_message' => "Welcome back, #{current_user[:email]}!",
          'login_time' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
          # Dashboard specific props
          'features' => [
            {
              'title' => 'Authenticated Access',
              'description' => 'Only visible when logged in',
              'icon' => '🔐',
            },
            {
              'title' => 'Session Management',
              'description' => 'Powered by Rodauth',
              'icon' => '👤',
            },
            {
              'title' => 'API Integration',
              'description' => 'Fetch data with hydrated endpoints',
              'icon' => '⚡',
            },
          ],
          'api_endpoints' => {
            'user' => '/api/user',
            'demo_data' => '/api/demo-data',
          },
        }
        view('dashboard',
          locals: template_locals(locals),
          layout: false,
        )
      else
        # Home page props
        locals = {
          'page_type' => 'home',
          'features' => [
            {
              'title' => 'Single File Components',
              'description' => 'Combine templates, data, and logic in one file',
              'icon' => '📦',
            },
            {
              'title' => 'Type-Safe Hydration',
              'description' => 'Zod schemas ensure contract safety',
              'icon' => '🛡️',
            },
            {
              'title' => 'Security First',
              'description' => 'CSP nonces and HTML escaping by default',
              'icon' => '🔒',
            },
            {
              'title' => 'Framework Agnostic',
              'description' => 'Works with Roda, Sinatra, Rails, and more',
              'icon' => '🔧',
            },
          ],
        }
        view('home', locals: template_locals(locals), layout: false)
      end

      # Set CSP header after view rendering
      set_csp_header
      result
    end

    # Simple API endpoint for RSFC hydration demo
    r.get 'api/user' do
      response['Content-Type'] = 'application/json'

      if logged_in?
        {
          authenticated: true,
          user: current_user,
          server_time: Time.now.iso8601,
        }.to_json
      else
        { authenticated: false }.to_json
      end
    end

    # Demo data endpoint
    r.get 'api/demo-data' do
      response['Content-Type'] = 'application/json'
      {
        message: 'This data was loaded dynamically via JavaScript!',
        timestamp: Time.now.to_i,
        random_number: rand(1000),
      }.to_json
    end
  end

  # Helper method to provide common template data
  # Returns hash with :client_data and :server_data keys for Rhales v2.0+
  def template_locals(additional_locals = {})
    # Separate client (serialized to browser) from server (template-only) data
    client_defaults = {
      # Authentication state
      'authenticated' => respond_to?(:logged_in?) ? logged_in? : false,

      # Demo accounts for login page
      'demo_accounts' => DEMO_ACCOUNTS,
    }

    server_defaults = {
      # Layout props (required by layouts/main.rue)
      'app_name' => 'Rhales Demo',
      'year' => Time.now.year,

      # Flash messages (already handled by Tilt, but keeping for consistency)
      'flash_notice' => respond_to?(:flash) ? flash['notice'] : nil,
      'flash_error' => respond_to?(:flash) ? flash['error'] : nil,
    }

    # Merge additional locals
    client_data = client_defaults.merge(additional_locals.fetch('client_data', {}))
    server_data = server_defaults.merge(additional_locals.fetch('server_data', {}))

    # Also merge any top-level keys into client for backward compatibility
    additional_locals.each do |key, value|
      next if key == 'client_data' || key == 'server_data'
      client_data[key] = value
    end

    {
      client_data: client_data,
      server_data: server_data,
    }
  end
end
