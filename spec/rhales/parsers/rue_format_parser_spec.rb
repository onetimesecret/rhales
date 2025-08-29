# spec/rhales/parsers/rue_format_parser_spec.rb

require 'spec_helper'
require 'rhales'

RSpec.describe Rhales::RueFormatParser do
  let(:valid_content) do
    <<~RUE
      <data window="appState" layout="main">
        {
          "user": "{{user.name}}"
        }
      </data>

      <template>
        <h1>Hello, {{user.name}}</h1>
        {{> user_profile}}
      </template>

      <logic>
        This is a comment.
      </logic>
    RUE
  end

  let(:malformed_content) { '<data>...<template>...</template>' } # Missing closing data tag

  # Helper to reconstruct the content from an AST node array
  def reconstruct_content(nodes)
    nodes.map do |node|
      case node.type
      when :text
        node.value
      when :variable_expression
        # NOTE: The handlebars parser might return a hash for the value,
        # so we need to handle that case.
        if node.value.is_a?(Hash)
          "{{#{node.value[:name]}}}"
        else
          node.value
        end
      when :partial_expression
        "{{> #{node.value[:name]}}}"
      else
        # For other node types, we might need to recursively reconstruct.
        # This simple version handles the current test cases.
        reconstruct_content(node.children) if node.children.any?
      end
    end.join.gsub('&gt;', '>')
  end

  # Helper to get the reconstructed content from a section node
  def get_section_content(ast, tag_name)
    section_node = ast.children.find { |n| n.value[:tag] == tag_name }
    return nil unless section_node

    # For template sections, we reconstruct from the AST. For others, we just join.
    if tag_name == 'template'
      reconstruct_content(section_node.value[:content]).strip
    else
      section_node.value[:content].map(&:value).join.strip
    end
  end

  [:rexml, :oga, :nokogiri].each do |parser_type|
    context "when using the #{parser_type.to_s.upcase} parser" do
      before do
        Rhales.reset_configuration!
        # Ensure the required gem is loaded for the test
        begin
          require parser_type.to_s
        rescue LoadError
          # Skip test if gem isn't installed
          skip "Skipping #{parser_type} tests: `#{parser_type}` gem not installed."
        end
        Rhales.configure { |config| config.xml_parser = parser_type }
      end

      subject(:parser) { described_class.new(valid_content) }

      it 'parses the document without errors' do
        expect { parser.parse! }.not_to raise_error
      end

      it 'identifies all three sections' do
        ast = parser.parse!.ast
        tags = ast.children.map { |node| node.value[:tag] }
        expect(tags).to contain_exactly('data', 'template', 'logic')
      end

      it 'parses attributes from the data tag' do
        ast = parser.parse!.ast
        data_node = ast.children.find { |n| n.value[:tag] == 'data' }
        attributes = data_node.value[:attributes]
        expect(attributes['window']).to eq('appState')
        expect(attributes['layout']).to eq('main')
      end

      it 'extracts the content of the data section' do
        ast = parser.parse!.ast
        content = get_section_content(ast, 'data')
        expect(content).to include('"user": "{{user.name}}"')
      end

      it 'extracts the content of the template section' do
        ast = parser.parse!.ast
        content = get_section_content(ast, 'template')
        expect(content).to include('<h1>Hello, {{user.name}}</h1>')
        expect(content).to include('{{> user_profile}}')
      end

      it 'raises a ParseError for malformed content' do
        parser = described_class.new(malformed_content)
        expect { parser.parse! }.to raise_error(Rhales::ParseError)
      end
    end
  end
end
