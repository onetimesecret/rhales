#!/usr/bin/env ruby

require_relative 'lib/rhales'

# Test props with both symbols and strings
props = {
  'greeting' => 'Hello World',
  'user' => { 'name' => 'John Doe', 'role' => 'admin' },
  'authenticated' => true,
  'items' => [
    { 'name' => 'Item 1', 'active' => true },
    { 'name' => 'Item 2', 'active' => false }
  ]
}

context = Rhales::Context.minimal(props: props)

puts "=== Context Variables ==="
puts "greeting: #{context.get('greeting')}"
puts "user.name: #{context.get('user.name')}"
puts "items.0.name: #{context.get('items.0.name')}"
puts "items.0.active: #{context.get('items.0.active')}"
puts "items.1.name: #{context.get('items.1.name')}"
puts "items.1.active: #{context.get('items.1.active')}"
puts "========================="
