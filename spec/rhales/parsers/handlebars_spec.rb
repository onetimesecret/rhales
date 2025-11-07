# spec/rhales/parsers/handlebars_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rhales::HandlebarsParser do
  describe '#parse!' do
    it 'parses plain text' do
      parser = described_class.new('Hello World')
      parser.parse!

      expect(parser.ast.type).to eq(:template)
      expect(parser.ast.children.size).to eq(1)
      expect(parser.ast.children.first.type).to eq(:text)
      expect(parser.ast.children.first.value).to eq('Hello World')
    end

    it 'parses simple variable expression' do
      parser = described_class.new('{{name}}')
      parser.parse!

      expect(parser.ast.children.size).to eq(1)
      expect(parser.ast.children.first.type).to eq(:variable_expression)
      expect(parser.ast.children.first.value[:name]).to eq('name')
      expect(parser.ast.children.first.value[:raw]).to eq(false)
    end

    it 'parses raw variable expression' do
      parser = described_class.new('Content: {{{html}}}')
      parser.parse!

      expect(parser.ast.children.size).to eq(2)
      expect(parser.ast.children[0].type).to eq(:text)
      expect(parser.ast.children[0].value).to eq('Content: ')
      expect(parser.ast.children[1].type).to eq(:variable_expression)
      expect(parser.ast.children[1].value[:name]).to eq('html')
      expect(parser.ast.children[1].value[:raw]).to be(true)
    end

    it 'parses partial expression' do
      parser = described_class.new('{{> header}}')
      parser.parse!

      expect(parser.ast.children.size).to eq(1)
      expect(parser.ast.children.first.type).to eq(:partial_expression)
      expect(parser.ast.children.first.value[:name]).to eq('header')
    end

    it 'parses if block without else' do
      template = '{{#if condition}}Content{{/if}}'
      parser = described_class.new(template)
      parser.parse!

      expect(parser.ast.children.size).to eq(1)
      if_block = parser.ast.children.first
      expect(if_block.type).to eq(:if_block)
      expect(if_block.value[:condition]).to eq('condition')
      expect(if_block.value[:if_content].size).to eq(1)
      expect(if_block.value[:if_content].first.value).to eq('Content')
      expect(if_block.value[:else_content]).to be_empty
    end

    it 'parses if block with else' do
      template = '{{#if user}}Hello{{else}}Goodbye{{/if}}'
      parser = described_class.new(template)
      parser.parse!

      expect(parser.ast.children.size).to eq(1)
      if_block = parser.ast.children.first
      expect(if_block.type).to eq(:if_block)
      expect(if_block.value[:condition]).to eq('user')
      expect(if_block.value[:if_content].size).to eq(1)
      expect(if_block.value[:if_content].first.value).to eq('Hello')
      expect(if_block.value[:else_content].size).to eq(1)
      expect(if_block.value[:else_content].first.value).to eq('Goodbye')
    end

    it 'parses unless block' do
      template = '{{#unless condition}}Content{{/unless}}'
      parser = described_class.new(template)
      parser.parse!

      expect(parser.ast.children.size).to eq(1)
      unless_block = parser.ast.children.first
      expect(unless_block.type).to eq(:unless_block)
      expect(unless_block.value[:condition]).to eq('condition')
      expect(unless_block.value[:content].size).to eq(1)
      expect(unless_block.value[:content].first.value).to eq('Content')
    end

    it 'parses each block' do
      template = '{{#each items}}{{name}}{{/each}}'
      parser = described_class.new(template)
      parser.parse!

      expect(parser.ast.children.size).to eq(1)
      each_block = parser.ast.children.first
      expect(each_block.type).to eq(:each_block)
      expect(each_block.value[:items]).to eq('items')
      expect(each_block.value[:content].size).to eq(1)
      expect(each_block.value[:content].first.type).to eq(:variable_expression)
      expect(each_block.value[:content].first.value[:name]).to eq('name')
    end

    it 'parses nested if blocks' do
      template = '{{#if user}}{{#if admin}}Admin{{/if}}{{/if}}'
      parser = described_class.new(template)
      parser.parse!

      expect(parser.ast.children.size).to eq(1)
      outer_if = parser.ast.children.first
      expect(outer_if.type).to eq(:if_block)
      expect(outer_if.value[:condition]).to eq('user')

      inner_if = outer_if.value[:if_content].first
      expect(inner_if.type).to eq(:if_block)
      expect(inner_if.value[:condition]).to eq('admin')
      expect(inner_if.value[:if_content].first.value).to eq('Admin')
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

      parser = described_class.new(template)
      parser.parse!

      expect(parser.ast.children.size).to be >= 4

      # Should contain text, variable, if block, and partial
      types = parser.ast.children.map(&:type)
      expect(types).to include(:text, :variable_expression, :if_block, :partial_expression)
    end
  end

  describe '#variables' do
    it 'collects variables from simple expressions' do
      parser = described_class.new('{{name}} and {{email}}')
      parser.parse!

      expect(parser.variables).to contain_exactly('name', 'email')
    end

    it 'collects variables from block conditions' do
      parser = described_class.new('{{#if authenticated}}{{name}}{{/if}}')
      parser.parse!

      expect(parser.variables).to contain_exactly('authenticated', 'name')
    end

    it 'collects variables from each blocks' do
      parser = described_class.new('{{#each posts}}{{title}}{{/each}}')
      parser.parse!

      expect(parser.variables).to contain_exactly('posts', 'title')
    end

    it 'collects variables from nested blocks' do
      parser = described_class.new('{{#if user}}{{#each posts}}{{title}}{{/each}}{{/if}}')
      parser.parse!

      expect(parser.variables).to contain_exactly('user', 'posts', 'title')
    end

    it 'deduplicates variables' do
      parser = described_class.new('{{name}} {{#if name}}Hello{{/if}}')
      parser.parse!

      expect(parser.variables).to contain_exactly('name')
    end
  end

  describe '#partials' do
    it 'collects partials from simple expressions' do
      parser = described_class.new('{{> header}} and {{> footer}}')
      parser.parse!

      expect(parser.partials).to contain_exactly('header', 'footer')
    end

    it 'collects partials from inside blocks' do
      parser = described_class.new('{{#if user}}{{> user_info}}{{/if}}')
      parser.parse!

      expect(parser.partials).to contain_exactly('user_info')
    end

    it 'collects partials from nested blocks' do
      parser = described_class.new('{{#if user}}{{#each posts}}{{> post_item}}{{/each}}{{/if}}')
      parser.parse!

      expect(parser.partials).to contain_exactly('post_item')
    end

    it 'deduplicates partials' do
      parser = described_class.new('{{> header}} {{> header}}')
      parser.parse!

      expect(parser.partials).to contain_exactly('header')
    end
  end

  describe '#blocks' do
    it 'collects blocks from template' do
      parser = described_class.new('{{#if condition}}content{{/if}}')
      parser.parse!

      blocks = parser.blocks
      expect(blocks.size).to eq(1)
      expect(blocks[0].type).to eq(:if_block)
    end

    it 'collects nested blocks' do
      parser = described_class.new('{{#if outer}}{{#each items}}{{name}}{{/each}}{{/if}}')
      parser.parse!

      blocks = parser.blocks
      expect(blocks.size).to eq(2)
      expect(blocks.map(&:type)).to contain_exactly(:if_block, :each_block)
    end

    it 'collects multiple block types' do
      parser = described_class.new('{{#if test}}{{/if}}{{#unless other}}{{/unless}}{{#each items}}{{/each}}')
      parser.parse!

      blocks = parser.blocks
      expect(blocks.size).to eq(3)
      expect(blocks.map(&:type)).to contain_exactly(:if_block, :unless_block, :each_block)
    end
  end

  describe 'error handling' do
    it 'raises error for unclosed variable expression' do
      parser = described_class.new('{{name')

      expect { parser.parse! }.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.message).to include("Expected '}}'")
      end
    end

    it 'raises error for unclosed raw expression' do
      parser = described_class.new('{{{html}}')

      expect { parser.parse! }.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.message).to include("Expected '}}}'")
      end
    end

    it 'raises error for unclosed if block' do
      parser = described_class.new('{{#if condition}}content')

      expect { parser.parse! }.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.message).to include("Missing closing tag for {{#if}}")
      end
    end

    it 'raises error for unclosed each block' do
      parser = described_class.new('{{#each items}}content')

      expect { parser.parse! }.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.message).to include("Missing closing tag for {{#each}}")
      end
    end

    it 'raises error for unclosed unless block' do
      parser = described_class.new('{{#unless condition}}content')

      expect { parser.parse! }.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.message).to include("Missing closing tag for {{#unless}}")
      end
    end

    it 'raises error for unexpected closing tag' do
      parser = described_class.new('{{/if}}')

      expect { parser.parse! }.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.message).to include("Unexpected closing tag")
      end
    end

    it 'raises error for unexpected else' do
      parser = described_class.new('{{else}}')

      expect { parser.parse! }.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.message).to include("Unexpected 'else' outside of block")
      end
    end

    it 'includes line and column information in errors' do
      parser = described_class.new("line 1\nline 2\n{{invalid")

      expect { parser.parse! }.to raise_error(Rhales::HandlebarsParser::ParseError) do |error|
        expect(error.line).to eq(3)
        expect(error.column).to be > 0
      end
    end
  end

  describe 'whitespace handling' do
    it 'preserves whitespace in text nodes' do
      parser = described_class.new("  \n  {{name}}  \n  ")
      parser.parse!

      expect(parser.ast.children.size).to eq(3)
      expect(parser.ast.children[0].value).to eq("  \n  ")
      expect(parser.ast.children[2].value).to eq("  \n  ")
    end

    it 'trims whitespace in expression content' do
      parser = described_class.new('{{  name  }}')
      parser.parse!

      expect(parser.ast.children[0].value[:name]).to eq('name')
    end

    it 'handles expressions with internal whitespace' do
      parser = described_class.new('{{#if user.authenticated}}content{{/if}}')
      parser.parse!

      if_block = parser.ast.children[0]
      expect(if_block.value[:condition]).to eq('user.authenticated')
    end
  end

  describe 'edge cases' do
    it 'handles empty template' do
      parser = described_class.new('')
      parser.parse!

      expect(parser.ast.type).to eq(:template)
      expect(parser.ast.children).to be_empty
    end

    it 'handles template with only whitespace' do
      parser = described_class.new('   ')
      parser.parse!

      expect(parser.ast.children.size).to eq(1)
      expect(parser.ast.children.first.type).to eq(:text)
    end

    it 'handles expressions at start and end' do
      template = '{{start}}middle{{end}}'
      parser = described_class.new(template)
      parser.parse!

      expect(parser.ast.children.size).to eq(3)
      expect(parser.ast.children[0].type).to eq(:variable_expression)
      expect(parser.ast.children[1].type).to eq(:text)
      expect(parser.ast.children[2].type).to eq(:variable_expression)
    end

    it 'handles consecutive expressions' do
      parser = described_class.new('{{first}}{{second}}')
      parser.parse!

      expect(parser.ast.children.size).to eq(2)
      expect(parser.ast.children[0].type).to eq(:variable_expression)
      expect(parser.ast.children[1].type).to eq(:variable_expression)
    end

    it 'handles blocks with no content' do
      parser = described_class.new('{{#if condition}}{{/if}}')
      parser.parse!

      expect(parser.ast.children.size).to eq(1)
      if_block = parser.ast.children.first
      expect(if_block.type).to eq(:if_block)
      expect(if_block.value[:if_content]).to be_empty
    end

    it 'handles complex partial names' do
      parser = described_class.new('{{> user/profile}} {{> nav.header}}')
      parser.parse!

      expect(parser.partials).to contain_exactly('user/profile', 'nav.header')
    end
  end
end
