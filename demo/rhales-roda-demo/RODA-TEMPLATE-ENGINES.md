# Custom Template Engines in Roda

Roda's render plugin uses Tilt to support multiple template engines. You can use any template engine that Tilt supports, or integrate custom template engines in several ways.

## Using Template Engines Already Supported by Tilt

Tilt supports 25+ template engines out of the box. To use a different engine, specify it in the `:engine` option:

```ruby
plugin :render, engine: 'haml'
plugin :render, engine: 'slim'
plugin :render, engine: 'liquid'
```

You can also specify the engine per template:

```ruby
render('template', engine: 'haml')
view('template', engine: 'slim')
```

## Adding New Template Engines to Tilt

As of 2025, Tilt is actively maintained by Jeremy Evans but no longer accepts new community template engine integrations in the main gem. If you want to add support for a template engine not currently supported by Tilt, you should:

1. Create a separate gem that provides Tilt integration for your template engine
2. Have the template engine itself ship with Tilt integration

To register a new template engine with Tilt:

```ruby
# In your gem or application
require 'tilt'

class MyTemplateEngine < Tilt::Template
  def prepare
    # Parse/compile template during template creation
  end

  def evaluate(scope, locals, &block)
    # Render template with given scope and locals
  end
end

# Register with Tilt
Tilt.register MyTemplateEngine, 'myengine'

# Or for multiple extensions
Tilt.register MyTemplateEngine, 'myengine', 'mytempl'
```

Then use it in Roda:

```ruby
plugin :render, engine: 'myengine'
render('template') # renders template.myengine
```

## Using Custom Template Classes Directly

For maximum control, you can bypass Tilt entirely and provide your own template class using the `:template_class` option:

```ruby
class MyCustomTemplate
  def initialize(file, line, options={}, &block)
    @template_string = block ? block.call : File.read(file)
    # Custom initialization
  end

  def render(scope, locals={}, &block)
    # Custom rendering logic
    # Return rendered string
  end
end

# Use globally
plugin :render, template_class: MyCustomTemplate

# Or per-template
render('template', template_class: MyCustomTemplate)
```

## Engine-Specific Options

Configure options for specific template engines using `:engine_opts`:

```ruby
plugin :render,
  engine_opts: {
    'erb' => {default_encoding: 'UTF-8'},
    'haml' => {format: :html5, escape_html: true},
    'slim' => {pretty: true}
  }
```

## Example: Adding Mustache Support

Here's a complete example of adding Mustache template support:

```ruby
require 'mustache'
require 'tilt'

class TiltMustacheTemplate < Tilt::Template
  def prepare
    @engine = Mustache.new
    @engine.template = data
  end

  def evaluate(scope, locals, &block)
    @engine.render(locals)
  end
end

Tilt.register TiltMustacheTemplate, 'mustache'

# In your Roda app
plugin :render, engine: 'mustache'

route do |r|
  r.get do
    view('template', locals: {name: 'World'}) # renders template.mustache
  end
end
```

## Tilt Maintenance Status

**Current Status**: Tilt is actively maintained by Jeremy Evans (also the maintainer of Roda) as of 2025.

**Recent Activity**:
- Version 2.6.0 released January 13, 2025
- Version 2.5.0 released December 20, 2024
- 0 open issues and pull requests (excellent maintenance)

**Policy on New Engines**: The Tilt team no longer accepts new community-maintained template integrations into the main gem. New template engines should implement their own Tilt compatibility in separate gems.

**Supported Engines**: Tilt currently supports 25+ template engines including ERB, Erubi, Haml, Slim, Markdown engines (CommonMarker, Kramdown, Redcarpet), Sass/SCSS, CoffeeScript, TypeScript, Liquid, Builder, Nokogiri, and many more.

## Best Practices

1. **Use existing engines**: Check if Tilt already supports your desired template engine before creating a custom integration.

2. **Separate gems**: If you need a new template engine, create a separate gem with Tilt integration rather than modifying Tilt directly.

3. **Performance**: Use the `:template_class` option for maximum performance if you don't need Tilt's generic interface.

4. **Caching**: Custom template classes should support Roda's caching mechanisms for best performance.

5. **Error handling**: Ensure your custom template engines provide proper error messages with filename and line number information.
