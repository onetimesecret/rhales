require 'roda'
require 'sequel'
require 'rhales'
require 'rodauth'
require 'bcrypt'
require 'rack/session'

# Database setup
DB = Sequel.sqlite('db/demo.db')

# Create simple accounts table for demo
DB.create_table?(:accounts) do
  primary_key :id
  String :email, null: false, unique: true
  String :password_hash, null: false
  String :name
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
end

# Simple Account model
class Account < Sequel::Model
end

# Configure Rhales for basic demo
Rhales.configure do |config|
  config.cache_templates = false # Development mode
  config.default_locale  = 'en'
end

# Simple authentication helper for demo
class SimpleAuth
  def initialize(rodauth_instance)
    @rodauth = rodauth_instance
  end

  def authenticated?
    @rodauth.logged_in?
  end

  def current_user
    return nil unless authenticated?

    Account[@rodauth.session_value]
  end

  def user_data
    user = current_user
    return {} unless user

    {
      id: user.id,
      email: user.email,
      name: user.name,
      member_since: user.created_at.strftime('%B %Y'),
    }
  end
end

class App < Roda
  use Rack::Session::Cookie, secret: 'demo_secret_key_change_in_production_this_must_be_at_least_64_bytes_long_for_security', key: '_rhales_demo_session'

  plugin :route_csrf
  plugin :flash

  plugin :rodauth do
    enable :login, :logout

    db DB
    accounts_table :accounts
    account_password_hash_column :password_hash

    login_route 'login'
    logout_route 'logout'

    login_redirect '/'
    logout_redirect '/'

    login_view { rhales_render('login') }
  end

  # Helper method to render Rhales templates
  def rhales_render(template_name, locals = {})
    auth  = SimpleAuth.new(rodauth)
    nonce = SecureRandom.hex(16)

    # Create runtime data
    runtime = {
      csrf_token: csrf_token,
      csrf_field: csrf_field,
      nonce: nonce,
      flash: flash,
    }

    # Create business data
    business = {
      authenticated: auth.authenticated?,
      current_user: auth.current_user,
    }.merge(locals)

    # Render the main template
    content_html = render_template(template_name, runtime, business, nonce)

    # Wrap in layout
    render_template('layouts/main', runtime, business.merge(content: content_html), nonce)
  end

  private

  def render_template(template_name, runtime, business, nonce)
    # Load template file with full path
    template_path = File.expand_path(File.join('templates', "#{template_name}.rue"), __dir__)
    raise "Template not found: #{template_path}" unless File.exist?(template_path)

    template_content = File.read(template_path)

    # Parse template content
    parser = Rhales::Parser.new(template_content)

    # Create context
    context = Rhales::Context.new(runtime, business, {})

    # Partial resolver
    partial_resolver = lambda do |partial_name|
      partial_path = File.expand_path(File.join('templates', 'partials', "#{partial_name}.rue"), __dir__)
      raise "Partial not found: #{partial_name}" unless File.exist?(partial_path)

      partial_content = File.read(partial_path)
      partial_parser  = Rhales::Parser.new(partial_content)
      partial_parser.template_content
    end

    # Render template
    engine        = Rhales::TemplateEngine.new(parser.template_content, context, partial_resolver: partial_resolver)
    template_html = engine.render

    # Add hydration if data section exists
    if parser.data_content && !parser.data_content.strip.empty?
      hydrator = Rhales::Hydrator.new(parser.data_content, context, parser.window_name, nonce)
      template_html + hydrator.render
    else
      template_html
    end
  end

  route do |r|
    r.rodauth

    # Homepage - shows public vs private data boundary
    r.root do
      if rodauth.logged_in?
        auth = SimpleAuth.new(rodauth)
        rhales_render('dashboard', user_data: auth.user_data)
      else
        rhales_render('home')
      end
    end

    # Simple API endpoint to demonstrate hydration
    r.get 'api/user' do
      rodauth.require_authentication
      auth = SimpleAuth.new(rodauth)

      response['Content-Type'] = 'application/json'
      auth.user_data.to_json
    end
  end
end
