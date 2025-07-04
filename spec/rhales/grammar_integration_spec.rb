# spec/rhales/grammar_integration_spec.rb

require 'spec_helper'

RSpec.describe 'Grammar Integration' do
  describe 'RueGrammar AST parsing' do
    it 'parses simple .rue file correctly' do
      content = <<~RUE
        <data>
        {
          "message": "{{greeting}}"
        }
        </data>

        <template>
        <h1>{{greeting}}</h1>
        </template>
      RUE

      grammar = Rhales::RueGrammar.new(content)
      grammar.parse!

      expect(grammar.sections.keys).to contain_exactly('data', 'template')

      data_section = grammar.sections['data']
      expect(data_section.value[:tag]).to eq('data')
      expect(data_section.value[:content].size).to be >= 1
      data_content = data_section.value[:content].find { |node| node.type == :text }
      expect(data_content.value).to include('"message"')

      template_section = grammar.sections['template']
      expect(template_section.value[:tag]).to eq('template')
      expect(template_section.value[:content].size).to be >= 2
    end

    it 'handles attributes in section tags' do
      content = <<~RUE
        <data window="customData" schema="schema.json">
        {"test": "value"}
        </data>

        <template>
        <div>Test</div>
        </template>
      RUE

      grammar = Rhales::RueGrammar.new(content)
      grammar.parse!

      data_section = grammar.sections['data']
      expect(data_section.value[:attributes]).to eq({
        'window' => 'customData',
        'schema' => 'schema.json'
      })
    end

    it 'parses handlebars expressions correctly' do
      content = <<~RUE
        <data>
        {"test": "value"}
        </data>

        <template>
        {{variable}}
        {{{rawVariable}}}
        {{#if condition}}
        Content
        {{/if}}
        {{> partial}}
        </template>
      RUE

      grammar = Rhales::RueGrammar.new(content)
      grammar.parse!

      template_section = grammar.sections['template']
      handlebars_nodes = template_section.value[:content].select do |node|
        node.type == :handlebars_expression
      end

      expect(handlebars_nodes.size).to be >= 4

      # Test variable expression
      var_node = handlebars_nodes.find { |n| n.value[:content] == 'variable' }
      expect(var_node).not_to be_nil
      expect(var_node.value[:raw]).to be(false)

      # Test raw variable expression
      raw_node = handlebars_nodes.find { |n| n.value[:content] == 'rawVariable' }
      expect(raw_node).not_to be_nil
      expect(raw_node.value[:raw]).to be(true)

      # Test block expression
      if_node = handlebars_nodes.find { |n| n.value[:content] == '#if condition' }
      expect(if_node).not_to be_nil

      # Test partial expression
      partial_node = handlebars_nodes.find { |n| n.value[:content] == '> partial' }
      expect(partial_node).not_to be_nil
    end

    it 'provides accurate error reporting' do
      content = <<~RUE
        <data>
        {"test": "value"}
        </data>

        <template>
        <h1>{{greeting}}</h1>
        </template>

        <data>
        {"duplicate": "section"}
        </data>
      RUE

      grammar = Rhales::RueGrammar.new(content)

      expect { grammar.parse! }.to raise_error(Rhales::RueGrammar::ParseError) do |error|
        expect(error.message).to include('Duplicate sections: data')
      end
    end

    it 'validates required sections' do
      content = <<~RUE
        <logic>
        # Some logic
        </logic>
      RUE

      grammar = Rhales::RueGrammar.new(content)

      expect { grammar.parse! }.to raise_error(Rhales::RueGrammar::ParseError) do |error|
        expect(error.message).to include('Missing required sections: data, template')
      end
    end
  end

  describe 'Parser integration with grammar' do
    it 'creates Parser that uses RueGrammar' do
      content = <<~RUE
        <data>
        {"greeting": "{{message}}"}
        </data>

        <template>
        <h1>{{message}}</h1>
        </template>
      RUE

      parser = Rhales::Parser.new(content)
      parser.parse!

      expect(parser.sections.keys).to contain_exactly('data', 'template')
      expect(parser.section('data')).to include('"greeting"')
      expect(parser.section('template')).to include('<h1>')
      expect(parser.template_variables).to include('message')
      expect(parser.data_variables).to include('message')
    end

    it 'handles data attributes through grammar' do
      content = <<~RUE
        <data window="appData">
        {"test": "value"}
        </data>

        <template>
        <div>Test</div>
        </template>
      RUE

      parser = Rhales::Parser.new(content)
      parser.parse!

      expect(parser.window_attribute).to eq('appData')
      expect(parser.data_attributes).to eq({ 'window' => 'appData' })
    end

    it 'extracts partials correctly' do
      content = <<~RUE
        <data>
        {"test": "value"}
        </data>

        <template>
        <div>
          {{> header}}
          <main>Content</main>
          {{> footer}}
        </div>
        </template>
      RUE

      parser = Rhales::Parser.new(content)
      parser.parse!

      expect(parser.partials).to contain_exactly('header', 'footer')
    end
  end

  describe 'TemplateEngine integration with grammar' do
    let(:context) do
      Rhales::Context.minimal(business_data: {
        greeting: 'Hello World',
        authenticated: true,
        user: { name: 'John Doe' }
      })
    end

    it 'renders simple templates without .rue structure' do
      template = '<h1>{{greeting}}</h1>'

      engine = Rhales::TemplateEngine.new(template, context)
      result = engine.render

      expect(result).to eq('<h1>Hello World</h1>')
    end

    it 'renders .rue templates using AST parsing' do
      template = <<~RUE
        <data>
        {"message": "{{greeting}}"}
        </data>

        <template>
        <h1>{{greeting}}</h1>
        <p>Simple template without blocks</p>
        </template>
      RUE

      engine = Rhales::TemplateEngine.new(template, context)
      result = engine.render

      expect(result).to include('<h1>Hello World</h1>')
      expect(result).to include('<p>Simple template without blocks</p>')
    end

    it 'handles raw variables correctly' do
      template = <<~RUE
        <data>
        {"greeting": "{{greeting}}"}
        </data>

        <template>
        <div>{{greeting}}</div>
        <div>{{{greeting}}}</div>
        </template>
      RUE

      html_context = Rhales::Context.minimal(business_data: {
        greeting: '<strong>Bold</strong>'
      })

      engine = Rhales::TemplateEngine.new(template, html_context)
      result = engine.render

      # Test both escaped and raw outputs
      expect(result).to include('<div>&lt;strong&gt;Bold&lt;/strong&gt;</div>')
      expect(result).to include('<div><strong>Bold</strong></div>')
    end

    it 'processes partials when resolver is provided' do
      template = '{{> test_partial}}'

      partial_resolver = proc do |name|
        case name
        when 'test_partial'
          '<p>This is a partial</p>'
        else
          nil
        end
      end

      engine = Rhales::TemplateEngine.new(template, context, partial_resolver: partial_resolver)
      result = engine.render

      expect(result).to eq('<p>This is a partial</p>')
    end

    it 'provides helpful error messages for parsing failures' do
      invalid_template = <<~RUE
        <data>
        {"test": "value"}
        </data>

        <template>
        <h1>{{greeting}}</h1>
        </template>

        <data>
        {"duplicate": "error"}
        </data>
      RUE

      engine = Rhales::TemplateEngine.new(invalid_template, context)

      expect { engine.render }.to raise_error(Rhales::TemplateEngine::RenderError) do |error|
        expect(error.message).to include('Template parsing failed')
        expect(error.message).to include('Duplicate sections')
      end
    end
  end

  describe 'End-to-end AST workflow' do
    it 'processes complete .rue file through the pipeline' do
      rue_content = <<~RUE
        <data window="testData">
        {
          "title": "{{page_title}}"
        }
        </data>

        <template>
        <div class="{{theme_class}}">
          <h1>{{page_title}}</h1>
          <p>Simple template test</p>
        </div>
        </template>
      RUE

      # Create business data
      business_data = {
        page_title: 'AST Test Page'
      }

      # Create authenticated context
      user = Rhales::Adapters::AuthenticatedAuth.new(name: 'Grammar User', theme: 'dark')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'test_session')
      context = Rhales::Context.for_view(nil, session, user, 'en', **business_data)

      # Parse through grammar
      parser = Rhales::Parser.new(rue_content)
      parser.parse!

      # Verify parsing
      expect(parser.window_attribute).to eq('testData')
      expect(parser.data_variables).to include('page_title')

      # Render template
      template_content = parser.section('template')
      engine = Rhales::TemplateEngine.new(template_content, context)
      result = engine.render

      # Verify rendering
      expect(result).to include('<h1>AST Test Page</h1>')
      expect(result).to include('class="theme-dark"')
      expect(result).to include('<p>Simple template test</p>')
    end

    it 'handles simple variable substitution' do
      content = <<~RUE
        <data>
        {
          "title": "{{page_title}}"
        }
        </data>

        <template>
        <h1>{{page_title}}</h1>
        <p>Static content</p>
        </template>
      RUE

      context = Rhales::Context.minimal(business_data: { page_title: 'Test Title' })

      parser = Rhales::Parser.new(content)
      parser.parse!

      template_content = parser.section('template')
      engine = Rhales::TemplateEngine.new(template_content, context)
      result = engine.render

      expect(result).to include('<h1>Test Title</h1>')
      expect(result).to include('<p>Static content</p>')
    end
  end
end
