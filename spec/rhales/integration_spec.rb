# spec/rhales/integration_spec.rb

require 'spec_helper'

# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable RSpec/MultipleDescribes
RSpec.describe 'Rhales Integration' do
  let(:props) do
    {
      greeting: 'Welcome to Rhales',
      user: { name: 'John Doe' },
    }
  end

  describe 'end-to-end template rendering' do
    it 'renders complete template with hydration' do
      # Create authenticated user and session
      user    = Rhales::Adapters::AuthenticatedAuth.new(name: 'John Doe', theme: 'dark')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'test_session', created_at: Time.now)

      # Create view with business data
      view = Rhales::View.new(nil, session, user, 'en', props: props)

      # Render the test template
      html = view.render('test_shared_context')

      # Verify template content
      expect(html).to include('<h1>Welcome to Rhales</h1>')
      expect(html).to include('<p>Hello, John Doe!</p>')
      expect(html).to include('class="theme-dark"')

      # Verify data hydration
      expect(html).to include('<script id="rsfc-data-')
      expect(html).to include('type="application/json"')
      expect(html).to include('"message":"Welcome to Rhales"')
      expect(html).to include('"authenticated":"true"')
      expect(html).to include('window.data = JSON.parse(')
    end

    it 'handles anonymous users' do
      anon_props = props.merge(user: { name: 'Guest' })
      view               = Rhales::View.new(nil, nil, nil, 'en', props: anon_props)
      html               = view.render('test_shared_context')

      expect(html).to include('<p>Please log in.</p>')
      expect(html).to include('"authenticated":"false"')
      expect(html).to include('class="theme-light"')
    end
  end

  describe 'template-only rendering' do
    it 'renders just the template section' do
      test_data = props.merge(user: { name: 'Guest' })
      view      = Rhales::View.new(nil, nil, nil, 'en', props: test_data)
      html      = view.render_template_only('test_shared_context')

      expect(html).to include('<h1>Welcome to Rhales</h1>')
      expect(html).not_to include('<script')
    end
  end

  describe 'hydration-only rendering' do
    it 'renders just the data hydration' do
      test_data = props.merge(user: { name: 'Guest' })
      view      = Rhales::View.new(nil, nil, nil, 'en', props: test_data)
      html      = view.render_hydration_only('test_shared_context')

      expect(html).to include('<script id="rsfc-data-')
      expect(html).to include('window.data = JSON.parse(')
      expect(html).not_to include('<h1>')
    end
  end

  describe 'data hash extraction' do
    it 'returns processed data as hash' do
      test_data = props.merge(user: { name: 'Guest' })
      view      = Rhales::View.new(nil, nil, nil, 'en', props: test_data)
      data      = view.data_hash('test_shared_context')

      expect(data).to be_a(Hash)
      expect(data['data']).to be_a(Hash)
      expect(data['data']['message']).to eq('Welcome to Rhales')
      expect(data['data']['user']['name']).to eq('Guest')
      expect(data['data']['authenticated']).to eq('false')
    end
  end

  describe 'inline data variables' do
    it 'renders template with inline data variables' do
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Jane Smith', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'inline_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: props)
      html = view.render('test_inline_data')

      # Verify inline data variables are accessible in template
      expect(html).to include('<span data-var="message">Welcome to Rhales</span>')
      expect(html).to include('<span data-var="user.display_name">John Doe!</span>')
      expect(html).to include('Welcome back,')

      # Verify data hydration includes inline data
      expect(html).to include('"message":"Welcome to Rhales"')
      expect(html).to include('"display_name":"John Doe"')
      expect(html).to include('"is_user_authenticated":"true"')
    end

    it 'handles dot notation with inline data variables' do
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Jane Smith', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'dot_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: props)
      html = view.render_template_only('test_inline_data')

      # Verify dot notation works for inline data (template is already rendered)
      expect(html).to include('<span data-var="user.display_name">John Doe!</span>')
      expect(html).to include('Welcome back,')
    end

    it 'properly evaluates inline data conditionals' do
      # Test with authenticated user
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Test User', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'auth_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: { greeting: 'Hello', user: { name: 'Test User' } })
      html = view.render_template_only('test_inline_data')

      expect(html).to include('Welcome back,')
      expect(html).to include('Test User!')
      expect(html).not_to include('Please log in.')

      # Test with anonymous user
      anon_view = Rhales::View.new(nil, nil, nil, 'en', props: { greeting: 'Hello', user: { name: 'Guest' } })
      anon_html = anon_view.render_template_only('test_inline_data')

      expect(anon_html).to include('Please log in.')
      expect(anon_html).not_to include('Welcome back,')
    end

    it 'returns inline data variables in data_hash' do
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Data Test', theme: 'light')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'data_test', created_at: Time.now)

      view = Rhales::View.new(nil, session, user, 'en', props: props)
      data = view.data_hash('test_inline_data')

      expect(data['data']['message']).to eq('Welcome to Rhales')
      expect(data['data']['user']).to be_a(Hash)
      expect(data['data']['user']['name']).to eq('John Doe')
      expect(data['data']['user']['display_name']).to eq('John Doe')
      expect(data['data']['is_user_authenticated']).to eq('true')
    end
  end

  describe 'convenience methods' do
    it 'renders via Rhales.render' do
      html = Rhales.render('test_shared_context', **props)

      expect(html).to include('Welcome to Rhales')
      expect(html).to include('<script')
    end

    it 'renders template via Rhales.render_template' do
      template = '{{#if authenticated}}Hello {{user.name}}{{/if}}'
      result   = Rhales.render_template(template, authenticated: true, user: { name: 'Test' })

      expect(result).to eq('Hello Test')
    end

    it 'treats string "false" as falsy in conditionals' do
      template = '{{#if flag}}true{{else}}false{{/if}}'

      # Test with boolean false
      result = Rhales.render_template(template, flag: false)
      expect(result).to eq('false')

      # Test with string "false"
      result = Rhales.render_template(template, flag: 'false')
      expect(result).to eq('false')

      # Test with string "False"
      result = Rhales.render_template(template, flag: 'False')
      expect(result).to eq('false')

      # Test with string "FALSE"
      result = Rhales.render_template(template, flag: 'FALSE')
      expect(result).to eq('false')

      # Test with other strings (should be truthy)
      result = Rhales.render_template(template, flag: 'true')
      expect(result).to eq('true')
    end
  end
end
