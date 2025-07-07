#!/usr/bin/env ruby
# proofs/error_handling.rb

require_relative 'lib/rhales'

# Example demonstrating the new error hierarchy

puts '=== Rhales Error Hierarchy Demo ==='
puts

# 1. Catching all Rhales errors
begin
  template = '{{#if user}}Hello{{else'  # Missing closing {{/if}}
  context  = Rhales::Context.minimal(business_data: { user: 'John' })
  Rhales::TemplateEngine.render(template, context)
rescue Rhales::Error => ex
  puts "Caught any Rhales error: #{ex.class} - #{ex.message}"
end

puts

# 2. Catching render errors (which wrap parse errors)
begin
  template = '{{unclosed'
  context  = Rhales::Context.minimal(business_data: {})
  Rhales::TemplateEngine.render(template, context)
rescue Rhales::TemplateEngine::RenderError => ex
  puts 'Render error wrapping parse error:'
  puts "  Class: #{ex.class}"
  puts "  Message: #{ex.message}"
end

puts

# 2b. Catching parse errors directly from parser
begin
  parser = Rhales::HandlebarsParser.new('{{unclosed')
  parser.parse!
rescue Rhales::ParseError => ex
  puts 'Direct parse error details:'
  puts "  Class: #{ex.class}"
  puts "  Message: #{ex.message}"
  puts "  Source type: #{ex.source_type}"
  puts "  Line: #{ex.line}, Column: #{ex.column}"
end

puts

# 3. Validation error from Parser
begin
  template = <<~RUE
    <logic>
    # Missing required sections
    </logic>
  RUE

  parser = Rhales::RueDocument.new(template)
  parser.parse!
rescue Rhales::ValidationError => ex
  puts "Validation error: #{ex.class} - #{ex.message}"
end

puts

# 4. Render error example
begin
  template = '{{> missing_partial}}'
  context  = Rhales::Context.minimal(business_data: {})
  Rhales::TemplateEngine.render(template, context)
rescue Rhales::RenderError => ex
  puts "Render error: #{ex.class} - #{ex.message}"
end

puts
puts '=== Benefits of the new hierarchy ==='
puts '1. Single rescue for all Rhales errors: rescue Rhales::Error'
puts '2. Stage-specific handling: ParseError, ValidationError, RenderError'
puts '3. Consistent error attributes across all parse errors'
puts '4. Better error messages with source context'
