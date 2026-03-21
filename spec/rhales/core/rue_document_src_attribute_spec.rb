# spec/rhales/core/rue_document_src_attribute_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rhales::RueDocument do
  describe 'src attribute support' do
    context 'KNOWN_SCHEMA_ATTRIBUTES' do
      it 'includes src in the known attributes list' do
        expect(described_class::KNOWN_SCHEMA_ATTRIBUTES).to include('src')
      end
    end

    context '#schema_src accessor' do
      let(:rue_content_with_src) do
        <<~RUE
          <schema src="schemas/bootstrap.schema.ts" lang="js-zod" window="__DATA__">
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE
      end

      let(:rue_content_without_src) do
        <<~RUE
          <schema lang="js-zod" window="__DATA__">
          const schema = z.object({ name: z.string() });
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE
      end

      it 'returns the src attribute value when present' do
        doc = described_class.new(rue_content_with_src)
        doc.parse!
        expect(doc.schema_src).to eq('schemas/bootstrap.schema.ts')
      end

      it 'returns nil when src attribute is not present' do
        doc = described_class.new(rue_content_without_src)
        doc.parse!
        expect(doc.schema_src).to be_nil
      end
    end

    context 'attribute validation' do
      let(:rue_content_with_unknown_attr) do
        <<~RUE
          <schema unknown_attr="value" lang="js-zod" window="__DATA__">
          const schema = z.object({});
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE
      end

      it 'does not warn about src attribute' do
        rue_content = <<~RUE
          <schema src="schemas/test.ts" lang="js-zod" window="__DATA__">
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE

        doc = described_class.new(rue_content)
        expect { doc.parse! }.not_to output(/unknown schema attribute.*src/i).to_stderr
      end

      it 'still warns about truly unknown attributes' do
        doc = described_class.new(rue_content_with_unknown_attr)
        expect { doc.parse! }.to output(/unknown_attr.*attribute.*not yet supported/i).to_stderr
      end
    end
  end
end
