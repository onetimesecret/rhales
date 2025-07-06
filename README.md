# Rhales - Ruby Single File Components

> [!CAUTION]
> **Early Development Release** - Rhales is in active development (v0.1.0). The API may change between versions. While functional and tested, it's recommended for experimental use and contributions rather than production applications. Please report issues and provide feedback through GitHub.

Rhales is a framework for building server-rendered components with client-side data hydration using `.rue` files called RSFCs (Ruby Single File Components). Similar to Vue.js single file components but designed for Ruby applications.

About the name:
It all started with a simple mustache template many years ago. The successor to mustache, "Handlebars" is a visual analog for a mustache and successor to the format. "Two Whales Kissing" is another visual analog for a mustache and since we're working with Ruby we could call that, "Two Whales Kissing for Ruby", which is very long. Rhales combines Ruby and Whales into a one-word name for our library. It's a perfect name with absolutely no ambiguity or risk of confusion with other gems.

## Features

- **Server-side template rendering** with Handlebars-style syntax
- **Client-side data hydration** with secure JSON injection
- **Clear security boundaries** between server context and client data
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
end
```

### 2. Create a Simple Component

Create a `.rue` file in your templates directory:

```rue
<!-- templates/hello.rue -->
<data>
{
  "greeting": "{{greeting}}",
  "user_name": "{{user.name}}"
}
</data>

<template>
<div class="hello-component">
  <h1>{{greeting}}, {{user.name}}!</h1>
  <p>Welcome to Rhales RSFC!</p>
</div>
</template>

<logic>
# Simple greeting component
</logic>
```

### 3. Render in Your Application

```ruby
# In your controller/route handler
view = Rhales::View.new(request, session, user, 'en',
  business_data: {
    greeting: 'Hello',
    user: { name: 'World' }
  }
)

html = view.render('hello')
# Returns HTML with embedded JSON for client-side hydration
```

## Context and Data Boundaries

Rhales implements a **two-phase security model**:

### Server Templates: Full Context Access
Templates have complete access to all server-side data:
- User objects and authentication state
- Database connections and internal APIs
- Configuration values and secrets
- Request metadata (CSRF tokens, nonces)

```handlebars
<!-- Full server access in templates -->
{{#if user.admin?}}
  <a href="/admin">Admin Panel</a>
{{/if}}
<div class="{{theme_class}}">{{user.full_name}}</div>
```

### Client Data: Explicit Allowlist
Only data declared in `<data>` sections reaches the browser:

```rue
<data>
{
  "display_name": "{{user.name}}",
  "preferences": {
    "theme": "{{user.theme}}"
  }
}
</data>
```

Becomes:
```javascript
window.data = {
  "display_name": "John Doe",
  "preferences": { "theme": "dark" }
}
// No access to user.admin?, internal APIs, etc.
```

This creates a **REST API-like boundary** where you explicitly declare what data crosses the server-to-client security boundary.

For complete details, see [Context and Data Boundaries Documentation](docs/CONTEXT_AND_DATA_BOUNDARIES.md).
  config.site_ssl_enabled = true
end
```

### 2. Create a .rue file

Create `templates/dashboard.rue` - notice how the `<data>` section defines exactly what your frontend app will receive:

```xml
<data window="appState" schema="@/src/types/app-state.d.ts">
{
  "user": {
    "id": "{{user.id}}",
    "name": "{{user.name}}",
    "email": "{{user.email}}",
    "preferences": {{user.preferences}}
  },
  "products": {{recent_products}},
  "cart": {
    "items": {{cart.items}},
    "total": "{{cart.total}}"
  },
  "api": {
    "baseUrl": "{{api_base_url}}",
    "csrfToken": "{{csrf_token}}"
  },
  "features": {{enabled_features}}
}
</data>

<template>
<!doctype html>
<html lang="{{locale}}" class="{{theme_class}}">
<head>
  <title>{{page_title}}</title>
  <meta name="csrf-token" content="{{csrf_token}}">
</head>
<body>
  <!-- Critical: The mounting point for your frontend framework -->
  <div id="app">
    <!-- Server-rendered content for SEO and initial load -->
    <nav>{{> navigation}}</nav>
    <main>
      <h1>{{page_title}}</h1>
      {{#if user}}
        <p>Welcome back, {{user.name}}!</p>
      {{else}}
        <p>Please sign in to continue.</p>
      {{/if}}
    </main>
  </div>

  <!--
    RSFC automatically generates hydration scripts:
    - <script type="application/json" id="app-state-data">{...}</script>
    - <script>window.appState = JSON.parse(...);</script>
  -->

  <!-- Your frontend framework takes over from here -->
  <script nonce="{{nonce}}" type="module" src="/assets/app.js"></script>
</body>
</html>
</template>
```

### 3. The Manifold: Server-to-SPA Handoff

This example demonstrates Rhales' core value proposition: **eliminating the coordination gap** between server state and frontend frameworks.

**What you get:**
- ✅ **Declarative data contract**: The `<data>` section explicitly defines what your frontend receives
- ✅ **Type safety ready**: Schema reference points to TypeScript definitions
- ✅ **Zero coordination overhead**: No separate API design needed for initial state
- ✅ **SEO + SPA**: Server-rendered HTML with automatic client hydration
- ✅ **Security boundaries**: Only explicitly declared data reaches the client

### 4. RSFC Security Model

**Key Principle: The security boundary is at the server-to-client handoff, not within server-side rendering.**

```xml
<data>
{
  "message": "{{greeting}}",    <!-- ✅ Exposed to client -->
  "user": {
    "name": "{{user.name}}"     <!-- ✅ Exposed to client -->
  }
  <!-- ❌ user.secret_key not declared, won't reach client -->
}
</data>

<template>
  <h1>{{greeting}}</h1>          <!-- ✅ Full server context access -->
  <p>{{user.name}}</p>           <!-- ✅ Can access user object methods -->
  <p>{{user.secret_key}}</p>     <!-- ✅ Server-side only, not in <data> -->
</template>
```

**Template Section (`<template>`):**
- ✅ **Full server context access** - like ERB, HAML, or any server-side template
- ✅ **Can call object methods** - `{{user.full_name}}`, `{{products.count}}`, etc.
- ✅ **Rich server-side logic** - access to full business objects and their capabilities
- ✅ **Private by default** - nothing in templates reaches the client unless explicitly declared

**Data Section (`<data>`):**
- ✅ **Explicit client allowlist** - only declared variables reach the browser
- ✅ **JSON serialization boundary** - like designing a REST API endpoint
- ✅ **Type safety foundation** - can validate against schemas
- ❌ **Cannot expose secrets** - `user.secret_key` won't reach client unless declared

This design gives you the flexibility of full server-side templating while maintaining explicit control over what data reaches the client.

**Generated output:**
```html
<!-- Server-rendered HTML -->
<div id="app">
  <nav>...</nav>
  <main><h1>User Dashboard</h1><p>Welcome back, Alice!</p></main>
</div>

<!-- Automatic client hydration -->
<script id="app-state-data" type="application/json">
{"user":{"id":123,"name":"Alice","email":"alice@example.com","preferences":{...}},"products":[...],"cart":{...},"api":{...},"features":{...}}
</script>
<script nonce="abc123">
window.appState = JSON.parse(document.getElementById('app-state-data').textContent);
</script>

<!-- Your Vue/React/Svelte app mounts here with full state -->
<script nonce="abc123" type="module" src="/assets/app.js"></script>
```

### 5. Framework Integration

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
def dashboard
  @dashboard_html = render_rhales('dashboard',
    page_title: 'User Dashboard',
    user: current_user,
    recent_products: Product.recent.limit(5),
    cart: current_user.cart,
    enabled_features: Feature.enabled_for(current_user)
  )
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

get '/dashboard' do
  @dashboard_html = render_rhales('dashboard',
    page_title: 'Dashboard',
    user: current_user,
    recent_products: Product.recent,
    cart: session[:cart] || {},
    enabled_features: FEATURES
  )
  erb :dashboard
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
get :dashboard do
  @dashboard_html = render_rhales('dashboard',
    page_title: 'Dashboard',
    user: current_user,
    recent_products: Product.recent,
    cart: current_user&.cart,
    enabled_features: settings.features
  )
  render :dashboard
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

  get '/dashboard' do
    content_type 'text/html'
    render_rhales('dashboard',
      page_title: 'API Dashboard',
      user: current_user,
      recent_products: [],
      cart: {},
      enabled_features: { api_v2: true }
    )
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
    r.on 'dashboard' do
      @dashboard_html = render_rhales('dashboard',
        page_title: 'Dashboard',
        user: current_user,
        recent_products: [],
        cart: session[:cart],
        enabled_features: FEATURES
      )
      view('dashboard')
    end
  end
end
```

### 6. Basic Usage

```ruby
# Create a view instance
view = Rhales::View.new(request, session, current_user, locale)

# Render a template with rich data for frontend hydration
html = view.render('dashboard',
  page_title: 'User Dashboard',
  user: current_user,
  recent_products: Product.recent.limit(5),
  cart: current_user.cart,
  enabled_features: Feature.enabled_for(current_user)
)

# Or use the convenience method
html = Rhales.render('dashboard',
  request: request,
  session: session,
  user: current_user,
  page_title: 'User Dashboard',
  recent_products: products,
  cart: cart_data,
  enabled_features: features
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

  def role?(role)
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

## AI Development Assistance

Rhales was developed with assistance from AI tools. The following tools provided significant help with architecture design, code generation, and documentation:

- **Claude Sonnet 4** - Architecture design, code generation, and documentation
- **Claude Desktop & Claude Code** - Interactive development sessions and debugging
- **GitHub Copilot** - Code completion and refactoring assistance
- **Qodo Merge Pro** - Code review and quality improvements

I remain responsible for all design decisions and the final code. I believe in being transparent about development tools, especially as AI becomes more integrated into our workflows.
