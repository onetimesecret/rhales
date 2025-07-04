require 'roda'
require 'sequel'
require 'rhales'
require 'rodauth'
require 'bcrypt'
require 'rack/session'
require 'ostruct'

# Database setup
DB = Sequel.sqlite('db/demo.db')

# Create users table
DB.create_table?(:accounts) do
  primary_key :id
  String :email, null: false, unique: true
  String :password_hash, null: false
  String :name
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :last_login_at
end

# Create posts table for demo content
DB.create_table?(:posts) do
  primary_key :id
  foreign_key :account_id, :accounts, null: false
  String :title, null: false
  String :content, text: true
  String :status, default: 'draft'
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
end

# Models
class Account < Sequel::Model
  one_to_many :posts
end

class Post < Sequel::Model
  many_to_one :account
end

# Configure Rhales
Rhales.configure do |config|
  config.template_root = File.expand_path('templates', __dir__)
  config.cache_templates = false # Development mode
  config.default_locale = 'en'
end

# Authentication adapter for Rhales
class RodauthAdapter < Rhales::Adapters::BaseAuth
  def initialize(rodauth_instance)
    @rodauth = rodauth_instance
  end

  def authenticated?
    @rodauth.logged_in?
  end

  def current_user_id
    @rodauth.session_value
  end

  def current_user
    return nil unless authenticated?
    Account[current_user_id]
  end
end

# Session adapter for Rhales
class RodaSessionAdapter < Rhales::Adapters::BaseSession
  def initialize(session)
    @session = session
  end

  def get(key)
    @session[key.to_s]
  end

  def set(key, value)
    @session[key.to_s] = value
  end

  def delete(key)
    @session.delete(key.to_s)
  end

  def clear
    @session.clear
  end
end

class App < Roda
  use Rack::Session::Cookie, secret: 'demo_secret_key_change_in_production_this_must_be_at_least_64_bytes_long_for_security', key: '_rhales_demo_session'

  plugin :render, engine: 'erb'
  plugin :assets, css: 'app.css', js: 'app.js'
  plugin :public
  plugin :route_csrf
  plugin :flash
  plugin :content_for

  plugin :rodauth do
    enable :login, :logout, :create_account, :change_password, :reset_password

    db DB
    accounts_table :accounts
    account_password_hash_column :password_hash

    login_route 'login'
    logout_route 'logout'
    create_account_route 'register'

    create_account_redirect '/'
    login_redirect '/'
    logout_redirect '/'

    create_account_view { rhales_render('auth/register') }
    login_view { rhales_render('auth/login') }

    before_create_account do
      account[:name] = param('name')
    end

    after_login do
      db[:accounts].where(id: account_id).update(last_login_at: Time.now)
    end
  end

  # Helper method to render Rhales templates
  def rhales_render(template_name, locals = {})
    auth_adapter = RodauthAdapter.new(rodauth)

    # Create context data
    runtime_data = {
      csrf_token: csrf_token,
      csrf_field: csrf_field,
      nonce: SecureRandom.hex(16),
      flash: flash
    }

    business_data = {
      current_user: auth_adapter.current_user,
      authenticated: auth_adapter.authenticated?
    }.merge(locals)

    # Create context for template engine
    context = Rhales::Context.new(runtime_data, business_data, {})

    # Load template file
    template_path = File.join('templates', "#{template_name}.rue")

    unless File.exist?(template_path)
      raise "Template not found: #{template_path}"
    end

    # Parse template content
    parser = Rhales::Parser.new(File.read(template_path))

    # Create partial resolver for template engine
    partial_resolver = lambda do |partial_name|
      partial_path = File.join('templates', 'partials', "#{partial_name}.rue")
      if File.exist?(partial_path)
        partial_parser = Rhales::Parser.new(File.read(partial_path))
        partial_parser.template_content
      else
        raise Rhales::TemplateEngine::PartialNotFoundError, "Partial not found: #{partial_name}"
      end
    end

    # Render template
    engine = Rhales::TemplateEngine.new(parser.template_content, context, partial_resolver: partial_resolver)
    template_html = engine.render

    # Generate hydration if data section exists
    if parser.data_content && !parser.data_content.strip.empty?
      hydrator = Rhales::Hydrator.new(parser.data_content, context, parser.window_name, runtime_data[:nonce])
      hydration_html = hydrator.render
      template_html + hydration_html
    else
      template_html
    end
  end

  route do |r|
    r.public
    r.assets
    r.rodauth

    # Homepage
    r.root do
      if rodauth.logged_in?
        posts = Post.where(account_id: rodauth.session_value).order(Sequel.desc(:created_at)).all
        rhales_render('dashboard/index', posts: posts, stats: {
          total_posts: posts.count,
          published: posts.count { |p| p.status == 'published' },
          drafts: posts.count { |p| p.status == 'draft' }
        })
      else
        rhales_render('home')
      end
    end

    # Posts routes (authenticated only)
    r.on 'posts' do
      rodauth.require_authentication

      r.get 'new' do
        rhales_render('dashboard/post_form', post: Post.new, action: '/posts')
      end

      r.post do
        post = Post.new(
          account_id: rodauth.session_value,
          title: r.params['title'],
          content: r.params['content'],
          status: r.params['status'] || 'draft'
        )

        if post.save
          flash[:notice] = 'Post created successfully!'
          r.redirect '/'
        else
          rhales_render('dashboard/post_form', post: post, errors: post.errors)
        end
      end

      r.on Integer do |id|
        post = Post.where(id: id, account_id: rodauth.session_value).first
        r.redirect '/' unless post

        r.get 'edit' do
          rhales_render('dashboard/post_form', post: post, action: "/posts/#{id}")
        end

        r.post do
          post.update(
            title: r.params['title'],
            content: r.params['content'],
            status: r.params['status'],
            updated_at: Time.now
          )
          flash[:notice] = 'Post updated successfully!'
          r.redirect '/'
        end

        r.delete do
          post.destroy
          flash[:notice] = 'Post deleted!'
          r.redirect '/'
        end
      end
    end

    # Profile
    r.get 'profile' do
      rodauth.require_authentication
      rhales_render('dashboard/profile')
    end

    # Demo data endpoint (shows hydration)
    r.get 'api/stats' do
      rodauth.require_authentication
      account = Account[rodauth.session_value]

      response['Content-Type'] = 'application/json'
      {
        user: {
          name: account.name,
          email: account.email,
          member_since: account.created_at.strftime('%B %Y')
        },
        stats: {
          total_posts: account.posts.count,
          last_login: account.last_login_at&.strftime('%Y-%m-%d %H:%M')
        }
      }.to_json
    end
  end
end
