require 'spec_helper'

RSpec.describe 'Reflection Utilities Security' do
  let(:config) do
    config = Rhales::Configuration.new
    config.hydration.reflection_enabled = true
    config
  end

  let(:view) { Rhales::View.new(config) }

  describe 'XSS prevention in reflection utilities' do
    it 'prevents code injection through window attribute bracket notation' do
      # Simulate a template with data that would use reflection utilities
      template_content = <<~TEMPLATE
        {{greeting}} {{name}}!
        <data window="userData">
        {
          "greeting": "Hello",
          "name": "World"
        }
        </data>
      TEMPLATE

      result = view.render(template_content, {})

      # Should use bracket notation in reflection utilities
      expect(result).to include('window[targetName]')
      expect(result).not_to include('window.targetName')
    end

    it 'includes null checks in reflection utilities' do
      template_content = <<~TEMPLATE
        {{greeting}} {{name}}!
        <data window="userData">
        {
          "greeting": "Hello",
          "name": "World"
        }
        </data>
      TEMPLATE

      result = view.render(template_content, {})

      # Should include null checks in getDataForTarget
      expect(result).to include('return targetName ? window[targetName] : undefined')

      # Should include null checks in refreshData
      expect(result).to include('if (dataScript && targetName)')

      # Should include null checks in getAllHydrationData
      expect(result).to include('if (targetName)')
    end

    it 'prevents XSS in direct window assignments' do
      template_content = <<~TEMPLATE
        {{greeting}} {{name}}!
        <data window="user_data; alert('XSS')">
        {
          "greeting": "Hello",
          "name": "World"
        }
        </data>
      TEMPLATE

      result = view.render(template_content, {})

      # Should use bracket notation, not dot notation
      expect(result).to include("window['user_data; alert(\\'XSS\\')']")
      expect(result).not_to include("window.user_data; alert('XSS')")
    end
  end

  describe 'HTML attribute escaping' do
    it 'escapes malicious nonce values' do
      template_content = <<~TEMPLATE
        {{greeting}} {{name}}!
        <data window="userData">
        {
          "greeting": "Hello",
          "name": "World"
        }
        </data>
      TEMPLATE

      # Mock a malicious nonce
      allow(config).to receive(:csp_nonce).and_return('test" onload="alert(\'XSS\')')

      result = view.render(template_content, {})

      # Should escape HTML special characters in nonce
      expect(result).to include('nonce="test&quot; onload=&quot;alert(&#x27;XSS&#x27;)')
      expect(result).not_to include('nonce="test" onload="alert(\'XSS\')')
    end
  end

  describe 'input validation' do
    it 'handles empty window attributes safely' do
      template_content = <<~TEMPLATE
        {{greeting}} {{name}}!
        <data window="">
        {
          "greeting": "Hello",
          "name": "World"
        }
        </data>
      TEMPLATE

      expect {
        view.render(template_content, {})
      }.not_to raise_error
    end

    it 'handles missing window attributes safely' do
      template_content = <<~TEMPLATE
        {{greeting}} {{name}}!
        <data>
        {
          "greeting": "Hello",
          "name": "World"
        }
        </data>
      TEMPLATE

      expect {
        view.render(template_content, {})
      }.not_to raise_error
    end
  end
end
