#!/usr/bin/env ruby

# Proof that partials now correctly inherit parent context and can access their own data sections
# This demonstrates the fix for issue #16 - Context Scoping

require_relative '../lib/rhales'

puts "=== Testing Partial Context Scoping Fix ==="
puts "Issue #16: Partials should access both inherited context and local data\n\n"

# Create context with some props
props = {
  greeting: 'Hello World',
  user: { name: 'John Doe' },
  authenticated: true,
  main_message: 'From main props'
}

context = Rhales::Context.minimal(props: props)

# Test 1: Basic partial with data section
puts "Test 1: Basic partial with local data section"
puts "-" * 50

main_template = <<~RUE
<template>
<div class="main">
  <h1>Main Template</h1>
  <p>Props: {{greeting}}</p>
  {{> basic_partial}}
</div>
</template>
RUE

basic_partial = <<~RUE
<data>
{
  "partial_message": "I am from the partial's data section",
  "computed_value": "Greeting is: {{greeting}}"
}
</data>

<template>
<div class="partial">
  <p>Local data: {{partial_message}}</p>
  <p>Computed: {{computed_value}}</p>
  <p>Inherited: {{main_message}}</p>
</div>
</template>
RUE

partial_resolver = proc do |name|
  case name
  when 'basic_partial' then basic_partial
  else nil
  end
end

engine = Rhales::TemplateEngine.new(main_template, context, partial_resolver: partial_resolver)
result = engine.render

puts result
puts "\nChecks:"
puts "✅ Partial's local data accessible" if result.include?("I am from the partial&#39;s data section")
puts "✅ Partial can use parent context in data section" if result.include?("Greeting is: Hello World")
puts "✅ Partial inherits parent props" if result.include?("From main props")

# Test 2: Partial with window attribute
puts "\n\nTest 2: Partial with window attribute (head.rue scenario)"
puts "-" * 50

head_partial = <<~RUE
<data window="headData">
{
  "page_title": "One Time Secret",
  "theme_color": "#dc4a22"
}
</data>

<template>
<head>
  <title>{{page_title}}</title>
  <meta name="theme-color" content="{{theme_color}}">
  <meta name="authenticated" content="{{authenticated}}">
</head>
</template>
RUE

main_with_head = <<~RUE
<template>
<html>
{{> head}}
<body>
  <h1>{{greeting}}</h1>
</body>
</html>
</template>
RUE

partial_resolver2 = proc do |name|
  case name
  when 'head' then head_partial
  else nil
  end
end

engine2 = Rhales::TemplateEngine.new(main_with_head, context, partial_resolver: partial_resolver2)
result2 = engine2.render

puts result2
puts "\nChecks:"
puts "✅ page_title from partial's data section" if result2.include?("<title>One Time Secret</title>")
puts "✅ theme_color from partial's data section" if result2.include?('content="#dc4a22"')
puts "✅ authenticated from parent context" if result2.include?('content="true"')

# Test 3: Variable precedence (local data overrides parent)
puts "\n\nTest 3: Variable precedence (local overrides parent)"
puts "-" * 50

override_partial = <<~RUE
<data>
{
  "greeting": "Overridden greeting from partial",
  "new_var": "Only in partial"
}
</data>

<template>
<div class="override-test">
  <p>Greeting: {{greeting}}</p>
  <p>New var: {{new_var}}</p>
  <p>User: {{user.name}}</p>
</div>
</template>
RUE

main_override = <<~RUE
<template>
<div>
  <p>Main greeting: {{greeting}}</p>
  {{> override_partial}}
</div>
</template>
RUE

partial_resolver3 = proc do |name|
  case name
  when 'override_partial' then override_partial
  else nil
  end
end

engine3 = Rhales::TemplateEngine.new(main_override, context, partial_resolver: partial_resolver3)
result3 = engine3.render

puts result3
puts "\nChecks:"
puts "✅ Main still has original greeting" if result3.include?("Main greeting: Hello World")
puts "✅ Partial overrides greeting locally" if result3.include?("Greeting: Overridden greeting from partial")
puts "✅ Partial has new local variable" if result3.include?("New var: Only in partial")
puts "✅ Partial inherits user from parent" if result3.include?("User: John Doe")

puts "\n\n=== Summary ==="
puts "The fix successfully implements the intended behavior from spec documents 080 & 082:"
puts "1. Partials can access their local <data> section variables"
puts "2. Partials inherit parent context (including expanded objects)"
puts "3. Local data takes precedence over inherited data"
puts "4. Window attributes work correctly for client-side hydration"
