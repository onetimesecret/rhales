require 'logger'
require 'roda'
require 'sequel'
require 'securerandom'
require 'bcrypt'
require 'rack/session'

# Add the lib directory to the load path
$:.unshift(File.expand_path('../../lib', __dir__))
require 'rhales'
require 'mail'

Mail.defaults do
  delivery_method :smtp, {
    address: 'localhost',
    port: 1025,
    domain: 'localhost.localdomain',
    enable_starttls_auto: false,
  }
end

# Simple adapter classes for Rhales context objects
class SimpleRequest
  attr_reader :path, :method, :ip, :params, :env

  def initialize(path:, method:, ip:, params:, env: {})
    @path   = path
    @method = method
    @ip     = ip
    @params = params
    @env    = env
  end
end

class SimpleSession
  attr_reader :authenticated, :csrf_token

  def initialize(authenticated:, csrf_token:)
    @authenticated = authenticated
    @csrf_token    = csrf_token
  end

  def authenticated?
    @authenticated
  end
end

class SimpleAuth < Rhales::Adapters::BaseAuth
  attr_reader :authenticated, :email, :user_data

  def initialize(authenticated:, email:, user_data:)
    @authenticated = authenticated
    @email         = email
    @user_data     = user_data
  end

  def anonymous?
    !@authenticated
  end

  def theme_preference
    'light'
  end

  def user_id
    @user_data&.dig(:id)
  end

  def display_name
    @user_data&.dig(:email)
  end
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

  # We're using Rhales instead of Roda's render plugin
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
    # before_login {}
    # before_create_account {}
    # after_login_failure {}
    # after_create_account {}
    #
    # login_error_flash do
    #   super()
    # end
    #
    # create_account_error_flash do
    #   super()
    # end
    #
    # account_from_login do |login|
    #   super(login)
    # end
    #
    # password_match? do |password|
    #   super(password)
    # end

    # ===== RODAUTH VIEW CUSTOMIZATIONS =====
    # Replace default ERB templates with Rhales RSFC templates
    #
    # AVAILABLE VARIABLES FOR ALL RODAUTH VIEWS:
    # - rodauth.* : Full Rodauth object with all methods (csrf_tag, logged_in?, etc.)
    # - flash_notice : Success/info message from flash[:notice]
    # - flash_error : Error message from flash[:error]
    # - current_path : request.path (current URL path)
    # - request_method : HTTP method (GET/POST/etc.)
    # - demo_accounts : Array of demo credentials (demo-specific)
    #
    # ADDING GLOBAL PROPS:
    # Modify auto_data hash in rhales_render method (line ~219)
    #
    # ADDING VIEW-SPECIFIC PROPS:
    # Pass hash as 2nd param: rhales_render('template', { key: 'value' })

    # LOGIN VIEW - rodauth.login_route ('/login')
    # Specific variables: rodauth.login, rodauth.login_error_flash
    login_view do
      scope.instance_eval { rhales_render('auth/login') }
    end

    # REGISTRATION VIEW - rodauth.create_account_route ('/register')
    # Specific variables: rodauth.login_confirm, rodauth.create_account_error_flash
    create_account_view do
      scope.instance_eval { rhales_render('auth/register') }
    end

    # LOGOUT VIEW - rodauth.logout_route ('/logout')
    # Specific variables: (logout is typically POST-only, minimal data needed)
    logout_view do
      scope.instance_eval { rhales_render('auth/logout') }
    end

    # VERIFY ACCOUNT VIEW - rodauth.verify_account_route ('/verify-account')
    # Specific variables: rodauth.verify_account_key_value (token from email link)
    verify_account_view do
      scope.instance_eval { rhales_render('auth/verify_account') }
    end

    # CHANGE LOGIN VIEW - rodauth.change_login_route ('/change-login')
    # Specific variables: rodauth.login (current login), rodauth.login_confirm
    change_login_view do
      scope.instance_eval { rhales_render('auth/change_login') }
    end

    # CHANGE PASSWORD VIEW - rodauth.change_password_route ('/change-password')
    # Specific variables: rodauth.new_password_param, rodauth.password_confirm_param
    change_password_view do
      scope.instance_eval { rhales_render('auth/change_password') }
    end

    # RESET PASSWORD VIEW - rodauth.reset_password_route ('/reset-password')
    # Specific variables: rodauth.reset_password_key_value (token from email)
    reset_password_view do
      scope.instance_eval { rhales_render('auth/reset_password') }
    end

    # CLOSE ACCOUNT VIEW - rodauth.close_account_route ('/close-account')
    # Specific variables: (requires current password confirmation)
    close_account_view do
      scope.instance_eval { rhales_render('auth/close_account') }
    end
  end

  # Configure Rhales
  Rhales.configure do |config|
    config.template_paths  = [File.join(opts[:root], 'templates')]
    config.default_locale  = 'en'
    config.cache_templates = false  # Disable for demo
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

  # Rhales render helper using adapter classes with layout support
  #
  # PARAMETERS:
  # - template_name: Path to .rue template (e.g. 'auth/login')
  # - props: Hash of template-specific variables
  # - layout: Layout template (default: 'layouts/main', set to nil for no layout)
  # - **extra_data: Additional keyword arguments merged as props
  #
  # EXAMPLE USAGE:
  # rhales_render('auth/login', { custom_message: 'Welcome' }, layout: 'auth_layout')
  # rhales_render('partial', {}, layout: nil)  # No layout
  def rhales_render(template_name, props = {}, layout: 'layouts/main', **extra_data)
    # AUTO-INJECTED GLOBAL VARIABLES (available to all templates):
    auto_data = {
      'flash_notice' => flash['notice'],        # Success message from flash
      'flash_error' => flash['error'],          # Error message from flash
      'current_path' => request.path,           # Current URL path
      'request_method' => request.request_method, # HTTP method (GET/POST/etc)
      'rodauth' => rodauth,                     # Full Rodauth object
      'demo_accounts' => DEMO_ACCOUNTS,         # Demo credentials (app-specific)
    }

    # Merge data layers: auto_data provides base, then props, then extra_data
    merged_data = auto_data.merge(props).merge(extra_data)

    # Create adapter instances for Rhales context
    request_data = SimpleRequest.new(
      path: request.path,
      method: request.request_method,
      ip: request.ip,
      params: request.params,
      env: {
        'nonce' => SecureRandom.hex(16),
        'request_id' => SecureRandom.hex(8),
        'flash_notice' => flash['notice'],
        'flash_error' => flash['error'],
      },
    )

    session_data = SimpleSession.new(
      authenticated: logged_in?,
      csrf_token: nil, # Rodauth handles CSRF tokens
    )

    # Create auth adapter object
    auth_data = if logged_in?
      SimpleAuth.new(
        authenticated: true,
        email: current_user[:email],
        user_data: {
          id: current_user[:id],
          email: current_user[:email],
        },
      )
    else
      SimpleAuth.new(
        authenticated: false,
        email: nil,
        user_data: nil,
      )
    end

    # Render content template first
    view         = Rhales::View.new(
      request_data,
      session_data,
      auth_data,
      nil, # locale_override
      props: merged_data,
    )
    content_html = view.render(template_name)

    # If layout is specified, render it with content
    if layout
      # Create new view for layout with content data
      layout_view = Rhales::View.new(
        request_data,
        session_data,
        auth_data,
        nil,
        props: merged_data.merge(content: content_html, authenticated: logged_in?),
      )

      layout_view.render(layout)
    else
      content_html
    end
  end

  route do |r|
    r.rodauth

    # Home route - shows different content based on auth state
    r.root do
      if logged_in?
        rhales_render('dashboard', {
          welcome_message: "Welcome back, #{current_user[:email]}!",
          login_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        }
        )
      else
        rhales_render('home', {})
      end
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
end
