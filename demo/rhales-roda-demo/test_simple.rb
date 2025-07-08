#!/usr/bin/env ruby

require_relative 'app'
require 'rack/mock'

# Create a mock rack env for the home page
env = Rack::MockRequest.env_for('/', method: 'GET')

begin
  app = RhalesDemo.app
  status, headers, body = app.call(env)
  puts "Status: #{status}"
  puts "Headers: #{headers}"
  puts "Body preview: #{body.first[0..200]}..."

  if status == 200
    puts "\n✅ SUCCESS: Tilt integration is working! Rhales templates are rendering."
  else
    puts "\n❌ ERROR: Got status #{status}"
  end
rescue => e
  puts "\n❌ ERROR: #{e.class}: #{e.message}"
  puts e.backtrace[0..5].join("\n")
end
