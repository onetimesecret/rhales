#!/usr/bin/env ruby

# Simple test to verify direct access works
require_relative 'lib/rhales'

# Create a test configuration
config = Rhales::Configuration.new do |conf|
  conf.template_paths = [File.join(__dir__, 'spec/fixtures/templates')]
end

# Create a view with test props
view = Rhales::View.new(
  nil, nil, nil, 'en',
  client: { 'greeting' => 'Hello World', 'user' => { 'name' => 'John Doe' } },
  config: config
)

# Render the template
result = view.render('test_direct_access')

puts "=== Rendered Output ==="
puts result
puts "======================="

# Check if direct access worked
if result.include?('Direct: Hello World')
  puts "✅ Direct access to 'message' works"
else
  puts "❌ Direct access to 'message' failed"
end

if result.include?('User: John Doe')
  puts "✅ Direct access to 'userName' works"
else
  puts "❌ Direct access to 'userName' failed"
end
