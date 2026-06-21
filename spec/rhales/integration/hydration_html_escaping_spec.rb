# spec/rhales/integration/hydration_html_escaping_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe 'hydration HTML escaping (XSS protection)' do
  let(:templates_dir) { File.join(__dir__, '../../fixtures/templates/hydration_escape_test') }

  before do
    FileUtils.mkdir_p(templates_dir)
  end

  after do
    FileUtils.rm_rf(templates_dir)
  end

  it 'escapes </script> in client data so it cannot break out of the data block' do
    File.write(File.join(templates_dir, 'escape.rue'), <<~RUE)
      <schema lang="js-zod" window="appState">
      const schema = z.object({ note: z.string() });
      </schema>

      <template>
      <div>page</div>
      </template>
    RUE

    config = Rhales::Configuration.new do |c|
      c.template_paths = [templates_dir]
    end

    payload = '</script><img src=x onerror=alert(1)>'
    view = Rhales::View.new(nil, client: { note: payload }, config: config)
    html = view.render('escape')

    # The raw breakout sequence must not appear anywhere in the rendered HTML.
    expect(html).not_to include('</script><img')
    expect(html).not_to include('<img src=x onerror=alert(1)>')

    # The escaped data must still round-trip to the original value for the client.
    data_match = html.match(%r{<script[^>]*id="rsfc-data-[^"]+"\s+type="application/json"[^>]*>(.*?)</script>}m)
    expect(data_match).not_to be_nil
    expect(JSON.parse(data_match[1])['note']).to eq(payload)
  end
end
