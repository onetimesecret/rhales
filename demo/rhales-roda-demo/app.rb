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
    @method = method
    @params = params
  end
end

class SimpleSession
  attr_reader :authenticated, :csrf_token

  def initialize(authenticated:, csrf_token:)
    @authenticated = authenticated
  end

  def authenticated?
    @authenticated
  end
end

class SimpleAuth < Rhales::Adapters::BaseAuth
  attr_reader :authenticated, :email, :user_data

  def initialize(authenticated:, email:, user_data:)
    @authenticated = authenticated
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
    login_view { scope.rhales_render('login', page_title: 'Login') }
    create_account_view { scope.rhales_render('register_simple', title: 'Sign Up for Demo') }
  end

  # Configure Rhales
  Rhales.configure do |config|
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

  # CSRF token validation
  def valid_csrf_token?(token)
    return false unless token && session[:csrf_token]

    # Simple constant-time comparison for security
    token == session[:csrf_token]
  end

  def require_csrf_token!
    unless valid_csrf_token?(request.params['_csrf_token'])
      response.status = 403
    end
  end

  # Helper method for Rodauth view configuration
  # Makes it easier to configure views: rodauth_view('login', title: 'Login')
  def rodauth_view(template_name, **data)
    proc { scope.rhales_render(template_name, data) }
  end

  # Rhales render helper using adapter classes with layout support
  def rhales_render(template_name, business_data = {}, layout: 'layouts/main', **extra_data)
    # Generate proper CSRF token and field
    csrf_token = SecureRandom.hex(32)
    csrf_field = "<input type=\"hidden\" name=\"_csrf_token\" value=\"#{csrf_token}\">"

    # Store CSRF token in session for validation
    session[:csrf_token] = csrf_token

    # Automatically include common view data (flash, CSRF, etc.)
    auto_data = {
      'flash_notice' => flash['notice'],
      'flash_error' => flash['error'],
      'current_path' => request.path,
      'request_method' => request.request_method,
      'csrf_field' => csrf_field,
      'csrf_token' => csrf_token,
      'test_field' => "TEST_VALUE"
    }

    # Merge data layers: auto_data provides base, then business_data, then extra_data
    # But we want to ensure CSRF is always available, so add it after merge
    merged_data = auto_data.merge(business_data).merge(extra_data)
    

    # Always ensure CSRF field is available regardless of data precedence
    merged_data['csrf_field'] = csrf_field
    merged_data['csrf_token'] = csrf_token
    merged_data['test_field'] = "FORCED_TEST_VALUE"

    # Create adapter instances for Rhales context
    request_data = SimpleRequest.new(
      path: request.path,
      method: request.request_method,
      ip: request.ip,
      params: request.params,
      env: {
        'csrf_token' => csrf_token,
        'nonce' => SecureRandom.hex(16),
        'request_id' => SecureRandom.hex(8),
        'flash_notice' => flash['notice'],
    )

    session_data = SimpleSession.new(
      authenticated: logged_in?,
    )

    # Create auth adapter object
    auth_data = if logged_in?
      SimpleAuth.new(
        authenticated: true,
        email: current_user[:email],
        user_data: {
          id: current_user[:id],
      )
    else
      SimpleAuth.new(
        authenticated: false,
        email: nil,
      )
    end

    # Render content template first
      request_data,
      session_data,
      auth_data,
      nil, # locale_override
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
      else
        rhales_render('home', {
          demo_credentials: {
            email: 'demo@example.com',
      end
    end

    # Simple API endpoint for RSFC hydration demo
    r.get 'api/user' do
      response['Content-Type'] = 'application/json'

      if logged_in?
        {
          authenticated: true,
          user: current_user,
        }.to_json
      else
        { authenticated: false }.to_json
      end
    end

    # Demo data endpoint
    r.get 'api/demo-data' do
      response['Content-Type'] = 'application/json'

      {
        timestamp: Time.now.to_i,
      }.to_json
    end
  end
end
