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

      # Verify inline data partial renders but shows "Please log in" because
      # is_user_authenticated is not defined in template context
      expect(html).to include('<span data-var="message"></span>')
      expect(html).to include('Please log in.')
    end

    it 'handles scope override correctly' do
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Scope Test User', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'scope_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: props)
      html = view.render_template_only('test_partials_main')

      # Verify parent template shows parent value
      expect(html).to include('Override test in parent: Parent value')

      # Verify child partial shows parent value (inline data doesn't override template context)
      expect(html).to include('Override test in child: Parent value')

      # Verify child-only variables from inline data are empty in template context
      expect(html).to include('Child only value: </p>')

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
  end
end
