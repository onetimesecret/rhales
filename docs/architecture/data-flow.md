# Rhales Data Flow Architecture

This document explains how data flows from your Ruby code through Rhales templates to the browser, with critical security considerations.

## Table of Contents

1. [Overview](#overview)
2. [Three-Layer Context Model](#three-layer-context-model)
3. [Complete Data Flow](#complete-data-flow)
4. [Critical Security Model](#critical-security-model)
5. [Tilt Integration](#tilt-integration)
6. [Schema Role: Validator vs Filter](#schema-role-validator-vs-filter)
7. [Layout Data Inheritance](#layout-data-inheritance)
8. [Best Practices](#best-practices)

## Overview

Rhales implements a **three-layer context system** that separates data concerns:

- **Request Layer**: Framework-provided data (CSRF tokens, nonces, auth status)
- **Server Layer**: Template-only data (never sent to browser)
- **Client Layer**: Data serialized to browser (explicitly controlled by developer)

**Key Principle**: The schema validates data contracts but does NOT filter which data gets serialized. YOU choose what goes in `client:`.

## Three-Layer Context Model

### Layer 1: Request (Framework Data)

Automatically populated from the request object:

```ruby
# Automatically available in templates
{{request.nonce}}          # CSP nonce
{{request.csrf_token}}     # CSRF token
{{request.authenticated?}} # Auth status
{{request.locale}}         # Current locale
{{request.session}}        # Session object
{{request.user}}           # User object
```

**Source**: `lib/rhales/context.rb:49-74` - `build_app_data` method

### Layer 2: Server (Template-Only)

Data that stays on the server, never serialized to browser:

```ruby
view = Rhales::View.new(request,
  server: {
    page_title: 'Dashboard',
    vite_assets_html: vite_javascript_tag('app'),
    admin_notes: 'Internal only',
    secret_config: ENV['SECRET_KEY']
  }
)
```

```handlebars
<!-- Available in templates -->
<title>{{server.page_title}}</title>
{{{server.vite_assets_html}}}

<!-- NOT sent to browser -->
<!-- Admin notes and secrets stay server-side -->
```

**Source**: `lib/rhales/context.rb:37` - `@server_data`

### Layer 3: Client (Serialized to Browser)

Data explicitly serialized to browser window state:

```ruby
view = Rhales::View.new(request,
  client: {
    user: current_user.public_data,
    items: Item.all.map(&:to_json_api),
    config: { apiUrl: ENV['PUBLIC_API_URL'] }
  }
)
```

```handlebars
<!-- Available in templates AND browser -->
<h1>Welcome {{client.user.name}}</h1>
```

```javascript
// Also available in browser
window.appData = {
  user: { name: 'Alice', ... },
  items: [...],
  config: { apiUrl: 'https://api.example.com' }
}
```

**Source**: `lib/rhales/context.rb:34` - `@client_data`

## Complete Data Flow

### Step 1: Developer Provides Data

```ruby
# lib/rhales/view.rb:82-93
View.new(req, locale_override = nil,
  client: { safe_public_data },   # ← Developer chooses
  server: { template_only_data }, # ← Developer chooses
  config: config
)
```

### Step 2: Context Initialization

```ruby
# lib/rhales/context.rb:28-47
def initialize(req, locale_override = nil, client: {}, server: {}, config: nil)
  # Normalize and freeze data
  @client_data = normalize_keys(client).freeze
  @server_data = build_app_data.merge(normalize_keys(server)).freeze

  # Templates get EVERYTHING (merged)
  @all_data = @server_data.merge(@client_data).merge({'app' => @server_data}).freeze

  # Make context immutable
  freeze
end
```

**Result**: Three frozen hashes:
- `@client_data` → Will be serialized
- `@server_data` → Template-only
- `@all_data` → What templates see

### Step 3: Template Rendering

Templates access data via `@all_data` with layer fallback:

```handlebars
<!-- Explicit layer access -->
{{client.user}}
{{server.page_title}}
{{request.nonce}}

<!-- Shorthand (checks client → server → request) -->
{{user}}        <!-- Finds in client layer -->
{{page_title}}  <!-- Finds in server layer -->
{{nonce}}       <!-- Finds in request layer -->
```

**Source**: `lib/rhales/template_engine.rb:157-174` - Variable resolution

### Step 4: Data Serialization

```ruby
# lib/rhales/hydrator.rb:64-76
def process_data_section
  if @parser.schema_lang
    # Serialize ENTIRE client data (NO filtering by schema)
    JSONSerializer.dump(@context.client)  # ← ALL of @client_data
  else
    '{}'
  end
end
```

**Critical**: This serializes the ENTIRE `@client_data` hash. The schema does NOT filter this.

### Step 5: Schema Validation (Optional Middleware)

```ruby
# lib/rhales/middleware/schema_validator.rb:86-96
errors = validate_hydration_data(hydration_data, schema, template_name)

# Validates AFTER serialization
# If validation fails:
#   - Development: Raises error
#   - Production: Logs warning
# But data already in HTML response!
```

**Critical**: Validation happens AFTER serialization. It cannot prevent data from reaching the browser.

### Step 6: Browser Receives

```html
<!-- Hydration script automatically injected -->
<script id="rsfc-data-xyz" type="application/json" data-window="appData">
{"user":"Alice","password":"secret123","api_key":"xyz"}
</script>

<script nonce="abc">
window.appData = JSON.parse(document.getElementById('rsfc-data-xyz').textContent);
</script>
```

If you passed secrets in `client:`, they're now in the browser. The schema can't stop this.

## Critical Security Model

### ⚠️ Schema is a Validator, NOT a Filter

**Common Misconception**: "The schema determines what data gets sent to the browser"

**Reality**: The schema validates that serialized data matches a contract. It does NOT filter what gets serialized.

#### What Actually Happens

```ruby
# Step 1: Developer passes data
view = Rhales::View.new(request,
  client: {
    name: 'Alice',
    password: 'secret123',  # ⚠️ Mistake!
    api_key: 'xyz'          # ⚠️ Mistake!
  }
)

# Step 2: Hydrator serializes EVERYTHING
# lib/rhales/hydrator.rb:69
JSONSerializer.dump(@context.client)
# Result: {"name":"Alice","password":"secret123","api_key":"xyz"}

# Step 3: HTML rendered with data
html = view.render('dashboard')
# Result includes: <script>window.data = {"name":"Alice","password":"secret123",...}</script>

# Step 4: Middleware validates (OPTIONAL, happens AFTER HTML generated)
# Schema in template:
# const schema = z.object({ name: z.string() });
#
# Validation FAILS because password/api_key not in schema
# But data ALREADY in HTML response sent to browser!
```

#### Developer Responsibility

**You MUST ensure** `client:` hash contains ONLY safe data:

```ruby
# ✅ SAFE - Only public data
client: {
  user: current_user.name,
  userId: current_user.id,
  theme: current_user.theme_preference
}

# ⚠️ DANGEROUS - Includes sensitive data
client: {
  user: current_user,  # Might include email, phone, etc
  session_token: session[:token],
  admin_secret: ENV['ADMIN_KEY']
}
```

**Best Practice**: Create explicit serializer methods:

```ruby
class User
  def to_client_data
    {
      id: id,
      name: name,
      avatar_url: avatar_url
      # Explicitly exclude: email, password_digest, api_tokens, etc
    }
  end
end

# Usage
view = Rhales::View.new(request,
  client: {
    user: current_user.to_client_data,
    ...
  }
)
```

## Tilt Integration

### Default Behavior: Everything Serialized

When using Tilt (Roda's `view()` helper, Sinatra, etc), the default behavior is **serialize everything**:

```ruby
# lib/rhales/tilt.rb:179-180
client_data = props.delete(:client_data) || props.dup  # ← Fallback!
server_data = props.delete(:server_data) || {}
```

**This means**:

```ruby
# ⚠️ DANGEROUS - All locals serialized by default!
view('dashboard', locals: {
  user: current_user,        # → Serialized (may include email, etc)
  secret: ENV['SECRET_KEY'], # → Serialized!
  title: 'Dashboard'         # → Serialized
})

# Browser gets:
# window.data = {
#   user: { id: 1, name: 'Alice', email: 'alice@example.com', ... },
#   secret: 'super_secret_key',
#   title: 'Dashboard'
# }
```

### Safe Tilt Usage: Explicit Separation

```ruby
# ✅ SAFE - Explicit client/server separation
view('dashboard', locals: {
  client_data: {
    user: current_user.public_data,
    count: Item.count
  },
  server_data: {
    secret: ENV['SECRET_KEY'],
    title: 'Dashboard',
    vite_assets: vite_javascript_tag('app')
  }
})
```

### Recommended Pattern: Helper Method

```ruby
# app.rb or controller
def template_locals(page_data = {})
  {
    client_data: {
      authenticated: logged_in?,
      locale: I18n.locale
    }.merge(page_data.fetch(:client, {})),

    server_data: {
      csrf_token: csrf_token,
      flash_notice: flash[:notice]
    }.merge(page_data.fetch(:server, {}))
  }
end

# Usage
view('dashboard', locals: template_locals(
  client: { user: current_user.public_data },
  server: { admin_note: 'Internal only' }
))
```

**Source**: `demo/rhales-roda-demo/app.rb:286-320` - Example implementation

## Layout Data Inheritance

Layouts receive a **merged context** with rendered content:

```ruby
# lib/rhales/view.rb:376
layout_context = context_with_rue_data.merge_client('content' => content_html)
```

**This means**:

1. Layout sees **all client data** from child template
2. Layout sees **all server data** from child template
3. Layout gets special `{{content}}` variable with rendered child HTML
4. Layout can add its own client/server data (merged, not replaced)

**Example**:

```xml
<!-- Child template: dashboard.rue -->
<schema lang="js-zod" window="pageData">
const schema = z.object({
  user: z.string()
});
</schema>

<template>
<h1>Dashboard for {{user}}</h1>
</template>
```

```xml
<!-- Layout: layouts/main.rue -->
<schema lang="js-zod" window="layoutData">
const schema = z.object({
  siteName: z.string()
});
</schema>

<template>
<!DOCTYPE html>
<html>
<head><title>{{siteName}}</title></head>
<body>
  {{content}}  <!-- ← Rendered child -->
  <!-- Layout sees {{user}} from child -->
  <footer>Logged in as: {{user}}</footer>
</body>
</html>
</template>
```

**Browser receives**:
```javascript
window.pageData = { user: 'Alice' }          // From child
window.layoutData = { siteName: 'My App' }   // From layout
```

## Best Practices

### 1. Explicit Serializers

```ruby
# app/serializers/user_client_serializer.rb
class UserClientSerializer
  def self.call(user)
    {
      id: user.id,
      name: user.name,
      avatar_url: user.avatar_url
      # Explicitly exclude sensitive fields
    }
  end
end

# Usage
view = Rhales::View.new(request,
  client: {
    user: UserClientSerializer.call(current_user)
  }
)
```

### 2. Schema-First Development

Write the schema FIRST, then ensure `client:` hash matches:

```xml
<!-- 1. Define schema -->
<schema lang="js-zod" window="data">
const schema = z.object({
  userId: z.number(),
  userName: z.string(),
  theme: z.enum(['light', 'dark'])
});
</schema>
```

```ruby
# 2. Ensure client hash matches
view = Rhales::View.new(request,
  client: {
    userId: current_user.id,
    userName: current_user.name,
    theme: current_user.theme_preference
    # If you add fields here, update schema!
  }
)
```

### 3. Schema Validation Middleware

Enable in development to catch mismatches early:

```ruby
# config.ru or app initialization
use Rhales::Middleware::SchemaValidator,
  schemas_dir: './public/schemas',
  fail_on_error: ENV['RACK_ENV'] == 'development'
```

This catches contract violations but doesn't prevent data leaks.

### 4. Code Review Checklist

- [ ] All `client:` data is safe for public exposure
- [ ] No passwords, API keys, or secrets in `client:`
- [ ] Sensitive data moved to `server:` layer
- [ ] Schema matches actual `client:` hash structure
- [ ] Explicit serializers used for complex objects
- [ ] Tilt integration uses `:client_data`/`:server_data` keys

## Summary

**Data Flow**: `View.new(client:, server:)` → Context → Templates (see all) → Hydrator (serializes ALL client) → Browser

**Security Model**: Developer chooses what's in `client:` → Entire `client:` serialized → Schema validates contract

**Critical**: Schema does NOT filter data. It validates that what you serialized matches the contract.

**Your Responsibility**: Ensure `client:` contains ONLY safe, public data.

**References**:
- `lib/rhales/context.rb` - Three-layer model
- `lib/rhales/hydrator.rb:69` - Client serialization
- `lib/rhales/middleware/schema_validator.rb` - Post-serialization validation
- `lib/rhales/tilt.rb:179-180` - Default fallback behavior
