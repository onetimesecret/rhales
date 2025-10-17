# Rhales Roda Demo

This demo application showcases the power of Rhales RSFC (Ruby Single File Components) templates integrated with a Roda web application using Rodauth for authentication.

## Features Demonstrated

- **RSFC Templates**: Single file components with `<data>`, `<template>`, `<schema>`, and `<logic>` sections
- **Schema Validation**: Runtime validation of hydration data against Zod schemas
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
- Node.js and pnpm (for schema generation)

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

If you encounter errors:
```bash
# Update bundler
gem install bundler

# Try again
bundle install
```

### Step 3: Install Node.js dependencies (for schema generation)

```bash
pnpm install
```

If you don't have pnpm installed:
```bash
npm install -g pnpm
pnpm install
```

### Step 4: Generate JSON Schemas from templates

```bash
bundle exec rake rhales:schema:generate
```

This will:
- Parse all `.rue` templates with `<schema>` sections
- Execute Zod schema code to generate JSON Schemas
- Save generated schemas to `public/schemas/`

Expected output:
```
Schema Generation
============================================================
Templates: ./templates
Output: ./public/schemas
Zod: (using pnpm exec tsx)

Found 2 schema section(s):
  - login (js-zod)
  - dashboard (js-zod)

Generating JSON Schemas...
✓ Generated schema for: login
✓ Generated schema for: dashboard

Results:
------------------------------------------------------------
✓ Successfully generated 2 schema(s)
✓ Output directory: /path/to/demo/rhales-roda-demo/public/schemas
```

You can verify the generated schemas:
```bash
ls -la public/schemas/
cat public/schemas/login.json | jq .
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
   - Password: `demo123`
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

## Schema Generation and Validation

### Generating Schemas

Rhales uses Zod schemas defined in `.rue` templates to generate JSON Schemas for runtime validation:

```bash
# Generate all schemas
bundle exec rake rhales:schema:generate

# Custom paths
bundle exec rake rhales:schema:generate \
  TEMPLATES_DIR=./templates \
  OUTPUT_DIR=./public/schemas

# View statistics
bundle exec rake rhales:schema:stats

# Validate existing schemas
bundle exec rake rhales:schema:validate
```

### Schema Sections in Templates

Templates with `<schema>` sections define the shape of data they expect:

```html
<schema lang="js-zod" window="appData">
const schema = z.object({
  user: z.object({
    name: z.string(),
    email: z.string().email(),
  }),
  posts: z.array(z.object({
    id: z.number(),
    title: z.string(),
  })),
});
</schema>
```

### Runtime Validation

When schema validation is enabled (see `app.rb`), the middleware will:
- Extract hydration data from HTML responses
- Validate against the generated JSON Schema
- In development: Fail loudly with detailed error messages
- In production: Log warnings but continue serving

### Directory Structure

```
demo/rhales-roda-demo/
├── templates/           # Source .rue files
│   ├── login.rue       # With <schema> section
│   └── dashboard.rue   # With <schema> section
├── public/
│   └── schemas/        # Generated JSON Schemas (gitignored)
│       ├── login.json
│       └── dashboard.json
└── app.rb              # Schema validation middleware config
```

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
