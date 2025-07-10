# spec/rhales/parsers/rue_format_parser_spec.rb

require 'spec_helper'

RSpec.describe Rhales::RueFormatParser do
  describe '#parse!' do
    it 'parses basic .rue file structure' do
      content = <<~RUE
        <data>
        {"greeting": "Hello World"}
        </data>

        <template>
        <h1>{{greeting}}</h1>
        </template>
      RUE

      parser = described_class.new(content)
      parser.parse!

      expect(parser.sections.keys).to contain_exactly('data', 'template')
      expect(parser.sections['data'].value[:tag]).to eq('data')
      expect(parser.sections['template'].value[:tag]).to eq('template')
    end

    it 'parses section attributes' do
      content = <<~RUE
        <data window="testData" schema="/api/schema.json">
        {"test": "value"}
        </data>

        <template>
        <div>Test</div>
        </template>
      RUE

      parser = described_class.new(content)
      parser.parse!

      data_section = parser.sections['data']
      expect(data_section.value[:attributes]).to eq({
        'window' => 'testData',
        'schema' => '/api/schema.json'
      })
    end

    it 'handles all three section types' do
      content = <<~RUE
        <data>
        {"test": "value"}
        </data>

        <template>
        <div>Content</div>
        </template>

        <logic>
        # Some Ruby logic
        </logic>
      RUE

      parser = described_class.new(content)
      parser.parse!

      expect(parser.sections.keys).to contain_exactly('data', 'template', 'logic')
    end
  end

  describe 'UTF-8 character handling' do
    it 'handles emoji characters in data section' do
      content = <<~RUE
        <data>
        {
          "features": [
            {
              "title": "Templates",
              "icon": "📄"
            },
            {
              "title": "Hydration",
              "icon": "💧"
            }
          ]
        }
        </data>

        <template>
        <div>Test</div>
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      data_section = parser.sections['data']
      data_content = data_section.value[:content].find { |node| node.type == :text }
      expect(data_content.value).to include('📄')
      expect(data_content.value).to include('💧')
    end

    it 'handles emoji characters in template section' do
      content = <<~RUE
        <data>
        {"test": "value"}
        </data>

        <template>
        <div class="status">
          <span>✓ Success</span>
          <span>❌ Error</span>
          <span>🔄 Loading</span>
        </div>
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      template_section = parser.sections['template']
      template_content = template_section.value[:content].find { |node| node.type == :text }
      expect(template_content.value).to include('✓')
      expect(template_content.value).to include('❌')
      expect(template_content.value).to include('🔄')
    end

    it 'handles complex emoji sequences' do
      content = <<~RUE
        <data>
        {
          "reactions": ["👍", "👎", "🎉", "😂", "😢", "😡"],
          "flags": ["🇺🇸", "🇬🇧", "🇫🇷", "🇩🇪"]
        }
        </data>

        <template>
        <div>👨‍💻 Developer working on 🚀 rocket</div>
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      data_section = parser.sections['data']
      data_content = data_section.value[:content].find { |node| node.type == :text }
      expect(data_content.value).to include('👍')
      expect(data_content.value).to include('🇺🇸')

      template_section = parser.sections['template']
      template_content = template_section.value[:content].find { |node| node.type == :text }
      expect(template_content.value).to include('👨‍💻')
      expect(template_content.value).to include('🚀')
    end

    it 'handles mixed ASCII and UTF-8 content' do
      content = <<~RUE
        <data>
        {
          "message": "Hello 世界! 🌍",
          "price": "¥1000 💰",
          "math": "π ≈ 3.14159"
        }
        </data>

        <template>
        <div>
          <p>English text</p>
          <p>日本語テキスト</p>
          <p>Español con ñ</p>
          <p>Français avec é</p>
          <p>Emoji: 🎨 🎯 🎪</p>
        </div>
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      data_section = parser.sections['data']
      data_content = data_section.value[:content].find { |node| node.type == :text }
      expect(data_content.value).to include('世界')
      expect(data_content.value).to include('🌍')
      expect(data_content.value).to include('¥')
      expect(data_content.value).to include('π')

      template_section = parser.sections['template']
      template_content = template_section.value[:content].find { |node| node.type == :text }
      expect(template_content.value).to include('日本語')
      expect(template_content.value).to include('ñ')
      expect(template_content.value).to include('é')
      expect(template_content.value).to include('🎨')
    end

    it 'handles various Unicode categories' do
      content = <<~RUE
        <data>
        {
          "symbols": "© ® ™ ℠",
          "arrows": "← → ↑ ↓",
          "math": "∑ ∫ ∞ √"
        }
        </data>

        <template>
        <div>
          <p>Symbols: © ® ™ ℠</p>
          <p>Arrows: ← → ↑ ↓</p>
          <p>Math: ∑ ∫ ∞ √</p>
        </div>
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      sections = parser.sections
      expect(sections.keys).to contain_exactly('data', 'template')
    end
  end

  describe 'position tracking with UTF-8 characters' do
    it 'reports correct positions for errors after emoji characters' do
      content = <<~RUE
        <data>
        {
          "icon": "📄",
          "status": "✓"
        }
        </data>

        <template>
        <div>Content</div>
        </template>

        <invalid_section>
        Should cause error
        </invalid_section>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Unknown sections: invalid_section')
      end
    end

    it 'handles closing tag detection after emoji characters' do
      content = <<~RUE
        <data>
        {
          "features": [
            {"icon": "📄", "title": "Templates"},
            {"icon": "💧", "title": "Hydration"},
            {"icon": "🔧", "title": "Syntax"},
            {"icon": "🔐", "title": "Auth"}
          ]
        }
        </data>

        <template>
        <div>✓ Success message</div>
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      # Verify sections are parsed correctly
      expect(parser.sections.keys).to contain_exactly('data', 'template')

      # Verify content includes all emojis
      data_section = parser.sections['data']
      data_content = data_section.value[:content].find { |node| node.type == :text }
      expect(data_content.value).to include('📄')
      expect(data_content.value).to include('💧')
      expect(data_content.value).to include('🔧')
      expect(data_content.value).to include('🔐')
    end

    it 'handles unclosed sections with emoji content' do
      content = <<~RUE
        <data>
        {
          "greeting": "Hello 🌍",
          "status": "✓ Ready"
        }
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include("Expected '</data>' to close section")
      end
    end
  end

  describe 'error handling with UTF-8 content' do
    it 'provides accurate error messages with emoji characters' do
      content = <<~RUE
        <data>
        {
          "message": "Hello 🌍"
        }
        </data>

        <template>
        <div>✓ Status</div>
        </template>

        <data>
        {
          "duplicate": "error 💥"
        }
        </data>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Duplicate sections: data')
      end
    end

    it 'handles malformed tags with UTF-8 content' do
      content = <<~RUE
        <data>
        {"emoji": "🎉"}
        </data>

        <template
        <div>Missing closing bracket</div>
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Expected identifier')
      end
    end

    it 'handles missing closing tags with UTF-8 content' do
      content = <<~RUE
        <data>
        {
          "icons": ["📄", "💧", "🔧"],
          "status": "✓ Working"
        }
        </data>

        <template>
        <div>Content with emoji 🎨</div>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include("Expected '</template>' to close section")
      end
    end
  end

  describe 'validation' do
    it 'requires at least one of data or template sections' do
      content = <<~RUE
        <logic>
        # Just logic, no data or template
        </logic>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Must have at least one of: data, template')
      end
    end

    it 'rejects duplicate sections' do
      content = <<~RUE
        <data>
        {"first": "data"}
        </data>

        <template>
        <div>Template</div>
        </template>

        <data>
        {"second": "data"}
        </data>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Duplicate sections: data')
      end
    end

    it 'rejects unknown sections' do
      content = <<~RUE
        <data>
        {"test": "value"}
        </data>

        <template>
        <div>Content</div>
        </template>

        <styles>
        .test { color: red; }
        </styles>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Unknown sections: styles')
      end
    end

    it 'rejects empty files' do
      parser = described_class.new('')
      expect { parser.parse! }.to raise_error(Rhales::RueFormatParser::ParseError) do |error|
        expect(error.message).to include('Empty .rue file')
      end
    end
  end

  describe 'edge cases' do
    it 'handles whitespace-only content' do
      content = <<~RUE
        <data>

        </data>

        <template>

        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      expect(parser.sections.keys).to contain_exactly('data', 'template')
    end

    it 'handles single-line sections' do
      content = '<data>{"test": "value"}</data><template><div>Content</div></template>'

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      expect(parser.sections.keys).to contain_exactly('data', 'template')
    end

    it 'handles sections with only UTF-8 content' do
      content = <<~RUE
        <data>
        {"emoji": "🎉🎊🎈"}
        </data>

        <template>
        🌟✨🎆
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      template_section = parser.sections['template']
      template_content = template_section.value[:content].find { |node| node.type == :text }
      expect(template_content.value).to include('🌟')
      expect(template_content.value).to include('✨')
      expect(template_content.value).to include('🎆')
    end

    it 'handles very long UTF-8 content' do
      emoji_string = '🎉' * 1000  # 1000 emoji characters
      content = <<~RUE
        <data>
        {"emojis": "#{emoji_string}"}
        </data>

        <template>
        <div>#{emoji_string}</div>
        </template>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      data_section = parser.sections['data']
      data_content = data_section.value[:content].find { |node| node.type == :text }
      expect(data_content.value.count('🎉')).to eq(1000)
    end
  end

  describe 'real-world demo template' do
    it 'parses the actual demo template that was failing' do
      content = <<~RUE
        <data window="data" layout="layouts/main">
        {
          "page_type": "public",
          "features": [
            {
              "title": "RSFC Templates",
              "description": "Ruby Single File Components with data, template, and logic sections",
              "icon": "📄"
            },
            {
              "title": "Client-Side Hydration",
              "description": "Secure data injection with CSP nonce support",
              "icon": "💧"
            },
            {
              "title": "Handlebars Syntax",
              "description": "Familiar template syntax with conditionals and iteration",
              "icon": "🔧"
            },
            {
              "title": "Authentication Ready",
              "description": "Pluggable auth adapters for any framework",
              "icon": "🔐"
            }
          ]
        }
        </data>

        <template>
        <div class="hero-section">
          <h1 class="hero-title">Welcome to Rhales Demo</h1>
          <p class="hero-subtitle">
            ✓ Experience the power of Ruby Single File Components
          </p>

          <div class="features-section">
            <h2>RSFC Features Demonstrated</h2>
            <div class="features-grid">
              {{#each features}}
                <div class="feature-card">
                  <div class="feature-icon">{{icon}}</div>
                  <h3 class="feature-title">{{title}}</h3>
                  <p class="feature-description">{{description}}</p>
                </div>
              {{/each}}
            </div>
          </div>
        </div>
        </template>

        <logic>
        # Homepage showcases Rhales features with authentication demo
        # Demonstrates conditional rendering based on auth state
        # Shows demo credentials for easy testing
        </logic>
      RUE

      parser = described_class.new(content)
      expect { parser.parse! }.not_to raise_error

      # Verify all sections are present
      expect(parser.sections.keys).to contain_exactly('data', 'template', 'logic')

      # Verify data section contains emoji icons
      data_section = parser.sections['data']
      data_content = data_section.value[:content].find { |node| node.type == :text }
      expect(data_content.value).to include('📄')
      expect(data_content.value).to include('💧')
      expect(data_content.value).to include('🔧')
      expect(data_content.value).to include('🔐')

      # Verify template section contains checkmark
      template_section = parser.sections['template']
      template_content = template_section.value[:content].find { |node| node.type == :text }

      expect(template_content.value).to include('✓')

      # Verify attributes are parsed correctly
      expect(data_section.value[:attributes]).to eq({
        'window' => 'data',
        'layout' => 'layouts/main'
      })
    end
  end
end
