# Rhales - Ruby Single File Components

> [!CAUTION]
> **Early Development Release** - Rhales is in active development (v0.5). The API underwent breaking changes from v0.4. While functional and tested, it's recommended for experimental use and contributions. Please report issues and provide feedback through GitHub.

Rhales is a **type-safe contract enforcement framework** for server-rendered pages with client-side data hydration. It uses `.rue` files (Ruby Single File Components) that combine Zod schemas, Handlebars templates, and documentation into a single contract-first format.

**About the name:** It all started with a simple mustache template many years ago. Mustache's successor, "Handlebars," is a visual analog for a mustache. "Two Whales Kissing" is another visual analog for a mustache, and since we're working with Ruby, we call it "Rhales" (Ruby + Whales). It's a perfect name with absolutely no ambiguity or risk of confusion.

## What's New in v0.5

- ✅ **Schema-First Design**: Replaced `<data>` sections with Zod v4 `<schema>` sections
- ✅ **Type Safety**: Contract enforcement between backend and frontend
- ✅ **Simplified API**: Removed deprecated parameters (`sess`, `cust`, `props:`, `app_data:`)
- ✅ **Clear Context Layers**: Renamed `app` → `request` for clarity
- ✅ **Schema Tooling**: Rake tasks for schema generation and validation
- ✅ **100% Migration**: All demo templates use schemas

**Breaking changes from v0.4:** See [Migration Guide](#migration-from-v1x-to-v20) below.

## Features

- **Schema-based hydration** with Zod v4 for type-safe client data
- **Server-side rendering** with Handlebars-style template syntax
- **Three-layer context** for request, server, and client data separation
- **Security-first design** with explicit server-to-client boundaries
- **Layout & partial composition** for component reuse
- **CSP support** with automatic nonce generation
- **Framework agnostic** - works with Rails, Roda, Sinatra, Grape, Padrino
- **Dependency injection** for testability and flexibility

## Installation

Add to your Gemfile:

```ruby
gem 'rhales'
```

Then execute:

```bash
bundle install
```

## Quick Start

### 1. Configure Rhales

```ruby
# config/initializers/rhales.rb or similar
Rhales.configure do |config|
  config.default_locale = 'en'
  config.template_paths = ['templates']
  config.features = { dark_mode: true }
  config.site_host = 'example.com'

  # CSP configuration
  config.csp_enabled = true
  config.auto_nonce = true
end
```

### 2. Create a .rue Component

Create `templates/hello.rue`:

```xml
<schema lang="js-zod" window="appData">
const schema = z.object({
  greeting: z.string(),
  userName: z.string()
});
</schema>

<template>
<div class="hello-component">
  <h1>{{greeting}}, {{userName}}!</h1>
  <p>Welcome to Rhales v0.5</p>
</div>
</template>

<logic>
# Simple greeting component demonstrating schema-based hydration
</logic>
```

### 3. Render in Your Application

```ruby
# In your controller/route handler
view = Rhales::View.new(
  request,
  client: {
    greeting: 'Hello',
    userName: 'World'
  }
)

html = view.render('hello')
# Returns HTML with schema-validated data injected as window.appData
```

## The .rue File Format

A `.rue` file contains three sections:

```xml
<schema lang="js-zod" window="data" [version="2"] [envelope="Envelope"] [layout="layouts/main"]>
const schema = z.object({
  // Zod v4 schema defining client data contract
});
</schema>

<template>
  <!-- Handlebars-style HTML template -->
  <!-- Has access to ALL context layers -->
</template>

<logic>
# Optional Ruby documentation/comments
</logic>
```

### Schema Section Attributes

| Attribute | Required | Description | Example |
|-----------|----------|-------------|---------|
| `lang` | Yes | Schema language (currently only `js-zod`) | `"js-zod"` |
| `window` | Yes | Browser global name | `"appData"` → `window.appData` |
| `version` | No | Schema version | `"2"` |
| `envelope` | No | Response wrapper type | `"SuccessEnvelope"` |
| `layout` | No | Layout template reference | `"layouts/main"` |

### Zod Schema Examples

```javascript
// Simple types
z.object({
  user: z.string(),
  count: z.number(),
  active: z.boolean()
})

// Complex nested structures
z.object({
  user: z.object({
    id: z.number(),
    name: z.string(),
    email: z.string().email()
  }),
  items: z.array(z.object({
    id: z.number(),
    title: z.string(),
    price: z.number().positive()
  })),
  metadata: z.record(z.string())
})

// Optional and nullable
z.object({
  theme: z.string().optional(),
  lastLogin: z.string().nullable()
})
```

## Context and Data Model

Rhales uses a **three-layer context system** that separates concerns and enforces security boundaries:

### 1. Request Layer (Framework Data)

Framework-provided data available under the `request` namespace:

```handlebars
{{request.nonce}}          <!-- CSP nonce for scripts -->
{{request.csrf_token}}     <!-- CSRF token for forms -->
{{request.authenticated?}} <!-- Authentication state -->
{{request.locale}}         <!-- Current locale -->
```

**Available Request Variables:**
- `request.nonce` - CSP nonce for inline scripts/styles
- `request.csrf_token` - CSRF token for form submissions
- `request.authenticated?` - User authentication status
- `request.locale` - Current locale (e.g., 'en', 'es')
- `request.session` - Session object (if available)
- `request.user` - User object (if available)

### 2. Server Layer (Template-Only Data)

Application data that stays on the server (not sent to browser):

```ruby
view = Rhales::View.new(
  request,
  server: {
    page_title: 'Dashboard',
    vite_assets_html: vite_javascript_tag('application'),
    admin_notes: 'Internal use only'  # Never sent to client
  }
)
```

```handlebars
{{server.page_title}}        <!-- Available in templates -->
{{server.vite_assets_html}}  <!-- Server-side only -->
```

### 3. Client Layer (Serialized to Browser)

Data serialized to browser via schema validation:

```ruby
view = Rhales::View.new(
  request,
  client: {
    user: current_user.name,
    items: Item.all.map(&:to_h)
  }
)
```

```handlebars
{{client.user}}   <!-- Also serialized to window.appData.user -->
{{client.items}}  <!-- Also serialized to window.appData.items -->
```

### Context Layer Fallback

Variables can use shorthand notation (checks `client` → `server` → `request`):

```handlebars
<!-- Explicit layer access -->
{{client.user}}
{{server.page_title}}
{{request.nonce}}

<!-- Shorthand (automatic layer lookup) -->
{{user}}        <!-- Finds client.user -->
{{page_title}}  <!-- Finds server.page_title -->
{{nonce}}       <!-- Finds request.nonce -->
```

## Security Model: Server-to-Client Boundary

The `.rue` format enforces a **security boundary at the server-to-client handoff**:

### Server Templates: Full Context Access

Templates have access to ALL context layers:

```handlebars
<!-- Server-side template has full access -->
{{#if request.authenticated?}}
  <div class="admin-panel">
    <h2>Welcome {{client.user}}</h2>
    <p>Secret: {{server.admin_notes}}</p>  <!-- Not sent to browser -->
  </div>
{{/if}}
```

### Client Data: Explicit Allowlist

Only schema-declared data reaches the browser:

```xml
<schema lang="js-zod" window="data">
const schema = z.object({
  user: z.string(),
  userId: z.number()
  // NOT declared: admin_notes, secret_key, internal_api_url
});
</schema>
```

**Result on client:**

```javascript
window.data = {
  user: "Alice",
  userId: 123
  // admin_notes, secret_key NOT included (never declared in schema)
}
```

This creates a **REST API-like boundary** where you explicitly declare what data crosses the security boundary.

## Complete Example: Dashboard

### Backend (Ruby)

```ruby
# config/routes.rb (Rails) or route handler
class DashboardController < ApplicationController
  def show
    view = Rhales::View.new(
      request,
      client: {
        user: current_user.name,
        userId: current_user.id,
        items: current_user.items.map { |i|
          { id: i.id, name: i.name, price: i.price }
        },
        apiBaseUrl: ENV['API_BASE_URL']
      },
      server: {
        page_title: 'Dashboard',
        internal_notes: 'User has premium access',  # Server-only
        vite_assets: vite_javascript_tag('application')
      }
    )

    render html: view.render('dashboard').html_safe
  end
end
```

### Frontend (.rue file)

```xml
<!-- templates/dashboard.rue -->
<schema lang="js-zod" version="2" window="dashboardData" layout="layouts/main">
const schema = z.object({
  user: z.string(),
  userId: z.number(),
  items: z.array(z.object({
    id: z.number(),
    name: z.string(),
    price: z.number()
  })),
  apiBaseUrl: z.string().url()
});
</schema>

<template>
<div class="dashboard">
  <h1>{{server.page_title}}</h1>

  {{#if request.authenticated?}}
    <p>Welcome, {{client.user}}!</p>

    <div class="items">
      {{#each client.items}}
        <div class="item">
          <h3>{{name}}</h3>
          <p>${{price}}</p>
        </div>
      {{/each}}
    </div>
  {{else}}
    <p>Please log in</p>
  {{/if}}
</div>

<!-- Client-side JavaScript can access validated data -->
<script nonce="{{request.nonce}}">
  // window.dashboardData is populated with schema-validated data
  console.log('User ID:', window.dashboardData.userId);
  console.log('Items:', window.dashboardData.items);

  // Fetch additional data from API
  fetch(window.dashboardData.apiBaseUrl + '/user/preferences')
    .then(r => r.json())
    .then(prefs => console.log('Preferences:', prefs));
</script>
</template>

<logic>
# Dashboard component demonstrates:
# - Schema-based type safety
# - Three-layer context access
# - Conditional rendering based on auth
# - Client-side data hydration
# - CSP nonce support
</logic>
```

### Generated HTML

```html
<div class="dashboard">
  <h1>Dashboard</h1>
  <p>Welcome, Alice!</p>
  <div class="items">
    <div class="item"><h3>Widget</h3><p>$19.99</p></div>
    <div class="item"><h3>Gadget</h3><p>$29.99</p></div>
  </div>
</div>

<!-- Hydration script injected automatically -->
<script id="rsfc-data-abc123" type="application/json">
{"user":"Alice","userId":123,"items":[{"id":1,"name":"Widget","price":19.99},{"id":2,"name":"Gadget","price":29.99}],"apiBaseUrl":"https://api.example.com"}
</script>
<script nonce="nonce-xyz789">
window.dashboardData = JSON.parse(document.getElementById('rsfc-data-abc123').textContent);
</script>

<!-- Your client-side script -->
<script nonce="nonce-xyz789">
  console.log('User ID:', window.dashboardData.userId);
  console.log('Items:', window.dashboardData.items);
  fetch(window.dashboardData.apiBaseUrl + '/user/preferences')
    .then(r => r.json())
    .then(prefs => console.log('Preferences:', prefs));
</script>
```

## Template Syntax

Rhales uses Handlebars-style syntax:

### Variables

```handlebars
{{variable}}       <!-- HTML-escaped (safe) -->
{{{variable}}}     <!-- Raw output (use carefully!) -->
{{object.property}}  <!-- Dot notation -->
{{array.0}}        <!-- Array index -->
```

### Conditionals

```handlebars
{{#if condition}}
  Content when true
{{else}}
  Content when false
{{/if}}

{{#unless condition}}
  Content when false
{{/unless}}
```

**Truthy/Falsy:**
- Falsy: `nil`, `null`, `false`, `""`, `0`, `"false"`
- Truthy: All other values

### Loops

```handlebars
{{#each items}}
  {{@index}}      <!-- 0-based index -->
  {{@first}}      <!-- true if first item -->
  {{@last}}       <!-- true if last item -->
  {{this}}        <!-- current item (if primitive) -->
  {{name}}        <!-- item.name (if object) -->
{{/each}}
```

### Partials

```handlebars
{{> header}}              <!-- Include templates/header.rue -->
{{> components/nav}}      <!-- Include templates/components/nav.rue -->
```

### Layouts

```xml
<!-- templates/pages/home.rue -->
<schema lang="js-zod" window="data" layout="layouts/main">
const schema = z.object({ page: z.string() });
</schema>

<template>
  <h1>Home Page Content</h1>
</template>
```

```xml
<!-- templates/layouts/main.rue -->
<schema lang="js-zod" window="layoutData">
const schema = z.object({ siteName: z.string() });
</schema>

<template>
<!DOCTYPE html>
<html>
<head>
  <title>{{server.siteName}}</title>
</head>
<body>
  <header>{{> components/header}}</header>
  <main>
    <!-- Page content injected here -->
  </main>
  <footer>{{> components/footer}}</footer>
</body>
</html>
</template>
```

## Schema Tooling

Rhales provides rake tasks for schema management:

```bash
# Generate JSON schemas from .rue templates
rake rhales:schema:generate TEMPLATES_DIR=./templates

# Validate existing JSON schemas
rake rhales:schema:validate

# Show schema statistics
rake rhales:schema:stats TEMPLATES_DIR=./templates
```

**Example output:**

```
Schema Statistics
============================================================
Templates directory: templates

Total .rue files: 25
Files with <schema>: 25
Files without <schema>: 0

By language:
  js-zod: 25
```

## Framework Integration

### Rails

```ruby
# config/initializers/rhales.rb
Rhales.configure do |config|
  config.template_paths = ['app/templates']
  config.default_locale = 'en'
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  def render_rhales(template_name, client: {}, server: {})
    view = Rhales::View.new(request, client: client, server: server)
    view.render(template_name)
  end
end

# In your controller
def dashboard
  html = render_rhales('dashboard',
    client: { user: current_user.name, items: @items },
    server: { page_title: 'Dashboard' }
  )
  render html: html.html_safe
end
```

### Roda

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

  route do |r|
    r.on 'dashboard' do
      view = Rhales::View.new(
        request,
        client: { user: current_user.name },
        server: { page_title: 'Dashboard' }
      )
      view.render('dashboard')
    end
  end
end
```

### Sinatra

```ruby
require 'sinatra'
require 'rhales'

Rhales.configure do |config|
  config.template_paths = ['templates']
  config.default_locale = 'en'
end

helpers do
  def render_rhales(template_name, client: {}, server: {})
    view = Rhales::View.new(request, client: client, server: server)
    view.render(template_name)
  end
end

get '/dashboard' do
  render_rhales('dashboard',
    client: { user: 'Alice' },
    server: { page_title: 'Dashboard' }
  )
end
```

### Grape

```ruby
require 'grape'
require 'rhales'

Rhales.configure do |config|
  config.template_paths = ['templates']
  config.default_locale = 'en'
end

class MyAPI < Grape::API
  helpers do
    def render_rhales(template_name, client: {}, server: {})
      mock_request = OpenStruct.new(env: env)
      view = Rhales::View.new(mock_request, client: client, server: server)
      view.render(template_name)
    end
  end

  get '/dashboard' do
    content_type 'text/html'
    render_rhales('dashboard',
      client: { user: 'Alice' },
      server: { page_title: 'Dashboard' }
    )
  end
end
```

## Content Security Policy (CSP)

Rhales provides **security by default** with automatic CSP support.

### Default CSP Configuration

```ruby
Rhales.configure do |config|
  config.csp_enabled = true     # Default: true
  config.auto_nonce = true      # Default: true
end
```

### Using Nonces in Templates

```handlebars
<script nonce="{{request.nonce}}">
  // Inline JavaScript with automatic nonce
  console.log('Secure execution');
</script>

<style nonce="{{request.nonce}}">
  /* Inline styles with automatic nonce */
  .component { color: blue; }
</style>
```

### Custom CSP Policies

```ruby
Rhales.configure do |config|
  config.csp_policy = {
    'default-src' => ["'self'"],
    'script-src' => ["'self'", "'nonce-{{nonce}}'", 'https://cdn.example.com'],
    'style-src' => ["'self'", "'nonce-{{nonce}}'"],
    'img-src' => ["'self'", 'data:', 'https://images.example.com'],
    'connect-src' => ["'self'", 'https://api.example.com']
  }
end
```

### Framework CSP Header Setup

#### Rails

```ruby
class ApplicationController < ActionController::Base
  after_action :set_csp_header

  private

  def set_csp_header
    csp_header = request.env['csp_header']
    response.headers['Content-Security-Policy'] = csp_header if csp_header
  end
end
```

#### Roda

```ruby
class App < Roda
  def render_with_csp(template_name, **data)
    result = render_rhales(template_name, **data)
    csp_header = request.env['csp_header']
    response.headers['Content-Security-Policy'] = csp_header if csp_header
    result
  end
end
```

## Testing

### Test Configuration

```ruby
# test/test_helper.rb or spec/spec_helper.rb
require 'rhales'

Rhales.configure do |config|
  config.default_locale = 'en'
  config.app_environment = 'test'
  config.cache_templates = false
  config.template_paths = ['test/fixtures/templates']
end
```

### Testing Context

```ruby
# Minimal context for testing
context = Rhales::Context.minimal(
  client: { user: 'Test' },
  server: { page_title: 'Test Page' }
)

expect(context.get('user')).to eq('Test')
expect(context.get('page_title')).to eq('Test Page')
```

### Testing Templates

```ruby
# Test inline template
template = '{{#if active}}Active{{else}}Inactive{{/if}}'
result = Rhales.render_template(template, active: true)
expect(result).to eq('Active')

# Test .rue file
mock_request = OpenStruct.new(env: {})
view = Rhales::View.new(mock_request, client: { message: 'Hello' })
html = view.render('test_template')
expect(html).to include('Hello')
```

## Migration from v0.4 to v0.5

### Breaking Changes

1. **`<data>` sections removed** → Use `<schema>` sections
2. **Parameters removed:**
   - `sess` → Access via `request.session`
   - `cust` → Access via `request.user`
   - `props:` → Use `client:`
   - `app_data:` → Use `server:`
   - `locale` → Set via `request.env['rhales.locale']`
3. **Context layer renamed:** `app` → `request`

### Migration Steps

#### 1. Update Ruby Code

```ruby
# v0.4 (REMOVED)
view = Rhales::View.new(req, session, customer, 'en',
  props: { user: customer.name },
  app_data: { page_title: 'Dashboard' }
)

# v0.5 (Current)
view = Rhales::View.new(req,
  client: { user: customer.name },
  server: { page_title: 'Dashboard' }
)

# Set locale in request
req.env['rhales.locale'] = 'en'
```

#### 2. Convert Data to Schema

```xml
<!-- v0.4 (REMOVED) -->
<data window="data">
{
  "user": "{{user.name}}",
  "count": {{items.count}}
}
</data>

<!-- v0.5 (Current) -->
<schema lang="js-zod" window="data">
const schema = z.object({
  user: z.string(),
  count: z.number()
});
</schema>
```

**Key difference:** In v0.5, pass resolved values in `client:` hash instead of relying on template interpolation in JSON.

#### 3. Update Context References

```handlebars
<!-- v0.4 (REMOVED) -->
{{app.nonce}}
{{app.csrf_token}}

<!-- v0.5 (Current) -->
{{request.nonce}}
{{request.csrf_token}}
```

#### 4. Update Backend Data Passing

```ruby
# v0.4: Template interpolation
view = Rhales::View.new(req, sess, cust, 'en',
  props: { user: cust }  # Object reference, interpolated in <data>
)

# v0.5: Resolved values upfront
view = Rhales::View.new(req,
  client: {
    user: cust.name,      # Resolved value
    userId: cust.id       # Resolved value
  }
)
```

## Performance Optimization

### Optional: Oj for Faster JSON Processing

Rhales includes optional support for [Oj](https://github.com/ohler55/oj), a high-performance JSON library that provides:

- **10-20x faster JSON parsing** compared to stdlib
- **5-10x faster JSON generation** compared to stdlib
- **Lower memory usage** for large data payloads
- **Full compatibility** with stdlib JSON API

#### Installation

Add to your Gemfile:

```ruby
gem 'oj', '~> 3.13'
```

Then run:

```bash
bundle install
```

That's it! Rhales automatically detects Oj at load time and uses it for all JSON operations.

**Note:** The backend is selected once when Rhales loads. To ensure Oj is used, require it before Rhales:

```ruby
# Gemfile or application initialization
require 'oj'       # Load Oj first
require 'rhales'   # Rhales will detect and use Oj
```

Most bundler setups handle this automatically, but explicit ordering ensures optimal performance.

#### Verification

Check which backend is active:

```ruby
Rhales::JSONSerializer.backend
# => :oj (if available) or :json (stdlib)
```

#### Performance Impact

For typical Rhales applications with hydration data:

| Operation | stdlib JSON | Oj | Improvement |
|-----------|-------------|-----|-------------|
| Parse 100KB payload | ~50ms | ~3ms | **16x faster** |
| Generate 100KB payload | ~30ms | ~5ms | **6x faster** |
| Memory usage | Baseline | -20% | **Lower** |

**Recommendation:** Install Oj for production applications with:
- Large hydration payloads (>10KB)
- High-traffic endpoints (>100 req/sec)
- Complex nested data structures

Oj provides the most benefit for data-heavy templates and high-concurrency scenarios.

## Development

```bash
# Clone repository
git clone https://github.com/onetimesecret/rhales.git
cd rhales

# Install dependencies
bundle install

# Run tests
bundle exec rspec spec/rhales/

# Run with documentation format
bundle exec rspec spec/rhales/ --format documentation

# Build gem
gem build rhales.gemspec

# Install locally
gem install ./rhales-0.5.0.gem
```

## Contributing

1. Fork it (https://github.com/onetimesecret/rhales/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the [MIT License](https://opensource.org/licenses/MIT).

## AI Development Assistance

Rhales was developed with assistance from AI tools:

- **Claude Sonnet 4.5** - Architecture design, code generation, documentation
- **Claude Desktop & Claude Code** - Interactive development and debugging
- **GitHub Copilot** - Code completion and refactoring
- **Qodo Merge Pro** - Code review and quality improvements

I remain responsible for all design decisions and the final code. Being transparent about development tools as AI becomes more integrated into our workflows.
