# spec/rhales/parser_integration_spec.rb

require 'spec_helper'

RSpec.describe 'Parser Integration' do
  describe 'RueFormatParser AST parsing' do
    it 'parses simple .rue file correctly' do
      content = <<~RUE
        <data>
        {"greeting": "{{message}}"}
        </data>

        <template>
        <h1>{{greeting}}</h1>
        </template>
      RUE

      parser = Rhales::RueFormatParser.new(content)
      parser.parse!

      expect(parser.sections.keys).to contain_exactly('data', 'template')

      data_section = parser.sections['data']
      expect(data_section.value[:tag]).to eq('data')
      expect(data_section.value[:content]).not_to be_empty
      expect(data_section.value[:content].size).to be >= 1
      data_content = data_section.value[:content].find { |node| node.type == :text }
      expect(data_content.value).to include('"greeting"')

      template_section = parser.sections['template']
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

      parser = Rhales::RueFormatParser.new(content)
      parser.parse!

      data_section = parser.sections['data']
      expect(data_section.value[:attributes]).to eq({
        'window' => 'customData',
        'schema' => 'schema.json',
      },
                                                   )
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

      parser = Rhales::RueFormatParser.new(content)
      parser.parse!

      template_section = parser.sections['template']
      expression_nodes = template_section.value[:content].select do |node|
        [:variable_expression, :if_block, :partial_expression].include?(node.type)
      end

      expect(expression_nodes.size).to be >= 4

      # Test variable expression
      var_node = expression_nodes.find { |n| n.type == :variable_expression && n.value[:name] == 'variable' }
      expect(var_node).not_to be_nil
      expect(var_node.value[:raw]).to be(false)

      # Test raw variable expression
      raw_node = expression_nodes.find { |n| n.type == :variable_expression && n.value[:name] == 'rawVariable' }
      expect(raw_node).not_to be_nil
      expect(raw_node.value[:raw]).to be(true)

      # Test block expression
      if_node = expression_nodes.find { |n| n.type == :if_block }
      expect(if_node).not_to be_nil
      expect(if_node.value[:condition]).to eq('condition')

      # Test partial expression
      partial_node = expression_nodes.find { |n| n.type == :partial_expression }
      expect(partial_node).not_to be_nil
      expect(partial_node.value[:name]).to eq('partial')
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

      parser = Rhales::RueFormatParser.new(content)

      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Duplicate sections: data')
      end
    end

    it 'validates required sections' do
      content = <<~RUE
        <logic>
        # Some logic
        </logic>
      RUE

      parser = Rhales::RueFormatParser.new(content)

      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Must have at least one of: data, template')
      end
    end
  end

  describe 'RueDocument integration with parser' do
    it 'creates RueDocument that uses RueFormatParser' do
      content = <<~RUE
        <data>
        {"greeting": "{{message}}"}
        </data>

        <template>
        <h1>{{message}}</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      document.parse!

      expect(document.sections.keys).to contain_exactly('data', 'template')
      expect(document.section('data')).to include('"greeting"')
      expect(document.section('template')).to include('<h1>')
      expect(document.template_variables).to include('message')
      expect(document.data_variables).to include('message')
    end

    it 'handles data attributes through parser' do
      content = <<~RUE
        <data window="appData">
        {"test": "value"}
        </data>

        <template>
        <div>Test</div>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      document.parse!

      expect(document.window_attribute).to eq('appData')
      expect(document.section('data')).to include('"test"')
    end

    it 'extracts partials correctly' do
      content = <<~RUE
        <data>
        {"test": "value"}
        </data>

        <template>
        {{> header}}
        <main>Content</main>
        {{> footer}}
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      document.parse!

      expect(document.partials).to contain_exactly('header', 'footer')
    end
  end

  describe 'TemplateEngine integration with parsers' do
    let(:context) do
      Rhales::Context.minimal(props: {
        greeting: 'Hello World',
        authenticated: true,
        user: { name: 'John Doe' },
      },
                             )
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

      html_context = Rhales::Context.minimal(props: {
        greeting: '<strong>Bold</strong>',
      },
                                            )

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
        expect(error.message).to match(/Template (parsing|validation) failed/)
        expect(error.message).to include('Duplicate sections')
      end
    end

    it 'now uses RueDocument internally for .rue files' do
      template = <<~RUE
        <data window="myData" schema="/api/schema.json">
        {"message": "test"}
        </data>

        <template>
        <h1>{{greeting}}</h1>
        {{> header}}
        </template>
      RUE

      engine = Rhales::TemplateEngine.new(template, context)
      result = engine.render

      # Verify metadata access methods work
      expect(engine.window_attribute).to eq('myData')
      expect(engine.schema_path).to eq('/api/schema.json')
      expect(engine.data_attributes).to eq({ 'window' => 'myData', 'schema' => '/api/schema.json' })

      # Verify analysis methods work
      expect(engine.template_variables).to include('greeting')
      expect(engine.partials).to include('header')
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
      props = {
        page_title: 'AST Test Page',
      }

      # Create authenticated context
      user    = Rhales::Adapters::AuthenticatedAuth.new(name: 'Grammar User', theme: 'dark')
      session = Rhales::Adapters::AuthenticatedSession.new(id: 'test_session')
      context = Rhales::Context.for_view(nil, session, user, 'en', **props)

      # Parse through document
      document = Rhales::RueDocument.new(rue_content)
      document.parse!

      # Verify parsing
      expect(document.window_attribute).to eq('testData')
      expect(document.data_variables).to include('page_title')

      # Render template
      template_content = document.section('template')
      engine           = Rhales::TemplateEngine.new(template_content, context)
      result           = engine.render

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

      context = Rhales::Context.minimal(props: { page_title: 'Test Title' })

      document = Rhales::RueDocument.new(content)
      document.parse!

      template_content = document.section('template')
      engine           = Rhales::TemplateEngine.new(template_content, context)
      result           = engine.render

      expect(result).to include('<h1>Test Title</h1>')
      expect(result).to include('<p>Static content</p>')
    end
  end
end
