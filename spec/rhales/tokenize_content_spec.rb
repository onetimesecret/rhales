# spec/rhales/tokenize_content_spec.rb

require 'spec_helper'

RSpec.describe 'TokenizeContent Method' do
  let(:parser) { Rhales::RueFormatParser.new('') }

  describe 'tokenize_content private method' do
    it 'tokenizes simple text' do
      tokens = parser.send(:tokenize_content, 'hello world')

      expect(tokens.length).to eq(1) # StringScanner consolidates text runs
      expect(tokens.all? { |t| t[:type] == :text }).to be true
      expect(tokens.map { |t| t[:content] }.join).to eq('hello world')
    end

    it 'tokenizes comments' do
      tokens = parser.send(:tokenize_content, '<!-- comment -->')

      expect(tokens.length).to eq(1)
      expect(tokens[0]).to eq({ type: :comment, content: '<!-- comment -->' })
    end

    it 'tokenizes multi-line comments' do
      content = <<~CONTENT
        <!--
        Multi-line
        comment
        -->
      CONTENT

      tokens = parser.send(:tokenize_content, content)

      comment_token = tokens.find { |t| t[:type] == :comment }
      expect(comment_token).not_to be_nil
      expect(comment_token[:content]).to include('Multi-line')
      expect(comment_token[:content]).to include('comment')
    end

    it 'handles unclosed comments as text' do
      tokens = parser.send(:tokenize_content, '<!-- unclosed')

      # Should create individual text tokens
      expect(tokens.all? { |t| t[:type] == :text }).to be true
      expect(tokens.map { |t| t[:content] }.join).to eq('<!-- unclosed')
    end

    it 'tokenizes section start tags' do
      tokens = parser.send(:tokenize_content, '<data>')

      expect(tokens.length).to eq(1)
      expect(tokens[0]).to eq({ type: :section_start, content: '<data>' })
    end

    it 'tokenizes section start tags with attributes' do
      tokens = parser.send(:tokenize_content, '<data window="test" schema="schema.json">')

      expect(tokens.length).to eq(1)
      expect(tokens[0]).to eq({ type: :section_start, content: '<data window="test" schema="schema.json">' })
    end

    it 'tokenizes section end tags' do
      tokens = parser.send(:tokenize_content, '</data>')

      expect(tokens.length).to eq(1)
      expect(tokens[0]).to eq({ type: :section_end, content: '</data>' })
    end

    it 'handles invalid section tags as text' do
      tokens = parser.send(:tokenize_content, '<invalid>')

      expect(tokens.length).to eq(2) # StringScanner consolidates: "<" and "invalid>"
      expect(tokens.all? { |t| t[:type] == :text }).to be true
      expect(tokens.map { |t| t[:content] }.join).to eq('<invalid>')
    end

    it 'tokenizes mixed content correctly' do
      content = '<!-- comment --><data>content</data>'
      tokens = parser.send(:tokenize_content, content)

      expect(tokens[0]).to eq({ type: :comment, content: '<!-- comment -->' })
      expect(tokens[1]).to eq({ type: :section_start, content: '<data>' })

      # Content should be consolidated text token
      content_tokens = tokens[2..-2] # Exclude start and end tags
      expect(content_tokens.length).to eq(1) # StringScanner consolidates text
      expect(content_tokens.all? { |t| t[:type] == :text }).to be true
      expect(content_tokens.map { |t| t[:content] }.join).to eq('content')

      expect(tokens.last).to eq({ type: :section_end, content: '</data>' })
    end

    it 'handles empty content' do
      tokens = parser.send(:tokenize_content, '')

      expect(tokens).to be_empty
    end

    it 'handles content with only whitespace' do
      tokens = parser.send(:tokenize_content, '   \n\t  ')

      expect(tokens.length).to eq(1) # StringScanner consolidates whitespace runs
      expect(tokens.all? { |t| t[:type] == :text }).to be true
      expect(tokens.map { |t| t[:content] }.join).to eq('   \n\t  ')
    end

    it 'handles complex nested content' do
      content = <<~CONTENT
        <!-- Header -->
        <data window="test">
        {"key": "value"}
        </data>
        <!-- Between -->
        <template>
        <h1>{{title}}</h1>
        </template>
      CONTENT

      tokens = parser.send(:tokenize_content, content)

      comment_tokens = tokens.select { |t| t[:type] == :comment }
      expect(comment_tokens.length).to eq(2)
      expect(comment_tokens[0][:content]).to eq('<!-- Header -->')
      expect(comment_tokens[1][:content]).to eq('<!-- Between -->')

      section_starts = tokens.select { |t| t[:type] == :section_start }
      expect(section_starts.length).to eq(2)
      expect(section_starts[0][:content]).to eq('<data window="test">')
      expect(section_starts[1][:content]).to eq('<template>')

      section_ends = tokens.select { |t| t[:type] == :section_end }
      expect(section_ends.length).to eq(2)
      expect(section_ends[0][:content]).to eq('</data>')
      expect(section_ends[1][:content]).to eq('</template>')
    end

    it 'handles edge case with < not followed by valid tag' do
      tokens = parser.send(:tokenize_content, '<notag')

      expect(tokens.length).to eq(2) # StringScanner: "<" and "notag"
      expect(tokens.all? { |t| t[:type] == :text }).to be true
      expect(tokens.map { |t| t[:content] }.join).to eq('<notag')
    end

    it 'handles edge case with </ not followed by valid tag' do
      tokens = parser.send(:tokenize_content, '</invalid')

      expect(tokens.length).to eq(2) # StringScanner: "</" and "invalid"
      expect(tokens.all? { |t| t[:type] == :text }).to be true
      expect(tokens.map { |t| t[:content] }.join).to eq('</invalid')
    end

    it 'handles malformed section tags' do
      tokens = parser.send(:tokenize_content, '<data unclosed')

      # Should treat all as text since no closing >
      expect(tokens.length).to eq(2) # StringScanner: "<" and "data unclosed"
      expect(tokens.all? { |t| t[:type] == :text }).to be true
      expect(tokens.map { |t| t[:content] }.join).to eq('<data unclosed')
    end

    it 'handles comments mixed with section tags' do
      content = '<data><!-- inside section --></data>'
      tokens = parser.send(:tokenize_content, content)

      expect(tokens[0]).to eq({ type: :section_start, content: '<data>' })
      expect(tokens[1]).to eq({ type: :comment, content: '<!-- inside section -->' })
      expect(tokens.last).to eq({ type: :section_end, content: '</data>' })
    end

    it 'preserves token order' do
      content = 'a<!-- c -->b<data>d</data>e'
      tokens = parser.send(:tokenize_content, content)

      # Should maintain exact order
      expect(tokens[0]).to eq({ type: :text, content: 'a' })
      expect(tokens[1]).to eq({ type: :comment, content: '<!-- c -->' })
      expect(tokens[2]).to eq({ type: :text, content: 'b' })
      expect(tokens[3]).to eq({ type: :section_start, content: '<data>' })
      expect(tokens[4]).to eq({ type: :text, content: 'd' })
      expect(tokens[5]).to eq({ type: :section_end, content: '</data>' })
      expect(tokens[6]).to eq({ type: :text, content: 'e' })
    end
  end
end
