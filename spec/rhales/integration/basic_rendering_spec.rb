# spec/rhales/integration/basic_rendering_spec.rb

require 'spec_helper'

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Rhales Basic Rendering Integration' do
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
      expect(html).to include('var dataScript = document.getElementById(')
      expect(html).to include('var targetName = dataScript.getAttribute(\'data-window\') || \'data\';')
      expect(html).to include('window[targetName] = JSON.parse(dataScript.textContent);')
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
      expect(html).to include('var dataScript = document.getElementById(')
      expect(html).to include('var targetName = dataScript.getAttribute(\'data-window\') || \'data\';')
      expect(html).to include('window[targetName] = JSON.parse(dataScript.textContent);')
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

  describe 'security validations' do
    it 'uses secure bracket notation in reflection utilities' do
      # Test that reflection utilities use secure window[targetName] pattern
      test_data = props.merge(user: { name: 'SecurityTest' })
      view      = Rhales::View.new(nil, nil, nil, 'en', props: test_data)
      html      = view.render_hydration_only('test_shared_context')

      # Verify secure patterns are used
      expect(html).to include('window[targetName] = JSON.parse(dataScript.textContent);')
      expect(html).to include('return targetName ? window[targetName] : undefined')
      expect(html).to include('if (dataScript && targetName)')
      expect(html).to include('if (targetName)')
      
      # Verify insecure patterns are NOT used
      expect(html).not_to include('window.targetName')
    end

    it 'escapes nonce values properly' do
      # Test with potentially malicious nonce using the LinkBasedInjectionDetector directly
      # since the nonce comes from context, not configuration
      malicious_nonce = 'test" onload="alert(\'XSS\')'
      
      hydration_config = Rhales::HydrationConfiguration.new
      detector = Rhales::LinkBasedInjectionDetector.new(hydration_config)
      
      result = detector.generate_for_strategy(:preload, 'test_template', 'userData', malicious_nonce)
      
      # Should escape the nonce properly
      expect(result).to include('nonce="test&quot; onload=&quot;alert(&#39;XSS&#39;)')
      expect(result).not_to include('nonce="test" onload="alert(\'XSS\')')
    end
  end
end
