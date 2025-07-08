#!/usr/bin/env ruby

require_relative 'app'
require 'rack/mock'

# Create a mock rack env for the home page
env = Rack::MockRequest.env_for('/', method: 'GET')

begin
  app                   = RhalesDemo.app
  _status, _headers, body = app.call(env)

  puts '=== FULL OUTPUT ==='
  puts body.first
  puts '=== END OUTPUT ==='

  # Check for demo accounts
  if body.first.include?('demo@example.com')
    puts "\n✅ Demo accounts are rendering correctly!"
  else
    puts "\n❌ Demo accounts are NOT rendering!"
    puts "Looking for 'demo_accounts' in template locals..."
  end
rescue StandardError => ex
  puts "❌ ERROR: #{ex.class}: #{ex.message}"
  puts ex.backtrace[0..5].join("\n")
end
