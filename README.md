# Rhales - Ruby Single File Components

> [!CAUTION]
> **Early Development Release** - Rhales is in active development (v0.1.0). The API may change between versions. While functional and tested, it's recommended for experimental use and contributions rather than production applications. Please report issues and provide feedback through GitHub.

Rhales is a framework for building server-rendered components with client-side data hydration using `.rue` files called RSFCs (Ruby Single File Components). Similar to Vue.js single file components but designed for Ruby applications.

About the name:
It all started with a simple mustache template many years ago. The successor to mustache, "Handlebars" is a visual analog for a mustache and successor to the format. "Two Whales Kissing" is another visual analog for a mustache and since we're working with Ruby we could call that, "Two Whales Kissing for Ruby", which is very long. Rhales combines Ruby and Whales into a one-word name for our library. It's a perfect name with absolutely no ambiguity or risk of confusion with other gems.

## Features

- **Server-side template rendering** with Handlebars-style syntax
- **Client-side data hydration** with secure JSON injection
- **Partial support** for component composition
- **Pluggable authentication adapters** for any auth system
- **Security-first design** with XSS protection and CSP support
- **Dependency injection** for testability and flexibility

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rhales'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install rhales
```

## Quick Start

### 1. Configure Rhales

```ruby
# Configure Rhales in your application initialization
Rhales.configure do |config|
  config.default_locale = 'en'
  config.template_paths = ['templates']  # or 'app/templates', 'views/templates', etc.
  config.features = { dark_mode: true }
  config.site_host = 'example.com'
  config.site_ssl_enabled = true
end
```

### 2. Create a .rue file

Create `templates/welcome.rue`:

```xml
<data>
{
  "greeting": "{{page_title}}",
  "user": {
    "name": "{{user.name}}",
    "authenticated": {{authenticated}}
  },
  "features": {{features}}
}
</data>

<template>
<div class="{{theme_class}}">
  <h1>{{page_title}}</h1>
  {{#if authenticated}}
    <p>Welcome back, {{user.name}}!</p>
  {{else}}
    <p>Please sign in to continue.</p>
  {{/if}}

  {{#if features.dark_mode}}
    <button onclick="toggleTheme()">Toggle Theme</button>
  {{/if}}
</div>
</template>
```

### 3. Framework Integration

#### Rails

```ruby
# config/initializers/rhales.rb
Rhales.configure do |config|
  config.template_paths = ['app/templates']
  config.default_locale = 'en'
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  def render_rhales(template_name, data = {})
    view = Rhales::View.new(request, session, current_user, I18n.locale)
    view.render(template_name, data)
  end
end

# In your controller
def index
  @welcome_html = render_rhales('welcome', page_title: 'Welcome to Our App')
end
```

#### Sinatra

```ruby
# app.rb
require 'sinatra'
require 'rhales'

Rhales.configure do |config|
  config.template_paths = ['templates']
  config.default_locale = 'en'
end

helpers do
  def render_rhales(template_name, data = {})
    view = Rhales::View.new(request, session, current_user, 'en')
    view.render(template_name, data)
  end
end

get '/' do
  @welcome_html = render_rhales('welcome', page_title: 'Welcome to Sinatra')
  erb :index
end
```

#### Padrino

```ruby
# config/apps.rb
Padrino.configure_apps do
  Rhales.configure do |config|
    config.template_paths = ['app/templates']
    config.default_locale = 'en'
  end
end

# app/helpers/application_helper.rb
module ApplicationHelper
  def render_rhales(template_name, data = {})
    view = Rhales::View.new(request, session, current_user, locale)
    view.render(template_name, data)
  end
end

# app/controllers/application_controller.rb
get :index do
  @welcome_html = render_rhales('welcome', page_title: 'Welcome to Padrino')
  render :index
end
```

#### Grape

```ruby
# config.ru or initializer
require 'grape'
require 'rhales'

Rhales.configure do |config|
  config.template_paths = ['templates']
  config.default_locale = 'en'
end

# api.rb
class MyAPI < Grape::API
  helpers do
    def render_rhales(template_name, data = {})
      # Create mock request/session for Grape
      mock_request = OpenStruct.new(env: env)
      mock_session = {}

      view = Rhales::View.new(mock_request, mock_session, current_user, 'en')
      view.render(template_name, data)
    end
  end

  get '/welcome' do
    content_type 'text/html'
    render_rhales('welcome', page_title: 'Welcome to Grape API')
  end
end
```

#### Roda

```ruby
# app.rb
require 'roda'
require 'rhales'

class App < Roda
  plugin :render

  Rhales.configure do |config|
    config.template_paths = ['templates']
    config.default_locale = 'en'
  end

  def render_rhales(template_name, data = {})
    view = Rhales::View.new(request, session, current_user, 'en')
    view.render(template_name, data)
  end

  route do |r|
    r.root do
      @welcome_html = render_rhales('welcome', page_title: 'Welcome to Roda')
      view('index')
    end
  end
end
```

### 4. Basic Usage

```ruby
# Create a view instance
view = Rhales::View.new(request, session, current_user, locale)

# Render a template
html = view.render('welcome', page_title: 'Welcome to Rhales')

# Or use the convenience method
html = Rhales.render('welcome',
  request: request,
  session: session,
  user: current_user,
  page_title: 'Welcome to Rhales'
)
```

## Authentication Adapters

Rhales supports pluggable authentication adapters. Implement the `Rhales::Adapters::BaseAuth` interface:

```ruby
class MyAuthAdapter < Rhales::Adapters::BaseAuth
  def initialize(user)
    @user = user
  end

  def anonymous?
    @user.nil?
  end

  def theme_preference
    @user&.theme || 'light'
  end

  def user_id
    @user&.id
  end

  def has_role?(role)
    @user&.roles&.include?(role)
  end
end

# Use with Rhales
user_adapter = MyAuthAdapter.new(current_user)
view = Rhales::View.new(request, session, user_adapter)
```

## Template Syntax

Rhales uses a Handlebars-style template syntax:

### Variables
- `{{variable}}` - HTML-escaped output
- `{{{variable}}}` - Raw output (use carefully!)

### Conditionals
```erb
{{#if condition}}
  Content when true
{{/if}}

{{#unless condition}}
  Content when false
{{/unless}}
```

### Iteration
```erb
{{#each items}}
  <div>{{name}} - {{@index}}</div>
{{/each}}
```

### Partials
```erb
{{> header}}
{{> navigation}}
```

## Data Hydration

The `<data>` section creates client-side JavaScript:

```erb
<data window="myData">
{
  "apiUrl": "{{api_base_url}}",
  "user": {{user}},
  "csrfToken": "{{csrf_token}}"
}
</data>
```

Generates:
```html
<script id="rsfc-data-abc123" type="application/json">
{"apiUrl":"https://api.example.com","user":{"id":123},"csrfToken":"token"}
</script>
<script nonce="nonce123">
window.myData = JSON.parse(document.getElementById('rsfc-data-abc123').textContent);
</script>
```

## Testing

Rhales includes comprehensive test helpers and is framework-agnostic:

```ruby
# test/test_helper.rb or spec/spec_helper.rb
require 'rhales'

Rhales.configure do |config|
  config.default_locale = 'en'
  config.app_environment = 'test'
  config.cache_templates = false
  config.template_paths = ['test/templates'] # or wherever your test templates are
end

# Test context creation
context = Rhales::Context.minimal(business_data: { user: { name: 'Test' } })
expect(context.get('user.name')).to eq('Test')

# Test template rendering
template = '{{#if authenticated}}Welcome{{/if}}'
result = Rhales.render_template(template, authenticated: true)
expect(result).to eq('Welcome')

# Test full template files
mock_request = OpenStruct.new(env: {})
mock_session = {}
view = Rhales::View.new(mock_request, mock_session, nil, 'en')
html = view.render('test_template', message: 'Hello World')
```

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rspec
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the [MIT License](https://opensource.org/licenses/MIT).
