#!/usr/bin/env ruby
# demo/logging_demo.rb
# Demonstration of Rhales native logging capabilities

require 'bundler/setup'
require_relative '../lib/rhales'
require 'logger'

# Configure logging to show different levels
logger = Logger.new($stdout)
logger.level = Logger::DEBUG
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%H:%M:%S')}] #{severity.ljust(5)} -- #{msg}\n"
end

puts "=== Rhales Native Logging Demo ==="
puts "Configuring Rhales with custom logger..."
puts

# Set up Rhales with custom logger
Rhales.logger = logger
Rhales::View.logger = logger
Rhales::TemplateEngine.logger = logger
Rhales::CSP.logger = logger

Rhales.configure do |config|
  config.template_paths = [File.join(__dir__, '../spec/fixtures/templates')]
  config.csp_enabled = true
  config.auto_nonce = true
end

puts "=== 1. View Rendering Logging ==="
begin
  # Create a mock request
  mock_request = Struct.new(:env).new({})
  
  # Create view with client data
  view = Rhales::View.new(
    mock_request,
    client: {
      user: 'demo_user',
      items: [
        { id: 1, name: 'Widget', price: 19.99 },
        { id: 2, name: 'Gadget', price: 29.99 }
      ]
    },
    server: {
      page_title: 'Demo Dashboard',
      debug_info: 'Internal use only'
    }
  )
  
  # This will trigger view rendering logs
  puts "Rendering template with logging..."
  html = view.render_template_only('{{server.page_title}}: {{client.user}} has {{client.items.size}} items')
  puts "✓ Template rendered successfully"
  
rescue => e
  puts "✗ Template render failed: #{e.message}"
end

puts "\n=== 2. Template Engine Logging ==="
begin
  # Direct template engine usage
  context = Rhales::Context.minimal(client: { 
    message: '<script>alert("xss")</script>',
    safe_content: 'Hello World'
  })
  
  # Test unescaped variable logging (security warning)
  puts "Testing unescaped variable (should trigger security warning):"
  engine = Rhales::TemplateEngine.new('Unsafe: {{{message}}} | Safe: {{safe_content}}', context)
  result = engine.render
  puts "Result: #{result[0..50]}..."
  
rescue => e
  puts "✗ Template engine failed: #{e.message}"
end

puts "\n=== 3. CSP Security Logging ==="
begin
  # CSP nonce generation
  puts "Generating CSP nonces:"
  3.times do |i|
    nonce = Rhales::CSP.generate_nonce
    puts "Generated nonce #{i + 1}: #{nonce[0..8]}..."
  end
  
  # CSP header building
  config = Rhales.configuration
  csp = Rhales::CSP.new(config, nonce: 'demo-nonce-123')
  header = csp.build_header
  puts "CSP header length: #{header&.length || 0} characters"
  
rescue => e
  puts "✗ CSP logging failed: #{e.message}"
end

puts "\n=== 4. Error Logging ==="
begin
  # Trigger parse error for logging demonstration
  puts "Testing parse error logging:"
  context = Rhales::Context.minimal(client: {})
  engine = Rhales::TemplateEngine.new('{{unclosed', context)
  engine.render
rescue => e
  puts "✓ Parse error caught and logged: #{e.message[0..50]}..."
end

puts "\n=== 5. Performance Logging ==="
begin
  # Test template composition and caching
  puts "Testing template composition logging:"
  
  # Simulate a complex template with partials
  mock_loader = lambda do |template_name|
    case template_name
    when 'dashboard'
      Rhales::RueDocument.new(<<~RUE)
        <template>
        <h1>{{title}}</h1>
        {{> header}}
        {{> content}}
        </template>
      RUE
    when 'header'
      Rhales::RueDocument.new('<template><nav>Navigation</nav></template>')
    when 'content'
      Rhales::RueDocument.new('<template><main>{{content}}</main></template>')
    else
      nil
    end
  end
  
  composition = Rhales::ViewComposition.new('dashboard', loader: mock_loader)
  composition.resolve!
  puts "✓ Template composition resolved successfully"
  
rescue => e
  puts "✗ Performance logging failed: #{e.message}"
end

puts "\n=== Demo Complete ==="
puts "Check the log output above to see:"
puts "• View rendering with timing and hydration size"
puts "• Template compilation with cache status" 
puts "• Security warnings for unescaped variables"
puts "• CSP nonce generation with entropy metrics"
puts "• Parse errors with line/column context"
puts "• Template composition and partial resolution"
puts "• Performance metrics and cache statistics"
puts
puts "In production, configure with SemanticLogger for structured JSON logs:"
puts "  Rhales.logger = SemanticLogger['Rhales']"