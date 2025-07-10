# spec/rhales/desired_namespace_behavior_spec.rb

require 'spec_helper'

# TDD - defines expected behavior after fix
#
# DESIRED NAMESPACE BEHAVIOR AFTER FIX:
# =====================================
#
# After the fix, templates should support ONLY direct access patterns:
# - Direct access: {{variable}} - accesses processed data from <data> section
# - NO namespaced access: {{windowName.variable}} is NOT supported
#
# Direct access should:
# - Access the processed data from the <data> section
# - Work consistently for simple variables and nested objects
# - Maintain compatibility with existing direct access patterns
# - Window attributes only affect client-side data organization, not template syntax
#
# Key principles after fix:
# - window="myData" ONLY affects client-side data organization
# - {{variable}} is the ONLY supported template syntax
# - Server-side templates use direct access only
# - Client-side hydration is organized by window attribute but templates are unchanged
RSpec.describe 'Desired Namespace Behavior After Fix' do
  let(:props) do
    {
      greeting: 'Hello World',
      user: { name: 'John Doe', role: 'admin' },
      authenticated: true,
      items: [
        { name: 'Item 1', active: true },
        { name: 'Item 2', active: false }
      ]
    }
  end

  let(:context) do
    Rhales::Context.minimal(props: props)
  end

  describe 'Basic direct access pattern' do
    it 'should support only direct access to simple variables' do
      # TDD - defines expected behavior after fix
      # Only {{message}} should work, not {{myData.message}}

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_basic_dual_access.rue')
      template_content = <<~RUE
        <data window="myData">
        {
          "message": "{{greeting}}",
          "userName": "{{user.name}}"
        }
        </data>

        <template>
        <div>
          <h1>Direct: {{message}}</h1>
          <p>Direct user: {{userName}}</p>
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_basic_dual_access')

      # EXPECTED BEHAVIOR: Only direct access should work regardless of window attribute
      expect(result).to include('<h1>Direct: Hello World</h1>')
      expect(result).to include('<p>Direct user: John Doe</p>')

      # Client-side data should be properly namespaced for hydration
      data_hash = view.data_hash('desired_basic_dual_access')
      expect(data_hash['myData']['message']).to eq('Hello World')
      expect(data_hash['myData']['userName']).to eq('John Doe')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end

    it 'should support nested object access with direct patterns only' do
      # TDD - defines expected behavior after fix
      # Complex nested data should work with direct access only

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_nested_object_access.rue')
      template_content = <<~RUE
        <data window="appData">
        {
          "userProfile": {
            "displayName": "{{user.name}}",
            "role": "{{user.role}}",
            "isAuthenticated": {{authenticated}}
          },
          "greeting": "{{greeting}}"
        }
        </data>

        <template>
        <div>
          <h1>Direct nested: {{userProfile.displayName}}</h1>
          <p>Direct role: {{userProfile.role}}</p>
          <p>Direct boolean: {{userProfile.isAuthenticated}}</p>
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_nested_object_access')

      # EXPECTED BEHAVIOR: Only direct access patterns should work for nested objects
      expect(result).to include('<h1>Direct nested: John Doe</h1>')
      expect(result).to include('<p>Direct role: admin</p>')
      expect(result).to include('<p>Direct boolean: true</p>')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Array access pattern' do
    it 'should support only direct access to arrays' do
      # TDD - defines expected behavior after fix
      # Array access should work with direct patterns only

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_array_access.rue')
      template_content = <<~RUE
        <data window="listData">
        {
          "itemCount": 2,
          "firstItemName": "{{user.name}}"
        }
        </data>

        <template>
        <div>
          <h1>Count direct: {{itemCount}}</h1>
          <p>Direct item: {{firstItemName}}</p>
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_array_access')

      # EXPECTED BEHAVIOR: Only direct access patterns should work for arrays
      expect(result).to include('<h1>Count direct: 2</h1>')
      expect(result).to include('<p>Direct item: John Doe</p>')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Backward compatibility' do
    it 'should maintain existing direct access behavior without window attribute' do
      # TDD - defines expected behavior after fix
      # Templates without window attributes should continue working exactly as before

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_backward_compatibility.rue')
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

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_backward_compatibility')

      # EXPECTED BEHAVIOR: Should work exactly as it does currently
      expect(result).to include('<h1>Hello World</h1>')
      expect(result).to include('<p>User: John Doe</p>')

      # No window namespace in client data (current behavior should be preserved)
      data_hash = view.data_hash('desired_backward_compatibility')
      expect(data_hash).to have_key('data')
      expect(data_hash['data']).to have_key('message')
      expect(data_hash['data']).to have_key('userName')
      expect(data_hash['data']['message']).to eq('Hello World')
      expect(data_hash['data']['userName']).to eq('John Doe')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end

    it 'should allow mixing direct access with original props' do
      # TDD - defines expected behavior after fix
      # Original props should remain accessible alongside processed data via direct access only

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_mixed_access.rue')
      template_content = <<~RUE
        <data window="processedData">
        {
          "processedGreeting": "Processed: {{greeting}}",
          "processedUser": "User: {{user.name}}"
        }
        </data>

        <template>
        <div>
          <h1>Original: {{greeting}}</h1>
          <h2>Processed direct: {{processedGreeting}}</h2>
          <p>Original nested: {{user.name}}</p>
          <p>Processed direct: {{processedUser}}</p>
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_mixed_access')

      # EXPECTED BEHAVIOR: Only direct access patterns should work
      expect(result).to include('<h1>Original: Hello World</h1>')
      expect(result).to include('<h2>Processed direct: Processed: Hello World</h2>')
      expect(result).to include('<p>Original nested: John Doe</p>')
      expect(result).to include('<p>Processed direct: User: John Doe</p>')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Edge cases and error handling' do
    it 'should handle non-existent variables gracefully' do
      # TDD - defines expected behavior after fix
      # Non-existent variables should render as empty, not cause errors

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_missing_variables.rue')
      template_content = <<~RUE
        <data window="testData">
        {
          "existing": "{{greeting}}"
        }
        </data>

        <template>
        <div>
          <p>Existing direct: {{existing}}</p>
          <p>Missing direct: {{missing}}</p>
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_missing_variables')

      # EXPECTED BEHAVIOR: Missing variables should render as empty, not cause errors
      expect(result).to include('<p>Existing direct: Hello World</p>')
      expect(result).to include('<p>Missing direct: </p>')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end

    it 'should handle deeply nested direct access' do
      # TDD - defines expected behavior after fix
      # Deep nesting should work with direct access only

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_deep_nesting.rue')
      template_content = <<~RUE
        <data window="deepData">
        {
          "level1": {
            "level2": {
              "level3": {
                "message": "{{greeting}}",
                "user": "{{user.name}}"
              }
            }
          }
        }
        </data>

        <template>
        <div>
          <p>Direct deep: {{level1.level2.level3.message}}</p>
          <p>Direct deep user: {{level1.level2.level3.user}}</p>
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_deep_nesting')

      # EXPECTED BEHAVIOR: Deep nesting should work with direct patterns only
      expect(result).to include('<p>Direct deep: Hello World</p>')
      expect(result).to include('<p>Direct deep user: John Doe</p>')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Conditional rendering with direct access' do
    it 'should support conditional blocks with direct access patterns only' do
      # TDD - defines expected behavior after fix
      # Conditional rendering should work with direct variables only

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_conditional_access.rue')
      template_content = <<~RUE
        <data window="conditionData">
        {
          "isAuthenticated": {{authenticated}},
          "userRole": "{{user.role}}",
          "showAdmin": {{authenticated}}
        }
        </data>

        <template>
        <div>
          {{#if isAuthenticated}}
          <p>Direct condition: User is authenticated</p>
          {{/if}}

          {{#if showAdmin}}
          <p>Admin access: {{userRole}}</p>
          {{/if}}
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_conditional_access')

      # EXPECTED BEHAVIOR: Only direct conditional patterns should work
      expect(result).to include('<p>Direct condition: User is authenticated</p>')
      expect(result).to include('<p>Admin access: admin</p>')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Server-side and client-side consistency' do
    it 'should provide consistent data access pattern between server and client' do
      # TDD - defines expected behavior after fix
      # Server templates use direct access, client hydration uses window namespace

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_server_client_consistency.rue')
      template_content = <<~RUE
        <data window="sharedData">
        {
          "serverMessage": "{{greeting}}",
          "clientMessage": "{{greeting}}",
          "userInfo": {
            "name": "{{user.name}}",
            "role": "{{user.role}}"
          }
        }
        </data>

        <template>
        <div>
          <h1>Server can access: {{serverMessage}}</h1>
          <p>Server user: {{userInfo.name}}</p>
          <script>
            // Client will access: window.sharedData.clientMessage
            // Client will access: window.sharedData.userInfo.name
            console.log('Client access uses window namespace, server templates use direct access');
          </script>
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_server_client_consistency')

      # EXPECTED BEHAVIOR: Server-side template should use direct access only
      expect(result).to include('<h1>Server can access: Hello World</h1>')
      expect(result).to include('<p>Server user: John Doe</p>')

      # Client-side data should be organized by window namespace
      data_hash = view.data_hash('desired_server_client_consistency')
      expect(data_hash['sharedData']['serverMessage']).to eq('Hello World')
      expect(data_hash['sharedData']['clientMessage']).to eq('Hello World')
      expect(data_hash['sharedData']['userInfo']['name']).to eq('John Doe')
      expect(data_hash['sharedData']['userInfo']['role']).to eq('admin')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Window namespace isolation' do
    it 'should handle window attributes for client-side organization only' do
      # TDD - defines expected behavior after fix
      # Window attributes should not affect server-side template syntax

      # Note: Current Rhales supports single data section per template
      # This test verifies that window attributes only affect client-side data organization
      # Templates should use direct access regardless of window attribute

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_single_namespace_isolation.rue')
      template_content = <<~RUE
        <data window="isolatedData">
        {
          "message": "{{greeting}}",
          "userInfo": {
            "name": "{{user.name}}",
            "authenticated": {{authenticated}}
          }
        }
        </data>

        <template>
        <div>
          <h1>Direct: {{message}}</h1>
          <p>Nested direct: {{userInfo.name}}</p>
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_single_namespace_isolation')

      # EXPECTED BEHAVIOR: Only direct access should work regardless of window attribute
      expect(result).to include('<h1>Direct: Hello World</h1>')
      expect(result).to include('<p>Nested direct: John Doe</p>')

      # Data should be properly isolated under the namespace for client-side access
      data_hash = view.data_hash('desired_single_namespace_isolation')
      expect(data_hash['isolatedData']).to be_a(Hash)
      expect(data_hash['isolatedData']['message']).to eq('Hello World')
      expect(data_hash['isolatedData']['userInfo']['name']).to eq('John Doe')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end

  describe 'Complex real-world scenario' do
    it 'should handle a comprehensive real-world template with direct access only' do
      # TDD - defines expected behavior after fix
      # A realistic template using direct access patterns exclusively

      template_path = File.join('spec', 'fixtures', 'templates', 'desired_comprehensive_scenario.rue')
      template_content = <<~RUE
        <data window="pageData">
        {
          "pageTitle": "Welcome {{user.name}}",
          "navigation": {
            "showAdminLink": {{authenticated}},
            "userRole": "{{user.role}}"
          },
          "content": {
            "welcomeMessage": "{{greeting}} from your dashboard",
            "itemCount": 2
          },
          "metadata": {
            "timestamp": "2024-01-01",
            "version": "1.0"
          }
        }
        </data>

        <template>
        <div class="page">
          <header>
            <h1>{{pageTitle}}</h1>
            {{#if navigation.showAdminLink}}
            <nav>Admin Panel ({{navigation.userRole}})</nav>
            {{/if}}
          </header>

          <main>
            <p>{{content.welcomeMessage}}</p>
            <p>Items: {{content.itemCount}}</p>
          </main>

          <footer>
            <small>Version: {{metadata.version}} | {{metadata.timestamp}}</small>
          </footer>
          <!-- Window attributes should not affect template syntax -->
          <!-- Templates should always use direct access regardless of window attribute -->
        </div>
        </template>
      RUE

      File.write(template_path, template_content)

      view = Rhales::View.new(nil, nil, nil, 'en', props: props)
      allow(view).to receive(:resolve_template_path).and_return(template_path)

      result = view.render('desired_comprehensive_scenario')

      # EXPECTED BEHAVIOR: Only direct access patterns should work in a complex scenario
      expect(result).to include('<h1>Welcome John Doe</h1>')
      expect(result).to include('<nav>Admin Panel (admin)</nav>')
      expect(result).to include('<p>Hello World from your dashboard</p>')
      expect(result).to include('<p>Items: 2</p>')
      expect(result).to include('Version: 1.0 | 2024-01-01')

      # Client data should be properly structured for hydration
      data_hash = view.data_hash('desired_comprehensive_scenario')
      expect(data_hash['pageData']['pageTitle']).to eq('Welcome John Doe')
      expect(data_hash['pageData']['navigation']['showAdminLink']).to be(true)
      expect(data_hash['pageData']['content']['welcomeMessage']).to eq('Hello World from your dashboard')

      # Clean up
      File.delete(template_path) if File.exist?(template_path)
    end
  end
end
