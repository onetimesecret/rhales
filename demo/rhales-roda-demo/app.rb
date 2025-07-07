require 'roda'
require 'sequel'
require 'securerandom'
require 'bcrypt'
require 'rack/session'

# Add the lib directory to the load path
$:.unshift(File.expand_path('../../lib', __dir__))
require 'rhales'

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
  # Database setup - use file-based SQLite for persistence
  DB = Sequel.sqlite(File.join(__dir__, 'db', 'demo.db'))

  # Run migrations if needed
  Sequel.extension :migration
  Sequel::Migrator.run(DB, File.join(__dir__, 'db', 'migrate'))

  opts[:root] = File.dirname(__FILE__)

  # We're using Rhales instead of Roda's render plugin
  plugin :flash
  plugin :sessions, secret: SecureRandom.hex(64), key: 'rhales-demo.session'
  plugin :route_csrf

  # Simple Rodauth configuration
  plugin :rodauth do
    db DB
    enable :login, :logout, :create_account

    login_redirect '/'
    logout_redirect '/'
    create_account_redirect '/'

    # Set custom routes to match our templates
    create_account_route 'register'

    # Skip status checks for demo simplicity
    skip_status_checks? true

    # Use email as login
    login_param 'email'
    login_confirm_param 'email'

    # Use our Rhales templates instead of ERB
    login_view do
      scope.instance_eval { rhales_render('auth/login') }
    end

    create_account_view do
      scope.instance_eval { rhales_render('auth/register') }
    end

    # Use Rhales template for logout page
    logout_view do
      scope.instance_eval { rhales_render('auth/logout') }
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

  def logged_in?
    rodauth.logged_in?
  end

  # Rhales render helper using adapter classes with layout support
  def rhales_render(template_name, business_data = {}, layout: 'layouts/main', **extra_data)
    # Automatically include common view data (flash, rodauth, etc.)
    auto_data = {
      'flash_notice' => flash['notice'],
      'flash_error' => flash['error'],
      'current_path' => request.path,
      'request_method' => request.request_method,
      'rodauth' => rodauth,
    }

    # Merge data layers: auto_data provides base, then business_data, then extra_data
    merged_data = auto_data.merge(business_data).merge(extra_data)

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
      business_data: merged_data,
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
        business_data: merged_data.merge(content: content_html, authenticated: logged_in?),
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
