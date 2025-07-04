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
  attr_reader :path, :method, :ip, :params

  def initialize(path:, method:, ip:, params:)
    @path = path
    @method = method
    @ip = ip
    @params = params
  end
end

class SimpleSession
  attr_reader :authenticated, :csrf_token

  def initialize(authenticated:, csrf_token:)
    @authenticated = authenticated
    @csrf_token = csrf_token
  end

  def authenticated?
    @authenticated
  end
end

class SimpleAuth < Rhales::Adapters::BaseAuth
  attr_reader :authenticated, :email, :user_data

  def initialize(authenticated:, email:, user_data:)
    @authenticated = authenticated
    @email = email
    @user_data = user_data
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
  # Database setup - use simple SQLite
  DB = Sequel.sqlite

  # Run basic migration for accounts table
  DB.create_table?(:accounts) do
    primary_key :id
    String :email, null: false, unique: true
    String :password_hash, null: false
  end

  # Create demo user if it doesn't exist
  unless DB[:accounts].where(email: 'demo@example.com').first
    password_hash = BCrypt::Password.create('demo123')
    DB[:accounts].insert(email: 'demo@example.com', password_hash: password_hash)
  end

  opts[:root] = File.dirname(__FILE__)

  # We're using Rhales instead of Roda's render plugin
  plugin :flash
  plugin :sessions, secret: SecureRandom.hex(64), key: 'rhales-demo.session'

  # Simple Rodauth configuration
  plugin :rodauth do
    db DB
    accounts_table :accounts
    enable :login, :logout, :create_account
    login_redirect '/'
    logout_redirect '/'
    create_account_redirect '/'
    require_bcrypt? false  # We'll handle password hashing ourselves

    # Use our Rhales templates instead of ERB
    # Using the rodauth_view helper for cleaner configuration
    login_view(&rodauth_view('login', page_title: 'Login'))
    create_account_view(&rodauth_view('register_simple', title: 'Sign Up for Demo'))
  end

  # Configure Rhales
  Rhales.configure do |config|
    config.template_paths = [File.join(opts[:root], 'templates')]
    config.default_locale = 'en'
    config.cache_templates = false  # Disable for demo
  end

  # Simple auth helper
  def current_user
    return nil unless session[:user_id]
    @current_user ||= DB[:accounts].where(id: session[:user_id]).first
  end

  def logged_in?
    !current_user.nil?
  end

  # Helper method for Rodauth view configuration
  # Makes it easier to configure views: rodauth_view('login', title: 'Login')
  def rodauth_view(template_name, **data)
    proc { scope.rhales_render(template_name, data) }
  end

  # Rhales render helper using adapter classes
  def rhales_render(template_name, business_data = {})
    # Automatically include common view data (flash, CSRF, etc.)
    auto_data = {
      flash_notice: flash['notice'],
      flash_error: flash['error'],
      current_path: request.path,
      request_method: request.request_method
    }

    # Merge with provided business data (business_data takes precedence)
    merged_data = auto_data.merge(business_data)

    # Create adapter instances for Rhales context
    request_data = SimpleRequest.new(
      path: request.path,
      method: request.request_method,
      ip: request.ip,
      params: request.params
    )

    session_data = SimpleSession.new(
      authenticated: logged_in?,
      csrf_token: 'demo_csrf_token'
    )

    # Create auth adapter object
    auth_data = if logged_in?
      SimpleAuth.new(
        authenticated: true,
        email: current_user[:email],
        user_data: {
          id: current_user[:id],
          email: current_user[:email]
        }
      )
    else
      SimpleAuth.new(
        authenticated: false,
        email: nil,
        user_data: nil
      )
    end

    # Create and render view using the View class
    view = Rhales::View.new(
      request_data,
      session_data,
      auth_data,
      nil, # locale_override
      business_data: merged_data
    )
    view.render(template_name)
  end

  route do |r|
    r.rodauth

    # Home route - shows different content based on auth state
    r.root do
      if logged_in?
        rhales_render('dashboard', {
          welcome_message: "Welcome back, #{current_user[:email]}!",
          login_time: Time.now.strftime('%Y-%m-%d %H:%M:%S')
        })
      else
        rhales_render('home', {
          demo_credentials: {
            email: 'demo@example.com',
            password: 'demo123'
          }
        })
      end
    end

    # Simple API endpoint for RSFC hydration demo
    r.get 'api/user' do
      response['Content-Type'] = 'application/json'

      if logged_in?
        {
          authenticated: true,
          user: current_user,
          server_time: Time.now.iso8601
        }.to_json
      else
        { authenticated: false }.to_json
      end
    end

    # Demo data endpoint
    r.get 'api/demo-data' do
      response['Content-Type'] = 'application/json'

      {
        message: "This data was loaded dynamically via JavaScript!",
        timestamp: Time.now.to_i,
        random_number: rand(1000)
      }.to_json
    end
  end
end
