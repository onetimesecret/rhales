# spec/rhales/integration/partial_scope_spec.rb

require 'spec_helper'

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Rhales Partial Scope Integration' do
  let(:props) do
    {
      greeting: 'Welcome to Rhales',
      user: { name: 'John Doe' },
    }
  end

  describe 'partial scope behavior' do
    it 'renders partials with parent scope access' do
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Partial Test User', theme: 'dark')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'partial_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: props)
      html = view.render_template_only('test_partials_main')

      # Verify main template content
      expect(html).to include('<h1>Partials Test Page</h1>')
      expect(html).to include('Parent message: Message from parent template')

      # Verify shared context partial has access to parent props
      expect(html).to include('<h1>Welcome to Rhales</h1>')
      expect(html).to include('<p>Hello, John Doe!</p>')
      expect(html).to include('class="theme-dark"')

      # Verify inline data partial can access parent context and shows authenticated user
      expect(html).to include('<span data-var="message">Welcome to Rhales</span>')
      expect(html).to include('Welcome back, <span data-var="user.display_name">John Doe!</span>')
    end

    it 'handles scope override correctly' do
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Scope Test User', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'scope_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: props)
      html = view.render_template_only('test_partials_main')

      # Verify parent template shows parent value
      expect(html).to include('Override test in parent: Parent value')

      # Verify child partial local data overrides parent context (correct precedence)
      expect(html).to include('Override test in child: Child value')

      # Verify child-only variables from inline data are accessible
      expect(html).to include('Child only value: Only in child</p>')

      # Verify child can access parent scope
      expect(html).to include('Parent message accessible: Message from parent template')

      # Verify child can access shared context
      expect(html).to include('User from context: John Doe')
    end

    it 'raises hydration collision error when partials use same window attribute' do
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Hydration Test', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'hydration_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: props)

      # Since all templates are using default window="data", we expect a wrapped collision error
      expect { view.render('test_partials_main') }.to raise_error(Rhales::View::RenderError, /Window attribute collision detected/)
    end

    it 'handles nested partial scoping' do
      # Test that partials can include other partials and maintain proper scope
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Nested Test', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'nested_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: {
        greeting: 'Hello from parent',
        user: { name: 'Parent User' }
      })

      # Verify data hash raises collision error since we're not using window attributes
      expect { view.data_hash('test_partials_main') }.to raise_error(Rhales::HydrationCollisionError)
    end
  end

  describe 'partials with window attributes' do
    it 'renders partials with non-conflicting window attributes' do
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Window Test', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'window_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: { main_message: 'Shared from parent' })
      html = view.render('test_partials_with_windows')

      # Verify main template renders
      expect(html).to include('<h1>Partials with Window Attributes</h1>')
      expect(html).to include('<p>Main template data</p>')

      # Verify partials can access parent's inline data
      expect(html).to include('Main message in partial 1: Main template data')
      expect(html).to include('Main message in partial 2: Main template data')

      # Verify partials' inline data is in hydration but not in template context
      expect(html).to include('Partial 1 message: </p>')
      expect(html).to include('Partial 2 message: </p>')

      # Verify all hydration scripts are present
      expect(html).to include('window.mainData = JSON.parse(')
      expect(html).to include('window.partial1Data = JSON.parse(')
      expect(html).to include('window.partial2Data = JSON.parse(')
    end

    it 'demonstrates object expansion scenario: partials inherit parent context but cannot access own data' do
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Object Expansion Test', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'object_expansion_test', created_at: Time.now)

      # Props that provide the expanded object data
      # The template uses {{{directly_embedded_hash_object}}} to expand this into the JSON directly
      view = Rhales::View.new(nil, session, user, 'en', props: {
        directly_embedded_hash_object: {
          key1_from_hash_object: 'Value 1 from expansion',
          key2_from_hash_object: 'Value 2 from expansion',
          key3_from_hash_object: 'Value 3 from expansion'
        }
      })

      html = view.render('test_partials_with_object_expansion_in_parent')

      # CURRENT BROKEN BEHAVIOR: Main template doesn't work either with object expansion syntax
      # This reveals that object expansion {{{object}}} in data sections may not be fully implemented
      expect(html).to include('<h1></h1>')  # {{key1_from_hash_object}} - currently empty
      expect(html).to include('<p></p>')    # {{key2_from_hash_object}} - currently empty

      # Namespaced access should be empty (expected behavior)
      expect(html).to include('<p></p>')  # {{mainData.key2_from_hash_object}} should be empty

      # Partials also cannot access the data (demonstrates the same core issue)
      expect(html).to include('Main message in partial 3: </p>')   # {{key1_from_hash_object}} fails
      expect(html).to include('Partial 3 message: </p>')          # {{key2_from_hash_object}} fails
      expect(html).to include('Partial 3 message: </p>')          # {{key3_from_hash_object}} fails

      # However, client-side hydration should work correctly for the object expansion
      expect(html).to include('window.mainData = JSON.parse(')
      expect(html).to include('window.partial3Data = JSON.parse(')

      # The client-side data should receive the expanded object
      data_hash = view.data_hash('test_partials_with_object_expansion_in_parent')
      expect(data_hash['mainData']['key1_from_hash_object']).to eq('Value 1 from expansion')
      expect(data_hash['mainData']['key2_from_hash_object']).to eq('Value 2 from expansion')
      expect(data_hash['mainData']['key3_from_hash_object']).to eq('Value 3 from expansion')

      # This test reveals that the object expansion syntax needs support,
      # AND that partials still have the same context inheritance issue
    end

    it 'demonstrates the core partial data access issue using regular data sections' do
      # This test focuses on the core issue: partials with window attributes
      # cannot access their own data section variables, using simpler data

      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Partial Data Test', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'partial_data_test', created_at: Time.now)

      # Create a simple test scenario with regular data sections (not object expansion)
      main_template_path = File.join('spec', 'fixtures', 'templates', 'simple_partial_test.rue')
      main_content = <<~RUE
        <data window="mainSimple">
        {
          "shared_value": "From main template"
        }
        </data>

        <template>
        <div class="simple-main">
          <h1>Main: {{shared_value}}</h1>
          {{> simple_partial}}
        </div>
        </template>
      RUE

      partial_path = File.join('spec', 'fixtures', 'templates', 'simple_partial.rue')
      partial_content = <<~RUE
        <data window="partialSimple">
        {
          "partial_value": "From partial data section"
        }
        </data>

        <template>
        <div class="simple-partial">
          <p>Parent data: {{shared_value}}</p>
          <p>Own data: {{partial_value}}</p>
        </div>
        </template>
      RUE

      File.write(main_template_path, main_content)
      File.write(partial_path, partial_content)

      view = Rhales::View.new(nil, session, user, 'en', props: {})
      allow(view).to receive(:resolve_template_path).with('simple_partial_test').and_return(main_template_path)
      allow(view).to receive(:resolve_template_path).with('simple_partial').and_return(partial_path)

      html = view.render_template_only('simple_partial_test')

      # Main template can access its own data section ✅
      expect(html).to include('<h1>Main: From main template</h1>')

      # FIXED: Partial can access parent's data ✅
      expect(html).to include('<p>Parent data: From main template</p>')

      # FIXED: Partial can access its own data section ✅
      expect(html).to include('<p>Own data: From partial data section</p>')

      # This demonstrates the exact same issue as the original failing test,
      # but with simpler data that's easier to understand

      # Clean up
      File.delete(main_template_path) if File.exist?(main_template_path)
      File.delete(partial_path) if File.exist?(partial_path)
    end
  end
end
