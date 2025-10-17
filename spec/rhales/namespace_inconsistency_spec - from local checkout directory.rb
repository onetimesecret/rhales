# spec/rhales/namespace_inconsistency_spec.rb

require 'spec_helper'

# TDD - demonstrates current behavior before fix
#
# NAMESPACE INCONSISTENCY PROBLEM SUMMARY:
# ========================================
#
# Current Behavior:
# - Direct access to data section variables works: {{variable}}
# - Namespaced access does NOT work: {{windowName.variable}}
# - Client-side gets data under window namespace: window.windowName.variable
#
# The UX Problem:
# - Users see `<data window="myData">` and expect `{{myData.variable}}` to work
# - But only `{{variable}}` works in server templates
# - This creates confusion about data access patterns
#
# Expected Behavior (to be implemented):
# - Direct access should work: {{variable}}
# - Namespaced access should work: {{windowName.variable}}
# - Both should access the same processed data from the <data> section
# - Client-side continues to use: window.windowName.variable
#
# Key Issues Demonstrated:
# 1. Namespaced template access fails ({{myData.variable}} doesn't work)
# 2. Window attribute name doesn't provide expected namespaced access
# 3. UX inconsistency between server template syntax and client data access
RSpec.describe 'Namespace Inconsistency Problem' do
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
    it 'demonstrates that data section values are not accessible in server templates' do
      # TDD - demonstrates current behavior before fix
      # The issue: <data> section defines processed values, but server templates
      # can't access them - they only get the original props context
      template_content = <<~RUE
        <data window="appData">
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

      parser = Rhales::RueDocument.new(template_content)
      parser.parse!

      # Using just the original context (what templates currently get)
      engine = Rhales::TemplateEngine.new(parser.section('template'), context)
      result = engine.render

      # The processed data values are NOT available in the template
      expect(result).not_to include('Welcome: Hello World')
      expect(result).not_to include('User is John Doe')
      expect(result).to include('<h1></h1>')  # Empty because {{displayMessage}} not found
      expect(result).to include('<p></p>')  # Empty because {{userInfo}} not found

      # But the hydration data contains the processed values
      hydrator = Rhales::Hydrator.new(parser, context)
      client_data = hydrator.processed_data_hash

      expect(client_data['displayMessage']).to eq('Welcome: Hello World')
      expect(client_data['userInfo']).to eq('User is John Doe')
    end

    it 'demonstrates the window attribute creates a namespace barrier' do
      # TDD - demonstrates current behavior before fix
      # The window attribute should not prevent template access to the data values
      template_content = <<~RUE
        <data window="appData">
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

      parser = Rhales::RueDocument.new(template_content)
      parser.parse!

      # Current issue: Template engine doesn't have access to processed data section values
      engine = Rhales::TemplateEngine.new(parser.section('template'), context)
      result = engine.render

      # These processed values from the data section are not accessible in templates
      expect(result).not_to include('Hello World')
      expect(result).not_to include('John Doe')
      expect(result).to include('<h1></h1>')  # Empty
      expect(result).to include('<p>User: </p>')  # Empty

      # But the client will receive this data under the window namespace
      hydrator = Rhales::Hydrator.new(parser, context)
      client_data = hydrator.processed_data_hash

      expect(client_data['message']).to eq('Hello World')
      expect(client_data['userName']).to eq('John Doe')

      # Client-side JavaScript would access as: window.appData.message
      # But server-side template cannot access these values at all
    end
  end

  describe 'Expected Behavior: Direct variable access should work' do
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
      view = Rhales::View.new(nil, 'en', props: props)
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

      view = Rhales::View.new(nil, 'en', props: props)
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

      view = Rhales::View.new(nil, 'en', props: props)
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
