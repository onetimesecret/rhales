# Rhales - Ruby Single File Components

> [!CAUTION]
> **Early Development Release** - Rhales is in active development (v0.1.0). The API may change between versions. While functional and tested, it's recommended for experimental use and contributions rather than production applications. Please report issues and provide feedback through GitHub.

Rhales is a framework for building server-rendered components with client-side data hydration using `.rue` files called RSFCs (Ruby Single File Components). Similar to Vue.js single file components but designed for Ruby applications.

About the name:
It all started with a simple mustache template many years ago. The successor to mustache, "Handlebars" is a visual analog for a mustache and successor to the format. "Two Whales Kissing" is another visual analog for a mustache and since we're working with Ruby we could call that, "Two Whales Kissing for Ruby", which is very long. Rhales combines Ruby and Whales into a one-word name for our library. It's a perfect name with absolutely no ambiguity or risk of confusion with other gems.

## Features

- **Server-side template rendering** with Handlebars-style syntax
- **Enhanced hydration strategies** for optimal client-side performance
- **API endpoint generation** for link-based hydration strategies
- **Window collision detection** prevents silent data overwrites
- **Explicit merge strategies** for controlled data sharing (shallow, deep, strict)
- **Clear security boundaries** between server context and client data
- **Partial support** for component composition
- **Pluggable authentication adapters** for any auth system
- **Security-first design** with XSS protection and automatic CSP generation
- **Dependency injection** for testability and flexibility
- **Resource hint optimization** with browser preload/prefetch support

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

  # Enhanced Hydration Configuration
  config.hydration.injection_strategy = :preload  # or :late, :early, :earliest, :prefetch, :modulepreload, :lazy
  config.hydration.api_endpoint_path = '/api/hydration'
  config.hydration.fallback_to_late = true
  config.hydration.api_cache_enabled = true
  config.hydration.cors_enabled = true

  # CSP configuration (enabled by default)
  config.csp_enabled = true           # Enable automatic CSP header generation
  config.auto_nonce = true            # Automatically generate nonces
  config.csp_policy = {               # Customize CSP policy (optional)
    'default-src' => ["'self'"],
    'script-src' => ["'self'", "'nonce-{{nonce}}'"],
    'style-src' => ["'self'", "'nonce-{{nonce}}'", "'unsafe-hashes'"]
    # ... more directives
  }
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
  props: {
    greeting: 'Hello',
    user: { name: 'World' }
  }
)

html = view.render('hello')
# Returns HTML with embedded JSON for client-side hydration
```

## Context and Data Model

Rhales uses a **two-layer data model** for template rendering:

### 1. App Data (Framework Layer)
All framework-provided data is available under the `app` namespace:

```handlebars
<!-- Framework data through app namespace -->
{{app.csrf_token}}       <!-- CSRF token for forms -->
{{app.nonce}}            <!-- CSP nonce for scripts -->
{{app.authenticated}}    <!-- Authentication state -->
{{app.environment}}      <!-- Current environment -->
{{app.features.dark_mode}} <!-- Feature flags -->
{{app.theme_class}}      <!-- Current theme -->
```

**Available App Variables:**
- `app.api_base_url` - Base URL for API calls
- `app.authenticated` - Whether user is authenticated
- `app.csrf_token` - CSRF token for forms
- `app.development` - Whether in development mode
- `app.environment` - Current environment (production/staging/dev)
- `app.features` - Feature flags hash
- `app.nonce` - CSP nonce for inline scripts
- `app.theme_class` - Current theme CSS class

### 2. Props Data (Application Layer)
Your application-specific data passed to each view:

```handlebars
<!-- Application data -->
{{user.name}}            <!-- Direct access -->
{{page_title}}           <!-- Props take precedence -->
{{#if user.admin?}}
  <a href="/admin">Admin Panel</a>
{{/if}}
```

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
<div class="{{app.theme_class}}">{{user.full_name}}</div>
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

## Enhanced Hydration Strategies

Rhales provides multiple hydration strategies optimized for different performance requirements and use cases:

### Traditional Strategies

#### `:late` (Default - Backwards Compatible)
Injects scripts before the closing `</body>` tag. Safe and reliable for all scenarios.

```ruby
config.hydration.injection_strategy = :late
```

#### `:early` (Mount Point Optimization)
Injects scripts immediately before frontend mount points (`#app`, `#root`, etc.) for improved Time-to-Interactive.

```ruby
config.hydration.injection_strategy = :early
config.hydration.mount_point_selectors = ['#app', '#root', '[data-mount]']
config.hydration.fallback_to_late = true
```

#### `:earliest` (Head Section Injection)
Injects scripts in the HTML head section for maximum performance, after meta tags and stylesheets.

```ruby
config.hydration.injection_strategy = :earliest
config.hydration.fallback_to_late = true
```

### Link-Based Strategies (API Endpoints)

These strategies generate separate API endpoints for hydration data, enabling better caching, parallel loading, and reduced HTML payload sizes.

#### `:preload` (High Priority Loading)
Generates `<link rel="preload">` tags with immediate script execution for critical data.

```ruby
config.hydration.injection_strategy = :preload
config.hydration.api_endpoint_path = '/api/hydration'
config.hydration.link_crossorigin = true
```

#### `:prefetch` (Future Page Optimization)
Generates `<link rel="prefetch">` tags for data that will be needed on subsequent page loads.

```ruby
config.hydration.injection_strategy = :prefetch
```

#### `:modulepreload` (ES Module Support)
Generates `<link rel="modulepreload">` tags with ES module imports for modern applications.

```ruby
config.hydration.injection_strategy = :modulepreload
```

#### `:lazy` (Intersection Observer)
Loads data only when mount points become visible using Intersection Observer API.

```ruby
config.hydration.injection_strategy = :lazy
config.hydration.lazy_mount_selector = '#app'
```

#### `:link` (Manual Loading)
Generates basic link references with manual loading functions for custom hydration logic.

```ruby
config.hydration.injection_strategy = :link
```

### Strategy Performance Comparison

| Strategy | Time-to-Interactive | Caching | Parallel Loading | Best Use Case |
|----------|-------------------|---------|------------------|---------------|
| `:late` | Standard | Basic | No | Legacy compatibility |
| `:early` | Improved | Basic | No | SPA mount point optimization |
| `:earliest` | Excellent | Basic | No | Critical path optimization |
| `:preload` | Excellent | Advanced | Yes | High-priority data |
| `:prefetch` | Standard | Advanced | Yes | Multi-page apps |
| `:modulepreload` | Excellent | Advanced | Yes | Modern ES modules |
| `:lazy` | Variable | Advanced | Yes | Below-fold content |
| `:link` | Manual | Advanced | Yes | Custom implementations |

### API Endpoint Setup

For link-based strategies, you'll need to set up API endpoints in your application:

```ruby
# Rails example
class HydrationController < ApplicationController
  def show
    template_name = params[:template]
    endpoint = Rhales::HydrationEndpoint.new(rhales_config, current_context)

    case request.format
    when :json
      result = endpoint.render_json(template_name)
    when :js
      result = endpoint.render_module(template_name)
    else
      result = endpoint.render_json(template_name)
    end

    render json: result[:content],
           content_type: result[:content_type],
           headers: result[:headers]
  end
end

# routes.rb
get '/api/hydration/:template', to: 'hydration#show'
get '/api/hydration/:template.js', to: 'hydration#show', defaults: { format: :js }
```

### Data Hydration Examples

#### Traditional Inline Hydration
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

#### Link-Based Hydration (`:preload` strategy)
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
<link rel="preload" href="/api/hydration/my_template" as="fetch" crossorigin>
<script nonce="nonce123" data-hydration-target="myData">
fetch('/api/hydration/my_template')
  .then(r => r.json())
  .then(data => {
    window.myData = data;
    window.dispatchEvent(new CustomEvent('rhales:hydrated', {
      detail: { target: 'myData', data: data }
    }));
  })
  .catch(err => console.error('Rhales hydration error:', err));
</script>
```

#### ES Module Hydration (`:modulepreload` strategy)
```html
<link rel="modulepreload" href="/api/hydration/my_template.js">
<script type="module" nonce="nonce123" data-hydration-target="myData">
import data from '/api/hydration/my_template.js';
window.myData = data;
window.dispatchEvent(new CustomEvent('rhales:hydrated', {
  detail: { target: 'myData', data: data }
}));
</script>
```

### Migration Guide

#### From Basic to Enhanced Hydration

**Step 1**: Update your configuration to use enhanced strategies:

```ruby
# Before (implicit :late strategy)
Rhales.configure do |config|
  # Basic configuration
end

# After (explicit strategy selection)
Rhales.configure do |config|
  # Choose your strategy based on your needs
  config.hydration.injection_strategy = :preload  # or :early, :earliest, etc.
  config.hydration.fallback_to_late = true        # Safe fallback
  config.hydration.api_endpoint_path = '/api/hydration'
  config.hydration.api_cache_enabled = true
end
```

**Step 2**: Set up API endpoints for link-based strategies (if using `:preload`, `:prefetch`, `:modulepreload`, `:lazy`, or `:link`):

```ruby
# Add to your routes
get '/api/hydration/:template', to: 'hydration#show'
get '/api/hydration/:template.js', to: 'hydration#show', defaults: { format: :js }

# Create controller
class HydrationController < ApplicationController
  def show
    template_name = params[:template]
    endpoint = Rhales::HydrationEndpoint.new(rhales_config, current_context)
    result = endpoint.render_json(template_name)

    render json: result[:content],
           content_type: result[:content_type],
           headers: result[:headers]
  end
end
```

**Step 3**: Update your frontend code to listen for hydration events (optional):

```javascript
// Listen for hydration completion
window.addEventListener('rhales:hydrated', (event) => {
  console.log('Data loaded:', event.detail.target, event.detail.data);

  // Initialize your app with the loaded data
  if (event.detail.target === 'appData') {
    initializeApp(event.detail.data);
  }
});
```

### Troubleshooting

#### Common Issues

**1. Link-based strategies not working**
- Ensure API endpoints are set up correctly
- Check that `config.hydration.api_endpoint_path` matches your routes
- Verify CORS settings if loading from different domains

**2. Mount points not detected with `:early` strategy**
- Check that your HTML contains valid mount point selectors (`#app`, `#root`, etc.)
- Verify `config.hydration.mount_point_selectors` includes your selectors
- Enable fallback: `config.hydration.fallback_to_late = true`

**3. CSP violations with link-based strategies**
- Ensure nonces are properly configured: `config.auto_nonce = true`
- Add API endpoint domains to CSP `connect-src` directive
- Check that `crossorigin` attribute is properly configured

**4. Performance not improving with advanced strategies**
- Verify browser support for chosen strategy (modulepreload requires modern browsers)
- Check network timing in DevTools to confirm parallel loading
- Consider using `:prefetch` for subsequent page loads vs `:preload` for current page

**5. Hydration events not firing**
- Ensure JavaScript is not blocked by CSP
- Check browser console for script errors
- Verify API endpoints return valid JSON responses

### Window Collision Detection

Rhales automatically detects when multiple templates try to use the same window attribute, preventing silent data overwrites:

```erb
<!-- layouts/main.rue -->
<data window="appData">
{"user": "{{user.name}}", "csrf": "{{csrf_token}}"}
</data>

<!-- pages/home.rue -->
<data window="appData">  <!-- ❌ Collision detected! -->
{"page": "home", "features": ["feature1"]}
</data>
```

This raises a helpful error:
```
Window attribute collision detected

Attribute: 'appData'
First defined: layouts/main.rue:1
Conflict with: pages/home.rue:1

Quick fixes:
  1. Rename one: <data window="homeData">
  2. Enable merging: <data window="appData" merge="deep">
```

### Merge Strategies

When you intentionally want to share data between templates, use explicit merge strategies:

```erb
<!-- layouts/main.rue -->
<data window="appData">
{
  "user": {"name": "{{user.name}}", "role": "{{user.role}}"},
  "csrf": "{{csrf_token}}"
}
</data>

<!-- pages/home.rue with deep merge -->
<data window="appData" merge="deep">
{
  "user": {"email": "{{user.email}}"},  <!-- Merged with layout user -->
  "page": {"title": "Home", "features": {{features.to_json}}}
}
</data>
```

#### Available Merge Strategies

**`merge="shallow"`** - Top-level key merge, throws error on conflicts:
```javascript
// Layout: {"user": {...}, "csrf": "abc"}
// Page:   {"page": {...}, "user": {...}}  // ❌ Error: key conflict
```

**`merge="deep"`** - Recursive merge, last value wins on conflicts:
```javascript
// Layout: {"user": {"name": "John", "role": "admin"}}
// Page:   {"user": {"email": "john@example.com"}}
// Result: {"user": {"name": "John", "role": "admin", "email": "john@example.com"}}
```

**`merge="strict"`** - Recursive merge, throws error on any conflict:
```javascript
// Layout: {"user": {"name": "John"}}
// Page:   {"user": {"name": "Jane"}}  // ❌ Error: value conflict
```

## Content Security Policy (CSP)

Rhales provides **security by default** with automatic CSP header generation and nonce management.

### Automatic CSP Protection

CSP is **enabled by default** when you configure Rhales:

```ruby
Rhales.configure do |config|
  # CSP is enabled by default with secure settings
  config.csp_enabled = true     # Default: true
  config.auto_nonce = true      # Default: true
end
```

### Default Security Policy

Rhales ships with a secure default CSP policy:

```ruby
{
  'default-src' => ["'self'"],
  'script-src' => ["'self'", "'nonce-{{nonce}}'"],
  'style-src' => ["'self'", "'nonce-{{nonce}}'", "'unsafe-hashes'"],
  'img-src' => ["'self'", 'data:'],
  'font-src' => ["'self'"],
  'connect-src' => ["'self'"],
  'base-uri' => ["'self'"],
  'form-action' => ["'self'"],
  'frame-ancestors' => ["'none'"],
  'object-src' => ["'none'"],
  'upgrade-insecure-requests' => []
}
```

### Automatic Nonce Generation

Rhales automatically generates and manages CSP nonces:

```erb
<!-- In your .rue templates -->
<script nonce="{{app.nonce}}">
  // Your inline JavaScript with automatic nonce
  console.log('Secure script execution');
</script>

<style nonce="{{app.nonce}}">
  /* Your inline styles with automatic nonce */
  .component { color: blue; }
</style>
```

### Framework Integration

CSP headers are automatically set during view rendering:

```ruby
# Your framework code (Rails, Sinatra, Roda, etc.)
def dashboard
  view = Rhales::View.new(request, session, current_user, 'en')
  html = view.render('dashboard', user: current_user)

  # CSP header automatically added to response:
  # Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-abc123'; ...
end
```

### Custom CSP Policies

Customize the CSP policy for your specific needs:

```ruby
Rhales.configure do |config|
  config.csp_policy = {
    'default-src' => ["'self'"],
    'script-src' => ["'self'", "'nonce-{{nonce}}'", 'https://cdn.example.com'],
    'style-src' => ["'self'", "'nonce-{{nonce}}'", 'https://fonts.googleapis.com'],
    'img-src' => ["'self'", 'data:', 'https://images.example.com'],
    'connect-src' => ["'self'", 'https://api.example.com'],
    'font-src' => ["'self'", 'https://fonts.gstatic.com'],
    # Add your own directives...
  }
end
```

### Per-Framework CSP Setup

#### Rails
```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  after_action :set_csp_header

  private

  def set_csp_header
    csp_header = request.env['csp_header']
    response.headers['Content-Security-Policy'] = csp_header if csp_header
  end
end
```

#### Sinatra
```ruby
helpers do
  def render_with_csp(template_name, data = {})
    result = render_rhales(template_name, data)
    csp_header = request.env['csp_header']
    headers['Content-Security-Policy'] = csp_header if csp_header
    result
  end
end
```

#### Roda
```ruby
class App < Roda
  def render_with_csp(template_name, data = {})
    result = render_rhales(template_name, data)
    csp_header = request.env['csp_header']
    response.headers['Content-Security-Policy'] = csp_header if csp_header
    result
  end
end
```

### CSP Benefits

- **Security by default**: Protection against XSS attacks out of the box
- **Automatic nonce management**: No manual nonce coordination needed
- **Template integration**: Nonces automatically available in templates
- **Framework agnostic**: Works with any Ruby web framework
- **Customizable policies**: Adapt CSP rules to your application needs
- **Zero configuration**: Secure defaults work immediately

### Disabling CSP

If you need to disable CSP for specific environments:

```ruby
Rhales.configure do |config|
  config.csp_enabled = false  # Disable CSP header generation
  config.auto_nonce = false   # Disable automatic nonce generation
end
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
context = Rhales::Context.minimal(props: { user: { name: 'Test' } })
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
