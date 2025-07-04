# Rhales Roda Demo

This demo application showcases the power of Rhales RSFC (Ruby Single File Components) templates integrated with a Roda web application using Rodauth for authentication.

## Features Demonstrated

- **RSFC Templates**: Single file components with `<data>`, `<template>`, and `<logic>` sections
- **Client-Side Hydration**: Secure data injection with CSP nonce support
- **Authentication Integration**: Rodauth with custom Rhales adapters
- **Dynamic Content**: Posts management with CRUD operations
- **Handlebars Syntax**: Conditionals, iteration, and partials
- **API Integration**: Client-side fetching with hydrated configuration

## Prerequisites

Before starting, ensure you have:
- Ruby 3.0 or higher
- Bundler gem installed (`gem install bundler`)
- SQLite3 installed on your system

## Step-by-Step Setup Instructions

### Step 1: Navigate to the demo directory

From the root of the rhales gem repository:
```bash
cd demo/rhales-roda-demo
```

### Step 2: Install Ruby dependencies

```bash
bundle install
```

Expected output:
```
Fetching gem metadata from https://rubygems.org/...
Resolving dependencies...
Installing bcrypt 3.1.20...
Installing rack-session 2.0.0...
Installing sequel 5.85.0...
Installing roda 3.84.0...
...
Bundle complete! 11 Gemfile dependencies, XX gems now installed.
```

If you encounter errors:
```bash
# Update bundler
gem install bundler

# Try again
bundle install
```

### Step 4: (Optional but recommended) Seed the database

```bash
bundle exec ruby db/seed.rb
```

Expected output:
```
Seed data created successfully!
Demo accounts:
  - demo@example.com / password123
  - user@example.com / userpass
```

### Step 5: Start the web server

```bash
bundle exec rackup
```

Expected output:
```
Puma starting in single mode...
* Puma version: 6.4.2 (ruby 3.0.0-p0) ("The Eagle of Durango")
*  Min threads: 0
*  Max threads: 5
*  Environment: development
*          PID: 12345
* Listening on http://127.0.0.1:9292
* Listening on http://[::1]:9292
Use Ctrl-C to stop
```

### Step 6: Open your browser

Visit: http://localhost:9292

You should see the Rhales Demo homepage with feature cards.

## Testing the Demo

### Quick Test with Demo Account

1. Click **"Login"** in the top navigation
2. Enter credentials:
   - Email: `demo@example.com`
   - Password: `password123`
3. Click **"Login"** button
4. You should see a dashboard with:
   - Welcome message with the user's name
   - Stats showing Total Posts, Published, and Drafts
   - List of sample posts

### Create Your Own Account

1. From the homepage, click **"Register"**
2. Fill out the form:
   - Full Name: `Test User` (or your name)
   - Email: `test@example.com` (any email works)
   - Password: `testpass` (min 6 characters)
   - Confirm Password: `testpass`
3. Click **"Create Account"**
4. You'll be automatically logged in and redirected to an empty dashboard

### Test Post Management

1. Click **"New Post"** button on the dashboard
2. Fill out the form:
   - Title: `My First Post`
   - Content: `This is a test post using Rhales RSFC templates!`
   - Status: `Published`
3. Click **"Create Post"**
4. You should see:
   - Success message: "Post created successfully!"
   - Your post in the dashboard list
5. Try editing the post:
   - Click **"Edit"** on your post
   - Change the title or content
   - Click **"Update Post"**
6. Try deleting:
   - Click **"Delete"**
   - Confirm the deletion
   - Post should disappear with success message

### Test Client-Side Hydration

1. Click **"Profile"** in the navigation
2. You'll see your account information
3. Click **"Fetch Stats"** button
4. Watch as it makes an API call and displays JSON response
5. Open browser console (F12) to see hydration logs

### Logout

Click **"Logout"** in the navigation to end your session.

## Development Mode

For automatic server restarts when files change:

```bash
bundle exec rerun rackup
```

Now when you edit any `.rb` or `.rue` file, the server will restart automatically.

## Understanding the Code

### Key Files to Explore

1. **app.rb** - Main application file
   - Shows Rhales configuration
   - Custom auth/session adapters
   - Route definitions
   - `rhales_render` helper method

2. **templates/layouts/main.rue** - Layout template
   - Shows conditional navigation
   - CSP nonce usage in styles
   - Flash message handling

3. **templates/home.rue** - Homepage
   - Data hydration with `window` attribute
   - Feature iteration
   - Client-side JavaScript integration

4. **templates/dashboard/index.rue** - Dashboard
   - Uses partials (`{{> post_item}}`)
   - Conditional rendering
   - Stats display

## Troubleshooting

### Port 9292 already in use

```bash
# Use a different port
bundle exec rackup -p 9293

# Or find and kill the process using port 9292
lsof -i :9292
kill -9 <PID>
```

### Bundle install fails

```bash
# Check Ruby version
ruby -v  # Should be 3.0 or higher

# Update RubyGems
gem update --system

# Try installing problematic gems individually
gem install sqlite3 -v '2.0.0'
gem install rack-session -v '2.0.0'
```

### Rack::Session errors

If you see "uninitialized constant Rack::Session" or "invalid secret" errors:
```bash
bundle install  # Make sure rack-session and rackup gems are installed
bundle binstub rack  # Fix rackup binstub conflicts if needed
bundle exec rackup  # Try again
```

### SQLite3 LoadError

Install SQLite3 for your system:

```bash
# macOS
brew install sqlite3

# Ubuntu/Debian
sudo apt-get install sqlite3 libsqlite3-dev

# Fedora/RHEL
sudo dnf install sqlite sqlite-devel
```

Then reinstall the gem:
```bash
gem uninstall sqlite3
bundle install
```

### Template not found

Verify template files exist:
```bash
find templates -name "*.rue" | sort
```

Should show:
```
templates/auth/login.rue
templates/auth/register.rue
templates/dashboard/index.rue
templates/dashboard/post_form.rue
templates/dashboard/profile.rue
templates/home.rue
templates/layouts/main.rue
templates/partials/post_item.rue
```

### No CSS styling

The demo includes inline CSS in the layout. If styles aren't loading:
1. Check browser console for CSP errors
2. Verify the `{{runtime.nonce}}` is being replaced in templates
3. Try hard refresh (Ctrl+Shift+R or Cmd+Shift+R)

## Next Steps

1. Explore the `.rue` template files to understand RSFC structure
2. Modify templates and see live changes
3. Add new routes and templates
4. Integrate Rhales into your own Ruby applications

## Architecture Overview

- **Roda**: Lightweight Ruby web framework
- **Rodauth**: Full-featured authentication
- **Sequel**: Database toolkit with models
- **SQLite**: Zero-config database
- **Rhales**: RSFC template engine with hydration

This demo shows how Rhales integrates seamlessly with existing Ruby tools while adding powerful component-based templating.
