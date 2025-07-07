# spec/rhales/two_parser_architecture_spec.rb

require 'spec_helper'

RSpec.describe 'Two Parser Architecture' do
  describe 'Architecture Benefits' do
    it 'provides clean separation of concerns' do
      # HandlebarsParser focuses purely on handlebars syntax
      handlebars_content = '{{#if user}}Hello {{user.name}}{{else}}Please login{{/if}}'
      handlebars_parser = Rhales::HandlebarsParser.new(handlebars_content)
      handlebars_parser.parse!

      expect(handlebars_parser.ast.type).to eq(:template)
      expect(handlebars_parser.variables).to include('user', 'user.name')
      expect(handlebars_parser.blocks.size).to eq(1)
      expect(handlebars_parser.blocks[0].type).to eq(:if_block)

      # RueFormatParser focuses on .rue file structure validation
      rue_content = <<~RUE
        <data window="testData">
        {"message": "Hello World"}
        </data>

        <template>
        #{handlebars_content}
        </template>
      RUE

      rue_parser = Rhales::RueFormatParser.new(rue_content)
      rue_parser.parse!

      expect(rue_parser.sections.keys).to contain_exactly('data', 'template')
      expect(rue_parser.sections['data'].value[:attributes]['window']).to eq('testData')

      # Template section uses HandlebarsParser internally
      template_nodes = rue_parser.sections['template'].value[:content]
      expect(template_nodes).to be_an(Array)
      expect(template_nodes.any? { |node| node.type == :if_block }).to be(true)
    end

    it 'provides better error reporting with parser-specific messages' do
      # HandlebarsParser provides precise handlebars syntax errors
      expect do
        Rhales::HandlebarsParser.new('{{#if condition}}unclosed').parse!
      end.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.message).to include('Missing closing tag for {{#if}}')
        expect(error.line).to be > 0
        expect(error.column).to be > 0
      end

      # RueFormatParser provides structure-specific errors
      expect do
        Rhales::RueFormatParser.new('<template>Only template section</template>').parse!
      end.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Missing required sections: data')
      end
    end

    it 'eliminates dual-mode detection complexity' do
      # Simple templates are handled by HandlebarsParser
      simple_template = 'Hello {{name}}!'
      context = Rhales::Context.minimal(business_data: { greeting: 'Hello', name: 'World' })

      engine = Rhales::TemplateEngine.new(simple_template, context)
      result = engine.render
      expect(result).to eq('Hello World!')

      # .rue files are handled by RueFormatParser + HandlebarsParser
      rue_template = <<~RUE
        <data>
        {"greeting": "Hello"}
        </data>

        <template>
        {{greeting}} {{name}}!
        </template>
      RUE

      engine = Rhales::TemplateEngine.new(rue_template, context)
      result = engine.render
      expect(result).to include('Hello World!')
    end
  end

  describe 'HandlebarsParser Independence' do
    it 'parses complex handlebars templates without .rue structure' do
      complex_template = <<~TEMPLATE
        <div class="{{theme}}">
          {{#if authenticated}}
            <h1>Welcome {{user.name}}!</h1>
            {{#each notifications}}
              <div class="notification {{type}}">
                {{message}}
                {{#unless read}}
                  <span class="unread">NEW</span>
                {{/unless}}
              </div>
            {{/each}}
          {{else}}
            <p>Please {{> login_link}} to continue</p>
          {{/if}}
        </div>
      TEMPLATE

      parser = Rhales::HandlebarsParser.new(complex_template)
      parser.parse!

      expect(parser.variables).to include(
        'theme', 'authenticated', 'user.name', 'notifications',
        'type', 'message', 'read'
      )

      expect(parser.partials).to include('login_link')

      blocks = parser.blocks
      expect(blocks.size).to eq(3) # if, each, unless
      expect(blocks.map(&:type)).to contain_exactly(:if_block, :each_block, :unless_block)

      # Verify nested structure
      if_block = blocks.find { |b| b.type == :if_block }
      expect(if_block.value[:condition]).to eq('authenticated')
      expect(if_block.value[:if_content]).not_to be_empty
      expect(if_block.value[:else_content]).not_to be_empty
    end

    it 'handles handlebars specification edge cases' do
      # Whitespace handling
      template_with_whitespace = "{{  variable  }}\n{{{  raw_variable  }}}"
      parser = Rhales::HandlebarsParser.new(template_with_whitespace)
      parser.parse!

      expect(parser.variables).to contain_exactly('variable', 'raw_variable')

      # Nested blocks of same type
      nested_template = '{{#if outer}}{{#if inner}}Content{{/if}}{{/if}}'
      parser = Rhales::HandlebarsParser.new(nested_template)
      parser.parse!

      expect(parser.blocks.size).to eq(2)
      outer_block = parser.blocks[0]
      expect(outer_block.value[:condition]).to eq('outer')

      # Complex expressions in conditions
      complex_conditions = '{{#if user.permissions.admin}}Admin{{/if}}'
      parser = Rhales::HandlebarsParser.new(complex_conditions)
      parser.parse!

      expect(parser.variables).to include('user.permissions.admin')
    end
  end

  describe 'RueFormatParser Integration' do
    it 'delegates template parsing to HandlebarsParser' do
      rue_content = <<~RUE
        <data schema="user.json">
        {
          "user": {
            "name": "{{current_user.name}}",
            "role": "{{current_user.role}}"
          }
        }
        </data>

        <template>
        {{#if current_user.authenticated}}
          <h1>{{current_user.name}}</h1>
          {{#each current_user.permissions}}
            <span class="permission">{{name}}</span>
          {{/each}}
        {{else}}
          {{> login_form}}
        {{/if}}
        </template>
      RUE

      parser = Rhales::RueFormatParser.new(rue_content)
      parser.parse!

      # Verify .rue structure
      expect(parser.sections.keys).to contain_exactly('data', 'template')

      data_section = parser.sections['data']
      expect(data_section.value[:attributes]['schema']).to eq('user.json')

      # Verify template section contains proper AST nodes
      template_section = parser.sections['template']
      template_content = template_section.value[:content]

      # Should contain handlebars AST nodes, not raw text
      node_types = template_content.map(&:type)
      expect(node_types).to include(:if_block, :text)

      # Find the if block
      if_block = template_content.find { |node| node.type == :if_block }
      expect(if_block.value[:condition]).to eq('current_user.authenticated')

      # Verify nested each block
      if_content = if_block.value[:if_content]
      each_block = if_content.find { |node| node.type == :each_block }
      expect(each_block.value[:items]).to eq('current_user.permissions')

      # Verify else content with partial
      else_content = if_block.value[:else_content]
      partial_node = else_content.find { |node| node.type == :partial_expression }
      expect(partial_node.value[:name]).to eq('login_form')
    end

    it 'maintains backward compatibility with RueDocument interface' do
      rue_content = <<~RUE
        <data window="appData">
        {"message": "{{greeting}}"}
        </data>

        <template>
        <h1>{{greeting}}</h1>
        {{> footer}}
        </template>
      RUE

      document = Rhales::RueDocument.new(rue_content)
      document.parse!

      # Legacy interface still works
      expect(document.section('data')).to include('"message"')
      expect(document.section('template')).to include('<h1>{{greeting}}</h1>')
      expect(document.section('template')).to include('{{> footer}}')

      # Variable extraction works across both parsers
      expect(document.data_variables).to include('greeting')
      expect(document.template_variables).to include('greeting')
      expect(document.partials).to include('footer')

      # Data attributes still work
      expect(document.window_attribute).to eq('appData')
      expect(document.merge_strategy).to be_nil
    end

    it 'extracts merge strategy from data section attributes' do
      rue_content = <<~RUE
        <data window="appData" merge="deep" schema="test.json">
        {"message": "{{greeting}}"}
        </data>

        <template>
        <h1>{{greeting}}</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(rue_content)
      document.parse!

      expect(document.window_attribute).to eq('appData')
      expect(document.merge_strategy).to eq('deep')
      expect(document.schema_path).to eq('test.json')
    end
  end

  describe 'AST-based Rendering' do
    it 'renders templates using AST nodes instead of text manipulation' do
      template_content = <<~TEMPLATE
        <div class="{{theme_class}}">
          {{#if user.authenticated}}
            <h1>Welcome {{user.name}}!</h1>
            {{#each user.notifications}}
              <div class="notification">
                {{message}}
                {{#unless read}}
                  <span class="badge">NEW</span>
                {{/unless}}
              </div>
            {{/each}}
          {{else}}
            <p>Please log in</p>
          {{/if}}
        </div>
      TEMPLATE

      context = Rhales::Context.minimal(business_data: {
        theme_class: 'dark-theme',
        user: {
          authenticated: true,
          name: 'John Doe',
          notifications: [
            { message: 'Welcome!', read: false },
            { message: 'Update available', read: true }
          ]
        }
      })

      engine = Rhales::TemplateEngine.new(template_content, context)
      result = engine.render

      # Verify proper rendering
      expect(result).to include('class="dark-theme"')
      expect(result).to include('<h1>Welcome John Doe!</h1>')
      expect(result).to include('<div class="notification">')
      expect(result).to include('Welcome!')
      expect(result).to include('Update available')
      expect(result).to include('<span class="badge">NEW</span>') # Only for unread
      expect(result).not_to include('Please log in')
    end

    it 'handles complex nested structures efficiently' do
      complex_template = <<~TEMPLATE
        {{#each categories}}
          <div class="category">
            <h2>{{name}}</h2>
            {{#if items}}
              <ul>
                {{#each items}}
                  <li class="{{#if featured}}featured{{/if}}">
                    {{title}}
                    {{#if price}}
                      <span class="price">{{price}}</span>
                    {{/if}}
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p>No items in this category</p>
            {{/if}}
          </div>
        {{/each}}
      TEMPLATE

      context = Rhales::Context.minimal(business_data: {
        categories: [
          {
            name: 'Electronics',
            items: [
              { title: 'Laptop', price: '$999', featured: true },
              { title: 'Mouse', price: '$29', featured: false }
            ]
          },
          {
            name: 'Books',
            items: []
          }
        ]
      })

      engine = Rhales::TemplateEngine.new(complex_template, context)
      result = engine.render

      # Verify complex nested rendering
      expect(result).to include('<h2>Electronics</h2>')
      expect(result).to include('<h2>Books</h2>')
      expect(result).to include('class="featured"') # Featured item
      expect(result).to include('Laptop')
      expect(result).to include('$999')
      expect(result).to include('No items in this category') # Empty category
    end
  end

  describe 'Performance and Maintainability' do
    it 'provides better error context for debugging' do
      # Syntax error in handlebars
      bad_handlebars = '{{#if condition}}content'

      expect do
        Rhales::HandlebarsParser.new(bad_handlebars).parse!
      end.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.message).to include('Missing closing tag for {{#if}}')
        expect(error.line).to eq(1)
        expect(error.column).to be > 0
      end

      # Structure error in .rue file
      bad_rue = <<~RUE
        <data>
        {"test": "value"}
        </data>

        <template>
        <h1>Test</h1>
        </template>

        <data>
        {"duplicate": "section"}
        </data>
      RUE

      expect do
        Rhales::RueFormatParser.new(bad_rue).parse!
      end.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Duplicate sections: data')
      end
    end

    it 'enables easier testing of individual components' do
      # Test handlebars parsing independently
      handlebars_parser = Rhales::HandlebarsParser.new('{{#if test}}{{value}}{{/if}}')
      handlebars_parser.parse!

      expect(handlebars_parser.blocks.size).to eq(1)
      expect(handlebars_parser.variables).to contain_exactly('test', 'value')

      # Test .rue structure independently
      rue_parser = Rhales::RueFormatParser.new(<<~RUE)
        <data window="test">
        {"key": "value"}
        </data>

        <template>
        Simple template
        </template>
      RUE

      rue_parser.parse!
      expect(rue_parser.sections['data'].value[:attributes]['window']).to eq('test')

      # Test rendering independently
      context = Rhales::Context.minimal(business_data: { name: 'Test' })
      engine = Rhales::TemplateEngine.new('Hello {{name}}!', context)

      expect(engine.render).to eq('Hello Test!')
    end

    it 'maintains clean architecture with single responsibility' do
      # HandlebarsParser only knows about handlebars syntax
      handlebars_methods = Rhales::HandlebarsParser.instance_methods(false)
      expect(handlebars_methods).to include(:parse!, :variables, :partials, :blocks)
      expect(handlebars_methods).not_to include(:window_attribute, :schema_path)

      # RueFormatParser only knows about .rue file structure
      rue_methods = Rhales::RueFormatParser.instance_methods(false)
      expect(rue_methods).to include(:parse!, :sections)
      expect(rue_methods).not_to include(:variables, :partials, :blocks)

      # TemplateEngine only knows about rendering
      template_methods = Rhales::TemplateEngine.instance_methods(false)
      expect(template_methods).to include(:render)
      expect(template_methods).not_to include(:parse!)
    end
  end

  describe 'Specification Compliance' do
    it 'follows handlebars specification for block helpers' do
      # If/else blocks
      template = '{{#if condition}}true{{else}}false{{/if}}'
      context = Rhales::Context.minimal(business_data: { condition: true })
      result = Rhales::TemplateEngine.new(template, context).render
      expect(result).to eq('true')

      # Unless blocks
      template = '{{#unless condition}}content{{/unless}}'
      context = Rhales::Context.minimal(business_data: { condition: false })
      result = Rhales::TemplateEngine.new(template, context).render
      expect(result).to eq('content')

      # Each blocks with context
      template = '{{#each items}}{{name}}: {{value}}{{/each}}'
      context = Rhales::Context.minimal(business_data: {
        items: [
          { name: 'item1', value: 'val1' },
          { name: 'item2', value: 'val2' }
        ]
      })
      result = Rhales::TemplateEngine.new(template, context).render
      expect(result).to eq('item1: val1item2: val2')
    end

    it 'handles handlebars edge cases correctly' do
      # Empty blocks
      template = '{{#if false}}{{/if}}content'
      context = Rhales::Context.minimal(business_data: {})
      result = Rhales::TemplateEngine.new(template, context).render
      expect(result).to eq('content')

      # Whitespace preservation
      template = "before\n{{variable}}\nafter"
      context = Rhales::Context.minimal(business_data: { variable: 'middle' })
      result = Rhales::TemplateEngine.new(template, context).render
      expect(result).to eq("before\nmiddle\nafter")

      # HTML escaping
      template = '{{html_content}}'
      context = Rhales::Context.minimal(business_data: { html_content: '<script>alert("xss")</script>' })
      result = Rhales::TemplateEngine.new(template, context).render
      expect(result).to include('&lt;script&gt;')

      # Raw output
      template = '{{{html_content}}}'
      context = Rhales::Context.minimal(business_data: { html_content: '<strong>bold</strong>' })
      result = Rhales::TemplateEngine.new(template, context).render
      expect(result).to eq('<strong>bold</strong>')
    end
  end
end
