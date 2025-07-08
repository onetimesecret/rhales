#!/usr/bin/env ruby

# Just check if the plugin can be loaded and registered
require 'roda'
require_relative 'lib/roda/plugins/rhales'

puts "Plugin loaded successfully!"

# Check if the plugin was registered
if Roda::RodaPlugins.constants.include?(:Rhales)
  puts "✅ Plugin registered as Roda::RodaPlugins::Rhales"
else
  puts "❌ Plugin not registered"
end

# Test plugin in a minimal app
class TestApp < Roda
  plugin :rhales, template_paths: ['templates'], layout: 'layouts/main'

  route do |r|
    r.root do
      "Plugin loaded successfully in route"
    end
  end
end

puts "✅ Minimal test app with plugin created successfully"

# Check if view method exists
test_app = TestApp.allocate
if test_app.respond_to?(:view)
  puts "✅ view method exists"
else
  puts "❌ view method not found"
end

if test_app.respond_to?(:rhales)
  puts "✅ rhales method exists"
else
  puts "❌ rhales method not found"
end
