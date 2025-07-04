# Rhales Roda Demo

This demo application showcases the power of Rhales RSFC (Ruby Single File Components) templates integrated with a Roda web application using Rodauth for authentication.

## Features Demonstrated

- **RSFC Templates**: Single file components with `<data>`, `<template>`, and `<logic>` sections
- **Client-Side Hydration**: Secure data injection with CSP nonce support
- **Authentication Integration**: Rodauth with custom Rhales adapters
- **Dynamic Content**: Posts management with CRUD operations
- **Handlebars Syntax**: Conditionals, iteration, and partials
- **API Integration**: Client-side fetching with hydrated configuration

## Setup and Installation

1. Install dependencies:
```bash
cd demo/rhales-roda-demo
bundle install
```

2. Create the database directory:
```bash
mkdir -p db
```

3. Run the application:
```bash
bundle exec rackup
```

Or use rerun for auto-reloading in development:
```bash
bundle exec rerun rackup
```

4. Visit http://localhost:9292

## Demo Accounts

- `demo@example.com` / `password123`
- `user@example.com` / `userpass`

Or create your own account via the registration page.

## Key Files

### Application Structure
- `app.rb` - Main Roda application with Rodauth integration
- `config.ru` - Rack configuration file
- `Gemfile` - Ruby dependencies

### RSFC Templates
- `templates/layouts/main.rue` - Main layout with navigation
- `templates/home.rue` - Homepage with feature showcase
- `templates/auth/login.rue` - Login form with demo accounts
- `templates/auth/register.rue` - Registration with dynamic fields
- `templates/dashboard/index.rue` - User dashboard with stats
- `templates/dashboard/post_form.rue` - Create/edit posts
- `templates/dashboard/profile.rue` - User profile with API demo
- `templates/partials/post_item.rue` - Reusable post component

## RSFC Template Features

### Data Section
```erb
<data window="customName">
{
  "key": "value",
  "dynamic": "{{variable}}"
}
</data>
```

### Template Section
```erb
<template>
  {{#if condition}}
    <p>{{variable}}</p>
  {{else}}
    <p>Alternative content</p>
  {{/if}}
  
  {{#each items}}
    <li>{{name}}</li>
  {{/each}}
  
  {{> partial_name}}
</template>
```

### Logic Section
```erb
<logic>
# Ruby code or comments
# Describes component behavior
</logic>
```

## Rhales Configuration

The demo configures Rhales with:
- Custom authentication adapter for Rodauth
- Session adapter for session management
- Template caching disabled for development
- CSP nonce support for inline scripts

## Development

To modify templates, edit the `.rue` files in the `templates` directory. Changes are reflected immediately with template caching disabled.

To add new features:
1. Create new `.rue` templates
2. Add routes in `app.rb`
3. Use the `rhales_render` helper method

## Architecture

- **Roda**: Lightweight Ruby web framework
- **Rodauth**: Authentication framework
- **Sequel**: Database toolkit
- **SQLite**: Development database
- **Rhales**: RSFC template engine

This demo showcases how Rhales can be integrated into any Ruby web application to provide powerful, component-based templating with secure client-side hydration.