# spec/rhales/grammars/handlebars_spec.rb

require 'spec_helper'

RSpec.describe Rhales::HandlebarsGrammar do
  describe '#parse!' do
    it 'parses plain text' do
      grammar = described_class.new('Hello world')
      grammar.parse!

      expect(grammar.ast.type).to eq(:template)
      expect(grammar.ast.children.size).to eq(1)
      expect(grammar.ast.children[0].type).to eq(:text)
      expect(grammar.ast.children[0].value).to eq('Hello world')
    end

    it 'parses simple variable expression' do
      grammar = described_class.new('Hello {{name}}')
      grammar.parse!

      expect(grammar.ast.children.size).to eq(2)
      expect(grammar.ast.children[0].type).to eq(:text)
      expect(grammar.ast.children[0].value).to eq('Hello ')
      expect(grammar.ast.children[1].type).to eq(:variable_expression)
      expect(grammar.ast.children[1].value[:name]).to eq('name')
      expect(grammar.ast.children[1].value[:raw]).to be(false)
    end

    it 'parses raw variable expression' do
      grammar = described_class.new('Content: {{{html}}}')
      grammar.parse!

      expect(grammar.ast.children.size).to eq(2)
      expect(grammar.ast.children[0].type).to eq(:text)
      expect(grammar.ast.children[0].value).to eq('Content: ')
      expect(grammar.ast.children[1].type).to eq(:variable_expression)
      expect(grammar.ast.children[1].value[:name]).to eq('html')
      expect(grammar.ast.children[1].value[:raw]).to be(true)
    end

    it 'parses partial expression' do
      grammar = described_class.new('{{> header}}')
      grammar.parse!

      expect(grammar.ast.children.size).to eq(1)
      expect(grammar.ast.children[0].type).to eq(:partial_expression)
      expect(grammar.ast.children[0].value[:name]).to eq('header')
    end

    it 'parses if block without else' do
      template = '{{#if condition}}True content{{/if}}'
      grammar = described_class.new(template)
      grammar.parse!

      expect(grammar.ast.children.size).to eq(1)

      if_block = grammar.ast.children[0]
      expect(if_block.type).to eq(:if_block)
      expect(if_block.value[:condition]).to eq('condition')
      expect(if_block.value[:if_content].size).to eq(1)
      expect(if_block.value[:if_content][0].type).to eq(:text)
      expect(if_block.value[:if_content][0].value).to eq('True content')
      expect(if_block.value[:else_content]).to be_empty
    end

    it 'parses if block with else' do
      template = '{{#if condition}}True{{else}}False{{/if}}'
      grammar = described_class.new(template)
      grammar.parse!

      expect(grammar.ast.children.size).to eq(1)

      if_block = grammar.ast.children[0]
      expect(if_block.type).to eq(:if_block)
      expect(if_block.value[:condition]).to eq('condition')
      expect(if_block.value[:if_content].size).to eq(1)
      expect(if_block.value[:if_content][0].value).to eq('True')
      expect(if_block.value[:else_content].size).to eq(1)
      expect(if_block.value[:else_content][0].value).to eq('False')
    end

    it 'parses unless block' do
      template = '{{#unless condition}}Content{{/unless}}'
      grammar = described_class.new(template)
      grammar.parse!

      expect(grammar.ast.children.size).to eq(1)

      unless_block = grammar.ast.children[0]
      expect(unless_block.type).to eq(:unless_block)
      expect(unless_block.value[:condition]).to eq('condition')
      expect(unless_block.value[:content].size).to eq(1)
      expect(unless_block.value[:content][0].value).to eq('Content')
    end

    it 'parses each block' do
      template = '{{#each items}}Item: {{name}}{{/each}}'
      grammar = described_class.new(template)
      grammar.parse!

      expect(grammar.ast.children.size).to eq(1)

      each_block = grammar.ast.children[0]
      expect(each_block.type).to eq(:each_block)
      expect(each_block.value[:items]).to eq('items')
      expect(each_block.value[:content].size).to eq(2)
      expect(each_block.value[:content][0].value).to eq('Item: ')
      expect(each_block.value[:content][1].type).to eq(:variable_expression)
      expect(each_block.value[:content][1].value[:name]).to eq('name')
    end

    it 'parses nested if blocks' do
      template = '{{#if outer}}{{#if inner}}Nested{{/if}}{{/if}}'
      grammar = described_class.new(template)
      grammar.parse!

      expect(grammar.ast.children.size).to eq(1)

      outer_if = grammar.ast.children[0]
      expect(outer_if.type).to eq(:if_block)
      expect(outer_if.value[:condition]).to eq('outer')
      expect(outer_if.value[:if_content].size).to eq(1)

      inner_if = outer_if.value[:if_content][0]
      expect(inner_if.type).to eq(:if_block)
      expect(inner_if.value[:condition]).to eq('inner')
      expect(inner_if.value[:if_content][0].value).to eq('Nested')
    end

    it 'parses complex template with mixed content' do
      template = <<~TEMPLATE
        <div>
          <h1>{{title}}</h1>
          {{#if user}}
            <p>Welcome {{user.name}}!</p>
            {{#each items}}
              <li>{{name}}</li>
            {{/each}}
          {{else}}
            <p>Please log in</p>
          {{/if}}
          {{> footer}}
        </div>
      TEMPLATE

      grammar = described_class.new(template)
      grammar.parse!

      expect(grammar.ast.children.size).to be >= 4

      # Should contain text, variable, if block, and partial
      types = grammar.ast.children.map(&:type)
      expect(types).to include(:text, :variable_expression, :if_block, :partial_expression)
    end
  end

  describe '#variables' do
    it 'collects variables from simple expressions' do
      grammar = described_class.new('{{name}} and {{age}}')
      grammar.parse!

      expect(grammar.variables).to contain_exactly('name', 'age')
    end

    it 'collects variables from block conditions' do
      grammar = described_class.new('{{#if authenticated}}{{username}}{{/if}}')
      grammar.parse!

      expect(grammar.variables).to contain_exactly('authenticated', 'username')
    end

    it 'collects variables from each blocks' do
      grammar = described_class.new('{{#each users}}{{name}}{{/each}}')
      grammar.parse!

      expect(grammar.variables).to contain_exactly('users', 'name')
    end

    it 'collects variables from nested blocks' do
      grammar = described_class.new('{{#if outer}}{{#each items}}{{name}}{{/each}}{{/if}}')
      grammar.parse!

      expect(grammar.variables).to contain_exactly('outer', 'items', 'name')
    end

    it 'deduplicates variables' do
      grammar = described_class.new('{{name}} {{name}} {{age}}')
      grammar.parse!

      expect(grammar.variables).to contain_exactly('name', 'age')
    end
  end

  describe '#partials' do
    it 'collects partials from simple expressions' do
      grammar = described_class.new('{{> header}} {{> footer}}')
      grammar.parse!

      expect(grammar.partials).to contain_exactly('header', 'footer')
    end

    it 'collects partials from inside blocks' do
      grammar = described_class.new('{{#if show}}{{> content}}{{/if}}')
      grammar.parse!

      expect(grammar.partials).to contain_exactly('content')
    end

    it 'collects partials from nested blocks' do
      grammar = described_class.new('{{#if outer}}{{#each items}}{{> item}}{{/each}}{{/if}}')
      grammar.parse!

      expect(grammar.partials).to contain_exactly('item')
    end

    it 'deduplicates partials' do
      grammar = described_class.new('{{> header}} {{> header}} {{> footer}}')
      grammar.parse!

      expect(grammar.partials).to contain_exactly('header', 'footer')
    end
  end

  describe '#blocks' do
    it 'collects blocks from template' do
      grammar = described_class.new('{{#if condition}}content{{/if}}')
      grammar.parse!

      blocks = grammar.blocks
      expect(blocks.size).to eq(1)
      expect(blocks[0].type).to eq(:if_block)
    end

    it 'collects nested blocks' do
      grammar = described_class.new('{{#if outer}}{{#each items}}{{name}}{{/each}}{{/if}}')
      grammar.parse!

      blocks = grammar.blocks
      expect(blocks.size).to eq(2)
      expect(blocks.map(&:type)).to contain_exactly(:if_block, :each_block)
    end

    it 'collects multiple block types' do
      grammar = described_class.new('{{#if test}}{{/if}}{{#unless other}}{{/unless}}{{#each items}}{{/each}}')
      grammar.parse!

      blocks = grammar.blocks
      expect(blocks.size).to eq(3)
      expect(blocks.map(&:type)).to contain_exactly(:if_block, :unless_block, :each_block)
    end
  end

  describe 'error handling' do
    it 'raises error for unclosed variable expression' do
      grammar = described_class.new('{{name')

      expect { grammar.parse! }.to raise_error(Rhales::HandlebarsGrammar::ParseError) do |error|
        expect(error.message).to include("Expected '}}'")
      end
    end

    it 'raises error for unclosed raw expression' do
      grammar = described_class.new('{{{html}}')

      expect { grammar.parse! }.to raise_error(Rhales::HandlebarsGrammar::ParseError) do |error|
        expect(error.message).to include("Expected '}}}'")
      end
    end

    it 'raises error for unclosed if block' do
      grammar = described_class.new('{{#if condition}}content')

      expect { grammar.parse! }.to raise_error(Rhales::HandlebarsGrammar::ParseError) do |error|
        expect(error.message).to include("Missing closing tag for {{#if}}")
      end
    end

    it 'raises error for unclosed each block' do
      grammar = described_class.new('{{#each items}}content')

      expect { grammar.parse! }.to raise_error(Rhales::HandlebarsGrammar::ParseError) do |error|
        expect(error.message).to include("Missing closing tag for {{#each}}")
      end
    end

    it 'raises error for unclosed unless block' do
      grammar = described_class.new('{{#unless condition}}content')

      expect { grammar.parse! }.to raise_error(Rhales::HandlebarsGrammar::ParseError) do |error|
        expect(error.message).to include("Missing closing tag for {{#unless}}")
      end
    end

    it 'raises error for unexpected closing tag' do
      grammar = described_class.new('{{/if}}')

      expect { grammar.parse! }.to raise_error(Rhales::HandlebarsGrammar::ParseError) do |error|
        expect(error.message).to include("Unexpected closing tag")
      end
    end

    it 'raises error for unexpected else' do
      grammar = described_class.new('{{else}}')

      expect { grammar.parse! }.to raise_error(Rhales::HandlebarsGrammar::ParseError) do |error|
        expect(error.message).to include("Unexpected 'else' outside of block")
      end
    end

    it 'includes line and column information in errors' do
      grammar = described_class.new("line 1\nline 2\n{{invalid")

      expect { grammar.parse! }.to raise_error(Rhales::HandlebarsGrammar::ParseError) do |error|
        expect(error.line).to eq(3)
        expect(error.column).to be > 0
      end
    end
  end

  describe 'whitespace handling' do
    it 'preserves whitespace in text nodes' do
      grammar = described_class.new("  \n  {{name}}  \n  ")
      grammar.parse!

      expect(grammar.ast.children.size).to eq(3)
      expect(grammar.ast.children[0].value).to eq("  \n  ")
      expect(grammar.ast.children[2].value).to eq("  \n  ")
    end

    it 'trims whitespace in expression content' do
      grammar = described_class.new('{{  name  }}')
      grammar.parse!

      expect(grammar.ast.children[0].value[:name]).to eq('name')
    end

    it 'handles expressions with internal whitespace' do
      grammar = described_class.new('{{#if user.authenticated}}content{{/if}}')
      grammar.parse!

      if_block = grammar.ast.children[0]
      expect(if_block.value[:condition]).to eq('user.authenticated')
    end
  end

  describe 'edge cases' do
    it 'handles empty template' do
      grammar = described_class.new('')
      grammar.parse!

      expect(grammar.ast.children).to be_empty
    end

    it 'handles template with only whitespace' do
      grammar = described_class.new("  \n  \t  ")
      grammar.parse!

      expect(grammar.ast.children.size).to eq(1)
      expect(grammar.ast.children[0].type).to eq(:text)
    end

    it 'handles expressions at start and end' do
      grammar = described_class.new('{{start}}middle{{end}}')
      grammar.parse!

      expect(grammar.ast.children.size).to eq(3)
      expect(grammar.ast.children[0].type).to eq(:variable_expression)
      expect(grammar.ast.children[1].type).to eq(:text)
      expect(grammar.ast.children[2].type).to eq(:variable_expression)
    end

    it 'handles consecutive expressions' do
      grammar = described_class.new('{{first}}{{second}}')
      grammar.parse!

      expect(grammar.ast.children.size).to eq(2)
      expect(grammar.ast.children[0].type).to eq(:variable_expression)
      expect(grammar.ast.children[1].type).to eq(:variable_expression)
    end

    it 'handles blocks with no content' do
      grammar = described_class.new('{{#if condition}}{{/if}}')
      grammar.parse!

      if_block = grammar.ast.children[0]
      expect(if_block.value[:if_content]).to be_empty
    end

    it 'handles complex partial names' do
      grammar = described_class.new('{{> path/to/partial}}')
      grammar.parse!

      expect(grammar.ast.children[0].value[:name]).to eq('path/to/partial')
    end
  end
end
