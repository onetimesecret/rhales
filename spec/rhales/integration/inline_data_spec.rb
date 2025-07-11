# spec/rhales/integration/inline_data_spec.rb

require 'spec_helper'

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Rhales Inline Data Integration' do
  let(:props) do
    {
      greeting: 'Welcome to Rhales',
      user: { name: 'John Doe' },
    }
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
      expect(html).to include('var dataScript = document.getElementById(')
      expect(html).to include('var targetName = dataScript.getAttribute(\'data-window\') || \'data\';')
      expect(html).to include('window[targetName] = JSON.parse(dataScript.textContent);')
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
end
