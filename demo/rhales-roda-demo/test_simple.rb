#!/usr/bin/env ruby

require_relative 'app'
require 'rack/mock'

# Test the view method directly
class TestApp < RhalesDemo
  def test_view
    # Mock request/response
    env = Rack::MockRequest.env_for('/', method: 'GET')
    @request = Rack::Request.new(env)
    @response = Rack::Response.new

    # Test calling view method
    begin
      result = view('home')
      puts "✅ SUCCESS: view('home') returned #{result.length} characters"
      puts "Preview: #{result[0..200]}..."
      return true
    rescue => e
      puts "❌ ERROR: #{e.class}: #{e.message}"
      puts e.backtrace[0..3].join("\n")
      return false
    end
  end
end

app = TestApp.new
app.test_view
