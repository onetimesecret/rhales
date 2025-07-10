# spec/rhales/tokenize_performance_spec.rb

require 'spec_helper'
require 'benchmark'

RSpec.describe 'Tokenize Performance Baseline' do
  # Original tokenize_content implementation preserved for performance comparison
  # This serves as a baseline for measuring StringScanner improvements
  def tokenize_content_baseline(content)
    tokens = []
    i = 0

    while i < content.length
      case
      when content[i, 4] == '<!--'
        # Comment token
        comment_end = content.index('-->', i + 4)
        if comment_end
          comment_content = content[i..comment_end + 2]
          tokens << { type: :comment, content: comment_content }
          i = comment_end + 3
        else
          # Unclosed comment - treat as text
          tokens << { type: :text, content: content[i] }
          i += 1
        end
      when content[i] == '<' && content[i + 1] != '!' && content[i + 1] != '/'
        # Potential section start
        tag_end = content.index('>', i)
        if tag_end && (match = content[i..tag_end].match(/^<(data|template|logic)(\s[^>]*)?>/))
          tokens << { type: :section_start, content: content[i..tag_end] }
          i = tag_end + 1
        else
          tokens << { type: :text, content: content[i] }
          i += 1
        end
      when content[i, 2] == '</'
        # Potential section end
        tag_end = content.index('>', i)
        if tag_end && (match = content[i..tag_end].match(/^<\/(data|template|logic)>/))
          tokens << { type: :section_end, content: content[i..tag_end] }
          i = tag_end + 1
        else
          tokens << { type: :text, content: content[i] }
          i += 1
        end
      else
        # Regular text
        tokens << { type: :text, content: content[i] }
        i += 1
      end
    end

    tokens
  end

  describe 'Baseline tokenize_content behavior' do
    it 'tokenizes simple content correctly' do
      content = '<data>{"test": "value"}</data>'
      tokens = tokenize_content_baseline(content)

      expect(tokens.length).to be > 5
      expect(tokens[0]).to eq({ type: :section_start, content: '<data>' })
      expect(tokens[-1]).to eq({ type: :section_end, content: '</data>' })
    end

    it 'handles comments correctly' do
      content = '<!-- comment --><data>test</data>'
      tokens = tokenize_content_baseline(content)

      expect(tokens[0]).to eq({ type: :comment, content: '<!-- comment -->' })
      expect(tokens.find { |t| t[:type] == :section_start }).to eq({ type: :section_start, content: '<data>' })
    end

    it 'handles unclosed comments as text' do
      content = '<!-- unclosed<data>test</data>'
      tokens = tokenize_content_baseline(content)

      # Should have many text tokens for the unclosed comment
      text_tokens = tokens.select { |t| t[:type] == :text }
      expect(text_tokens.length).to be > 10
    end

    it 'tokenizes complex content with multiple sections' do
      content = <<~RUE
        <!-- Header comment -->
        <data window="test">
        {"key": "value"}
        </data>
        <!-- Between sections -->
        <template>
        <h1>{{title}}</h1>
        </template>
        <!-- Footer comment -->
      RUE

      tokens = tokenize_content_baseline(content)

      comment_tokens = tokens.select { |t| t[:type] == :comment }
      expect(comment_tokens.length).to eq(3)

      section_starts = tokens.select { |t| t[:type] == :section_start }
      expect(section_starts.length).to eq(2)

      section_ends = tokens.select { |t| t[:type] == :section_end }
      expect(section_ends.length).to eq(2)
    end
  end

  describe 'Performance benchmarking' do
    let(:parser) { Rhales::RueFormatParser.new('') }
    let(:simple_content) { '<data>{"test": "value"}</data>' }
    let(:complex_content) do
      <<~RUE
        <!-- Header comment -->
        <data window="testWindow" schema="@/types/window.d.ts">
        {
          "user": {
            "id": 123,
            "name": "Test User",
            "permissions": ["read", "write", "admin"]
          },
          "csrf": "abc123def456",
          "theme": "dark",
          "features": {
            "notifications": true,
            "analytics": false
          }
        }
        </data>
        <!-- Between sections comment -->
        <template>
        <div class="{{theme_class}}">
          <h1>Welcome {{user.name}}!</h1>
          {{#if user.authenticated}}
            <div class="user-info">
              <span>User ID: {{user.id}}</span>
              {{#each user.permissions}}
                <span class="permission">{{name}}</span>
              {{/each}}
            </div>
          {{else}}
            <div class="login-prompt">
              <p>Please log in to continue</p>
              {{> login_form}}
            </div>
          {{/if}}
        </div>
        </template>
        <!-- Footer comment -->
      RUE
    end

    it 'benchmarks baseline simple content tokenization' do
      # Warm up
      5.times { tokenize_content_baseline(simple_content) }

      time = Benchmark.realtime do
        100.times { tokenize_content_baseline(simple_content) }
      end

      puts "\nBaseline tokenization (simple): #{(time * 1000).round(2)}ms for 100 iterations"
      expect(time).to be < 0.1 # Should complete in less than 100ms
    end

    it 'benchmarks StringScanner simple content tokenization' do
      # Warm up
      5.times { parser.send(:tokenize_content, simple_content) }

      time = Benchmark.realtime do
        100.times { parser.send(:tokenize_content, simple_content) }
      end

      puts "StringScanner tokenization (simple): #{(time * 1000).round(2)}ms for 100 iterations"
      expect(time).to be < 0.1 # Should complete in less than 100ms
    end

    it 'benchmarks baseline complex content tokenization' do
      iterations = 50

      # Warm up
      5.times { tokenize_content_baseline(complex_content) }

      time = Benchmark.realtime do
        iterations.times { tokenize_content_baseline(complex_content) }
      end

      puts "\nBaseline tokenization (complex): #{(time * 1000).round(2)}ms for #{iterations} iterations"
      expect(time).to be < 0.5 # Should complete in less than 500ms
    end

    it 'benchmarks StringScanner complex content tokenization' do
      iterations = 50

      # Warm up
      5.times { parser.send(:tokenize_content, complex_content) }

      time = Benchmark.realtime do
        iterations.times { parser.send(:tokenize_content, complex_content) }
      end

      puts "StringScanner tokenization (complex): #{(time * 1000).round(2)}ms for #{iterations} iterations"
      expect(time).to be < 0.5 # Should complete in less than 500ms
    end

    it 'compares performance directly' do
      iterations = 100

      # Baseline performance
      baseline_time = Benchmark.realtime do
        iterations.times { tokenize_content_baseline(simple_content) }
      end

      # StringScanner performance
      scanner_time = Benchmark.realtime do
        iterations.times { parser.send(:tokenize_content, simple_content) }
      end

      improvement = ((baseline_time - scanner_time) / baseline_time * 100).round(1)

      puts "\nPerformance Comparison (#{iterations} iterations):"
      puts "  Baseline: #{(baseline_time * 1000).round(2)}ms"
      puts "  StringScanner: #{(scanner_time * 1000).round(2)}ms"
      puts "  Improvement: #{improvement}%"

      # StringScanner should be faster or at least comparable
      expect(scanner_time).to be <= baseline_time * 1.1 # Allow 10% margin
    end

    it 'measures token count and characteristics' do
      baseline_tokens = tokenize_content_baseline(complex_content)
      scanner_tokens = parser.send(:tokenize_content, complex_content)

      baseline_counts = baseline_tokens.group_by { |t| t[:type] }.transform_values(&:count)
      scanner_counts = scanner_tokens.group_by { |t| t[:type] }.transform_values(&:count)

      puts "\nToken distribution comparison:"
      puts "Baseline token counts:"
      baseline_counts.each { |type, count| puts "  #{type}: #{count}" }
      puts "StringScanner token counts:"
      scanner_counts.each { |type, count| puts "  #{type}: #{count}" }

      # StringScanner should have fewer text tokens due to consolidation
      expect(scanner_counts[:text]).to be < baseline_counts[:text]

      # But same number of structured tokens
      expect(scanner_counts[:comment]).to eq(baseline_counts[:comment])
      expect(scanner_counts[:section_start]).to eq(baseline_counts[:section_start])
      expect(scanner_counts[:section_end]).to eq(baseline_counts[:section_end])
    end
  end
end
