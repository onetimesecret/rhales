# spec/rhales/namespace_inconsistency_spec.rb

require 'spec_helper'

# TDD - demonstrates current BROKEN behavior that needs to be fixed
#
# NAMESPACE INCONSISTENCY PROBLEM:
# ================================
#
# Current Broken Behavior:
# - Direct access to data section variables FAILS: {{variable}} → empty
# - Namespaced access also FAILS: {{windowName.variable}} → empty
# - Client-side gets data under window namespace: window.windowName.variable (works)
# - Server-side templates CANNOT access processed data from <data> sections
#
# The UX Problem:
# - Users see `<data window="myData">{"message": "{{greeting}}}</data>`
# - They expect `{{message}}` to work in templates but it doesn't
# - This creates major confusion about data access patterns
# - Only client-side JavaScript can access the data, not server templates
#
# Expected Behavior (needs implementation):
# - Direct access should work: {{variable}} ✅ (CURRENTLY BROKEN)
# - Data from <data> section should be accessible in server templates
# - Client-side continues to use: window.windowName.variable
# - Window attributes should only affect client organization, not server access
#
# Key Issues That Need Fixing:
# 1. Server templates cannot access processed data from <data> sections
# 2. create_context_with_rue_data doesn't properly merge processed data
# 3. Major disconnect between server template context and client hydration data
RSpec.describe 'Namespace Inconsistency Problem (BROKEN - Needs Fix)' do
  let(:props) do
    {
      greeting: 'Hello World',
      user: { name: 'John Doe' },
      authenticated: true,
    }
  end

  let(:context) do
    Rhales::Context.minimal(props: props)
  end

  describe 'Core Issue: Data in templates vs client hydration inconsistency' do
    it 'demonstrates that main templates WITH data sections work (not the real issue)' do
      # This shows that main templates with <data> sections already work correctly
      template_path = File.join('spec', 'fixtures', 'templates', 'main_template_works.rue')
      template_content = <<~RUE
        <data>
        {
          "displayMessage": "Welcome: {{greeting}}",
          "userInfo": "User is {{user.name}}"
        }
        </data>

        <template>
        <div>
          <h1>{{displayMessage}}</h1>
          <p>{{userInfo}}</p>
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('main_template_works')

      # This actually WORKS for main templates without window attributes
      expect(result).to include('Welcome: Hello World')
      expect(result).to include('User is John Doe')
      expect(result).to include('<h1>Welcome: Hello World</h1>')
      expect(result).to include('<p>User is John Doe</p>')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end

    it 'demonstrates the REAL issue: partials with window attributes fail (BROKEN)' do
      # TDD: The real broken behavior is in partials when they use window attributes

      # First create a main template that includes the problematic partial
      main_template_path = File.join('spec', 'fixtures', 'templates', 'main_includes_broken_partial.rue')
      main_content = <<~RUE
        <template>
        <div class="main">
          <h1>Main Template</h1>
          {{> broken_partial_demo}}
        </div>
        </template>
      RUE

      # Then create the partial with window attribute
      partial_path = File.join('spec', 'fixtures', 'templates', 'broken_partial_demo.rue')
      partial_content = <<~RUE
        <data window="partialData">
        {
          "partialMessage": "Hello from partial: {{greeting}}",
          "partialUser": "Partial user: {{user.name}}"
        }
        </data>

        <template>
        <div class="partial">
          <p>Direct: {{partialMessage}}</p>
          <p>Namespaced: {{partialData.partialMessage}}</p>
          <span>User: {{partialUser}}</span>
        </div>
        </template>
      RUE

      File.write(main_template_path, main_content)
      File.write(partial_path, partial_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).with('main_includes_broken_partial').and_return(main_template_path)
      allow(view).to receive(:resolve_template_path).with('broken_partial_demo').and_return(partial_path)

      result = view.render_template_only('main_includes_broken_partial')

      # BROKEN: The partial's data section variables are NOT accessible
      expect(result).not_to include('Hello from partial: Hello World')
      expect(result).not_to include('Partial user: John Doe')
      expect(result).to include('<p>Direct: </p>')        # Empty
      expect(result).to include('<p>Namespaced: </p>')    # Empty
      expect(result).to include('<span>User: </span>')    # Empty

      # Clean up
      File.delete(main_template_path) if File.exist?(main_template_path)
      File.delete(partial_path) if File.exist?(partial_path)
    end

    it 'shows that main templates with window attributes actually work (not the issue)' do
      # Actually, main templates with window attributes work fine - this isn't the real issue
      template_path = File.join('spec', 'fixtures', 'templates', 'main_with_window_works.rue')
      template_content = <<~RUE
        <data window="mySpecialData">
        {
          "message": "{{greeting}}",
          "userName": "{{user.name}}"
        }
        </data>

        <template>
        <div>
          <h1>Direct access: {{message}}</h1>
          <p>Namespaced access: {{mySpecialData.message}}</p>
          <span>User: {{userName}}</span>
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('main_with_window_works')

      # Main templates with window attributes actually work fine for direct access
      expect(result).to include('<h1>Direct access: Hello World</h1>')
      expect(result).to include('<span>User: John Doe</span>')

      # Namespaced access doesn't work (and shouldn't - that's not the intended solution)
      expect(result).to include('<p>Namespaced access: </p>')

      # Client-side data is properly namespaced
      expect(result).to include('window.mySpecialData = JSON.parse(')
      expect(result).to include('"message":"Hello World"')
      expect(result).to include('"userName":"John Doe"')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Expected Behavior: What SHOULD work but currently does not' do
    it 'should allow partials with window attributes to access data section variables directly (FAILING)' do
      # TDD: This test should FAIL until we implement the fix

      # Create a main template that includes a partial
      main_template_path = File.join('spec', 'fixtures', 'templates', 'main_should_work.rue')
      main_content = <<~RUE
        <template>
        <div class="main">
          <h1>Main Template</h1>
          {{> partial_should_work}}
        </div>
        </template>
      RUE

      # Create the partial that should work after the fix
      partial_path = File.join('spec', 'fixtures', 'templates', 'partial_should_work.rue')
      partial_content = <<~RUE
        <data window="partialData">
        {
          "message": "Processed: {{greeting}}",
          "userName": "User: {{user.name}}"
        }
        </data>

        <template>
        <div class="partial">
          <p>Message: {{message}}</p>
          <p>User: {{userName}}</p>
        </div>
        </template>
      RUE

      File.write(main_template_path, main_content)
      File.write(partial_path, partial_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).with('main_should_work').and_return(main_template_path)
      allow(view).to receive(:resolve_template_path).with('partial_should_work').and_return(partial_path)

      result = view.render_template_only('main_should_work')

      # EXPECTED BEHAVIOR (should work after fix): Direct access to data section variables
      expect(result).to include('<p>Message: Processed: Hello World</p>')
      expect(result).to include('<p>User: User: John Doe</p>')

      # Window attribute should not affect template variable access
      expect(result).not_to include('<p>Message: </p>')  # Should not be empty
      expect(result).not_to include('<p>User: </p>')     # Should not be empty

      # Clean up
      File.delete(main_template_path) if File.exist?(main_template_path)
      File.delete(partial_path) if File.exist?(partial_path)
    end
  end

  describe 'Current Working Behavior: What already works' do
    it 'shows that templates without window attributes work correctly' do
      # TDD - demonstrates current behavior before fix
      # Templates WITHOUT window attributes work as expected
      template_content = <<~RUE
        <data>
        {
          "message": "{{greeting}}",
          "userName": "{{user.name}}"
        }
        </data>

        <template>
        <div>
          <h1>{{message}}</h1>
          <p>User: {{userName}}</p>
        </div>
        </template>
      RUE

      # Write test template file
      template_path = File.join('spec', 'fixtures', 'templates', 'no_window_works.rue')
      File.write(template_path, template_content)

      parser = Rhales::RueDocument.new(template_content)
      parser.parse!

      # Create context that includes rue data
      rue_data = extract_rue_data(parser)
      merged_props = props.merge(rue_data)
      context_with_rue = Rhales::Context.minimal(props: merged_props)

      engine = Rhales::TemplateEngine.new(parser.section('template'), context_with_rue)
      result = engine.render

      # This works fine without window attribute - direct access works
      expect(result).to include('<h1>Hello World</h1>')
      expect(result).to include('<p>User: John Doe</p>')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end

    it 'demonstrates the inconsistency problem with identical template content' do
      # TDD - demonstrates current behavior before fix
      # Same template content behaves differently based on window attribute presence

      # Template content is identical except for window attribute
      template_without_window = <<~RUE
        <data>
        {
          "message": "{{greeting}}",
          "userName": "{{user.name}}"
        }
        </data>

        <template>
        <div>
          <h1>{{message}}</h1>
          <p>User: {{userName}}</p>
        </div>
        </template>
      RUE

      template_with_window = <<~RUE
        <data window="myData">
        {
          "message": "{{greeting}}",
          "userName": "{{user.name}}"
        }
        </data>

        <template>
        <div>
          <h1>{{message}}</h1>
          <p>User: {{userName}}</p>
        </div>
        </template>
      RUE

      # Test without window attribute - works
      parser_without = Rhales::RueDocument.new(template_without_window)
      parser_without.parse!

      rue_data = extract_rue_data(parser_without)
      merged_props = props.merge(rue_data)
      context_with_rue = Rhales::Context.minimal(props: merged_props)

      engine_without = Rhales::TemplateEngine.new(parser_without.section('template'), context_with_rue)
      result_without = engine_without.render

      # Test with window attribute - this is where the inconsistency happens
      parser_with = Rhales::RueDocument.new(template_with_window)
      parser_with.parse!

      rue_data_with = extract_rue_data(parser_with)
      merged_props_with = props.merge(rue_data_with)
      context_with_rue_with = Rhales::Context.minimal(props: merged_props_with)

      engine_with = Rhales::TemplateEngine.new(parser_with.section('template'), context_with_rue_with)
      result_with = engine_with.render

      # Same template content produces different results - INCONSISTENT
      expect(result_without).to include('<h1>Hello World</h1>')
      expect(result_without).to include('<p>User: John Doe</p>')

      # The issue is more subtle - let me test the actual inconsistency
      # Both should work the same, but the UX suggests different access patterns
      expect(result_without).to include('<h1>Hello World</h1>')
      expect(result_without).to include('<p>User: John Doe</p>')
      expect(result_with).to include('<h1>Hello World</h1>')
      expect(result_with).to include('<p>User: John Doe</p>')

      # The real issue: Users expect window="myData" to enable {{myData.variable}} access
      # but that doesn't work, creating a UX inconsistency
    end
  end

  describe 'Server-side vs Client-side inconsistency' do
    it 'demonstrates server template vs client hydration inconsistency' do
      # TDD - demonstrates current behavior before fix
      # The same data is processed differently for server templates vs client hydration

      template_content = <<~RUE
        <data window="clientData">
        {
          "message": "{{greeting}}",
          "userName": "{{user.name}}"
        }
        </data>

        <template>
        <div class="server-rendered">
          <h1>Server: {{greeting}}</h1>
          <p>Server User: {{user.name}}</p>
        </div>
        <div class="client-data">
          <h1>Client would access: clientData.message</h1>
          <p>Client would access: clientData.userName</p>
        </div>
        </template>
      RUE

      # Write test template file
      template_path = File.join('spec', 'fixtures', 'templates', 'server_client_inconsistency.rue')
      File.write(template_path, template_content)

      # Test server-side rendering - has access to original props
      parser = Rhales::RueDocument.new(template_content)
      parser.parse!

      engine = Rhales::TemplateEngine.new(parser.section('template'), context)
      result = engine.render

      # Server-side template can access original props directly
      expect(result).to include('Server: Hello World')
      expect(result).to include('Server User: John Doe')

      # Test client-side data processing
      hydrator = Rhales::Hydrator.new(parser, context)
      client_data = hydrator.processed_data_hash

      # Client gets processed data under window namespace
      expect(client_data).to have_key('message')
      expect(client_data).to have_key('userName')
      expect(client_data['message']).to eq('Hello World')
      expect(client_data['userName']).to eq('John Doe')

      # But to access this data client-side, it would be:
      # window.clientData.message and window.clientData.userName
      #
      # This creates inconsistency:
      # - Server template: {{greeting}} and {{user.name}}
      # - Client JavaScript: clientData.message and clientData.userName
      # - Server template trying to use client data: {{clientData.message}}

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'The real issue: Templates work but miss the UX expectation' do
    it 'shows the UX inconsistency - window names suggest namespaced access' do
      # TDD - demonstrates current behavior before fix
      # The real UX issue: window="myData" suggests that template variables
      # should be accessible as {{myData.variable}}, but they're not

      template_content = <<~RUE
        <data window="userData">
        {
          "displayName": "{{user.name}}",
          "welcomeMsg": "Welcome {{greeting}}"
        }
        </data>

        <template>
        <div>
          <h1>Attempt 1: {{userData.displayName}}</h1>
          <h2>Attempt 2: {{displayName}}</h2>
          <p>Original prop: {{user.name}}</p>
        </div>
        </template>
      RUE

      # Write test template file
      template_path = File.join('spec', 'fixtures', 'templates', 'ux_inconsistency.rue')
      File.write(template_path, template_content)

      # Test with View class (full integration)
      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('ux_inconsistency')

      # The UX problem:
      # 1. {{userData.displayName}} doesn't work (namespaced access fails)
      expect(result).not_to include('userData.displayName')
      expect(result).to include('<h1>Attempt 1: </h1>')  # Empty

      # 2. {{displayName}} DOES work (View class merges rue data correctly)
      expect(result).to include('<h2>Attempt 2: John Doe</h2>')

      # 3. Only original props work
      expect(result).to include('<p>Original prop: John Doe</p>')

      # 4. But client gets the processed data correctly
      data_hash = view.data_hash('ux_inconsistency')
      expect(data_hash['userData']['displayName']).to eq('John Doe')
      expect(data_hash['userData']['welcomeMsg']).to eq('Welcome Hello World')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end

    it 'demonstrates the expected behavior that should work' do
      # TDD - demonstrates current behavior before fix
      # What SHOULD happen: window="myData" should make data accessible as {{myData.key}}
      # AND the data section values should be accessible directly as {{key}}

      template_content = <<~RUE
        <data window="profileData">
        {
          "fullName": "{{user.name}}",
          "greeting": "{{greeting}}"
        }
        </data>

        <template>
        <div>
          <h1>Direct access: {{fullName}}</h1>
          <h2>Namespaced access: {{profileData.fullName}}</h2>
          <p>Both should work and show: John Doe</p>
        </div>
        </template>
      RUE

      # Write test template file
      template_path = File.join('spec', 'fixtures', 'templates', 'expected_behavior.rue')
      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('expected_behavior')

      # Direct access works (View merges rue data), but namespaced access fails
      expect(result).to include('<h1>Direct access: John Doe</h1>')  # This works
      expect(result).to include('<h2>Namespaced access: </h2>')  # This fails - should be "John Doe"

      # The expectation is that BOTH should work:
      # {{fullName}} -> "John Doe" (direct access to data section)
      # {{profileData.fullName}} -> "John Doe" (namespaced access)

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end

    it 'demonstrates the core issue: namespaced access fails' do
      # TDD - demonstrates current behavior before fix
      # The main UX problem: window="myData" suggests {{myData.variable}} should work

      template_content = <<~RUE
        <data window="myNamespace">
        {
          "title": "{{greeting}}",
          "user": "{{user.name}}"
        }
        </data>

        <template>
        <div>
          <p>Direct: {{title}} and {{user}}</p>
          <p>Namespaced: {{myNamespace.title}} and {{myNamespace.user}}</p>
        </div>
        </template>
      RUE

      # Write test template file
      template_path = File.join('spec', 'fixtures', 'templates', 'core_issue.rue')
      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('core_issue')

      # Direct access works (due to View's rue data merging)
      expect(result).to include('Direct: Hello World and John Doe')

      # Namespaced access fails - this is the problem to fix
      expect(result).to include('Namespaced:  and ')  # Both variables are empty
      expect(result).not_to include('myNamespace.title')  # Variable not resolved
      expect(result).not_to include('myNamespace.user')   # Variable not resolved

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Comprehensive demonstration using demo template' do
    it 'shows the complete UX inconsistency with clear examples' do
      # TDD - demonstrates current behavior before fix
      # This test uses a comprehensive template that shows all aspects of the issue

      template_content = <<~RUE
        <data window="demoData">
        {
          "processedGreeting": "Processed: {{greeting}}",
          "processedUser": "User: {{user.name}}",
          "timestamp": "Generated at compile time"
        }
        </data>

        <template>
        <div class="namespace-demo">
          <h1>Window Namespace UX Test</h1>

          <!-- These should work once the fix is implemented -->
          <h2>Namespaced Access (Currently Fails):</h2>
          <p>{{demoData.processedGreeting}}</p>
          <p>{{demoData.processedUser}}</p>
          <p>{{demoData.timestamp}}</p>

          <!-- Direct access (works when View merges the data) -->
          <h2>Direct Access (Currently Works):</h2>
          <p>{{processedGreeting}}</p>
          <p>{{processedUser}}</p>
          <p>{{timestamp}}</p>

          <!-- Original props (always works) -->
          <h2>Original Props (Always Works):</h2>
          <p>{{greeting}}</p>
          <p>{{user.name}}</p>
        </div>
        </template>
      RUE

      template_path = File.join('spec', 'fixtures', 'templates', 'window_namespace_demo.rue')
      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('window_namespace_demo')

      # Get only the template part (before hydration script)
      template_only = result.split('<script').first

      # Count how many times the processed messages appear - should only be once each
      # (from direct access, NOT from namespaced access)
      processed_greeting_count = template_only.scan('Processed: Hello World').length
      processed_user_count = template_only.scan('User: John Doe').length
      timestamp_count = template_only.scan('Generated at compile time').length

      # Each should appear exactly once (from direct access only)
      expect(processed_greeting_count).to eq(1)  # Only {{processedGreeting}} works, {{demoData.processedGreeting}} fails
      expect(processed_user_count).to eq(1)      # Only {{processedUser}} works, {{demoData.processedUser}} fails
      expect(timestamp_count).to eq(1)           # Only {{timestamp}} works, {{demoData.timestamp}} fails

      # The original props appear twice (once in original section, once in generated content)
      original_greeting_count = template_only.scan('Hello World').length
      original_user_count = template_only.scan('John Doe').length
      expect(original_greeting_count).to be >= 2  # Appears in original props section + processed content
      expect(original_user_count).to be >= 2      # Appears in original props section + processed content

      # ALWAYS WORKING: Original props work
      expect(template_only).to include('Hello World')  # {{greeting}} works
      expect(template_only).to include('John Doe')     # {{user.name}} works

      # CLIENT DATA: Properly namespaced for JavaScript access
      data_hash = view.data_hash('window_namespace_demo')
      expect(data_hash['demoData']['processedGreeting']).to eq('Processed: Hello World')
      expect(data_hash['demoData']['processedUser']).to eq('User: John Doe')
      expect(data_hash['demoData']['timestamp']).to eq('Generated at compile time')

      # This demonstrates the UX inconsistency:
      # 1. Users see window="demoData" and expect {{demoData.variable}} to work
      # 2. Only {{variable}} works in templates (when View merges data)
      # 3. Client-side correctly gets window.demoData.variable
      # 4. Server-side templates should support BOTH {{variable}} AND {{demoData.variable}}

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Specific failing examples to demonstrate the issue clearly' do
    it 'shows namespaced access with window attribute fails' do
      # TDD - demonstrates current behavior before fix
      # This test uses the existing namespaced_access.rue fixture to show the failure

      # Create the fixture template that demonstrates the issue
      template_content = <<~RUE
        <data window="myData">
        {
          "message": "{{greeting}}",
          "userName": "{{user.name}}"
        }
        </data>

        <template>
        <div>
          <h1>{{myData.message}}</h1>
          <p>User: {{myData.userName}}</p>
        </div>
        </template>
      RUE

      # Write the namespaced access template
      template_path = File.join('spec', 'fixtures', 'templates', 'namespaced_access.rue')
      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('namespaced_access')

      # The current behavior: namespaced access fails
      expect(result).to include('<h1></h1>')  # Empty - {{myData.message}} doesn't work
      expect(result).to include('<p>User: </p>')  # Empty - {{myData.userName}} doesn't work

      # The variables are not resolved in the template content because namespaced access is not implemented
      # Note: The data appears in the hydration script but not in the template content
      template_only = result.split('<script').first  # Get only the template part, not the hydration script
      expect(template_only).not_to include('Hello World')
      expect(template_only).not_to include('John Doe')

      # But the data is available for client-side hydration
      data_hash = view.data_hash('namespaced_access')
      expect(data_hash['myData']['message']).to eq('Hello World')
      expect(data_hash['myData']['userName']).to eq('John Doe')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end

    it 'demonstrates that direct access would work if variables were available' do
      # TDD - demonstrates current behavior before fix
      # If we manually provide the processed data to the template, direct access works

      template_content = <<~RUE
        <data window="testData">
        {
          "processedMessage": "Processed: {{greeting}}",
          "processedUser": "User: {{user.name}}"
        }
        </data>

        <template>
        <div>
          <p>Direct access: {{processedMessage}}</p>
          <p>Direct access: {{processedUser}}</p>
        </div>
        </template>
      RUE

      parser = Rhales::RueDocument.new(template_content)
      parser.parse!

      # Get the processed data from the hydrator
      hydrator = Rhales::Hydrator.new(parser, context)
      processed_data = hydrator.processed_data_hash

      # Create a context with the processed data merged in
      merged_props = props.merge(processed_data)
      context_with_processed = Rhales::Context.minimal(props: merged_props)

      engine = Rhales::TemplateEngine.new(parser.section('template'), context_with_processed)
      result = engine.render

      # When the processed data is available in context, direct access works
      expect(result).to include('<p>Direct access: Processed: Hello World</p>')
      expect(result).to include('<p>Direct access: User: John Doe</p>')

      # This shows that the issue is the processed data not being available to templates
    end
  end

  describe 'Object expansion and namespace inconsistency' do
    it 'shows that object expansion works in main templates but fails in partials' do
      # TDD - This test demonstrates how object expansion is affected by the same
      # namespace inconsistency issue that affects regular data sections

      # Props with an object that should be expanded using {{{object}}} syntax
      object_expansion_props = {
        greeting: 'Hello from expansion',
        user: { name: 'Expansion User' },
        directly_embedded_hash_object: {
          key1_from_hash_object: 'Expanded Value 1',
          key2_from_hash_object: 'Expanded Value 2',
          key3_from_hash_object: 'Expanded Value 3'
        }
      }

      # Test main template with object expansion - SHOULD work
      main_template_path = File.join('spec', 'fixtures', 'templates', 'main_object_expansion.rue')
      main_content = <<~RUE
        <data window="expandedData">
        {{{directly_embedded_hash_object}}}
        </data>

        <template>
        <div class="main-expansion">
          <h1>{{key1_from_hash_object}}</h1>
          <p>{{key2_from_hash_object}}</p>
          <span>Namespaced: {{expandedData.key1_from_hash_object}}</span>
        </div>
        </template>
      RUE

      File.write(main_template_path, main_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: object_expansion_props)
      allow(view).to receive(:resolve_template_path).and_return(main_template_path)

      result = view.render('main_object_expansion')

      # Main template object expansion works (View class handles this correctly)
      expect(result).to include('<h1>Expanded Value 1</h1>')
      expect(result).to include('<p>Expanded Value 2</p>')

      # Namespaced access fails (expected - window attributes are for client-side)
      expect(result).to include('<span>Namespaced: </span>')

      # Client-side data is properly organized
      data_hash = view.data_hash('main_object_expansion')
      expect(data_hash['expandedData']['key1_from_hash_object']).to eq('Expanded Value 1')
      expect(data_hash['expandedData']['key2_from_hash_object']).to eq('Expanded Value 2')
      expect(data_hash['expandedData']['key3_from_hash_object']).to eq('Expanded Value 3')

      # Clean up
      File.delete(main_template_path) if File.exist?(main_template_path)
    end

    it 'demonstrates the BROKEN behavior: partials with object expansion cannot access expanded data' do
      # TDD - This test shows the exact same namespace issue affects object expansion

      object_expansion_props = {
        greeting: 'Hello from expansion',
        user: { name: 'Expansion User' },
        directly_embedded_hash_object: {
          key1_from_hash_object: 'Should appear in partial',
          key2_from_hash_object: 'Should also appear',
          key3_from_hash_object: 'Should be accessible'
        }
      }

      # Create main template that includes a partial
      main_template_path = File.join('spec', 'fixtures', 'templates', 'main_with_expansion_partial.rue')
      main_content = <<~RUE
        <data window="mainExpanded">
        {{{directly_embedded_hash_object}}}
        </data>

        <template>
        <div class="main-with-partial">
          <h1>Main: {{key1_from_hash_object}}</h1>
          {{> expansion_partial}}
        </div>
        </template>
      RUE

      # Create partial that should inherit the expanded object data
      partial_path = File.join('spec', 'fixtures', 'templates', 'expansion_partial.rue')
      partial_content = <<~RUE
        <data window="partialExpanded">
        {
          "partialData": "Data from partial"
        }
        </data>

        <template>
        <div class="expansion-partial">
          <p>Partial should access: {{key1_from_hash_object}}</p>
          <p>Partial should access: {{key2_from_hash_object}}</p>
          <p>Partial data: {{partialData}}</p>
        </div>
        </template>
      RUE

      File.write(main_template_path, main_content)
      File.write(partial_path, partial_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: object_expansion_props)
      allow(view).to receive(:resolve_template_path).with('main_with_expansion_partial').and_return(main_template_path)
      allow(view).to receive(:resolve_template_path).with('expansion_partial').and_return(partial_path)

      result = view.render_template_only('main_with_expansion_partial')

      # Main template works - can access expanded object data
      expect(result).to include('<h1>Main: Should appear in partial</h1>')

      # BROKEN: Partial cannot access parent's expanded object data
      expect(result).to include('<p>Partial should access: </p>')  # Empty - no access to key1
      expect(result).to include('<p>Partial should access: </p>')  # Empty - no access to key2

      # BROKEN: Partial cannot access its own data section
      expect(result).to include('<p>Partial data: </p>')  # Empty - no access to partialData

      # This demonstrates the same core issue:
      # 1. Main templates with object expansion work ✅
      # 2. Partials cannot inherit expanded context ❌
      # 3. Partials cannot access their own data sections ❌
      # 4. The fix needs to address partial rendering context merging

      # Clean up
      File.delete(main_template_path) if File.exist?(main_template_path)
      File.delete(partial_path) if File.exist?(partial_path)
    end
  end

  private

  # Helper method to extract rue data like View class does
  def extract_rue_data(parser)
    data_content = parser.section('data')
    return {} unless data_content

    # Process the data section as JSON and parse it
    hydrator = Rhales::Hydrator.new(parser, context)
    hydrator.processed_data_hash
  rescue JSON::ParserError, Rhales::Hydrator::JSONSerializationError
    {}
  end
end
