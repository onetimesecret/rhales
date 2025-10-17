require 'spec_helper'
require 'fileutils'

RSpec.describe 'app_data parameter' do
  let(:templates_dir) { File.join(__dir__, '../../fixtures/templates/app_data_test') }

  before do
    FileUtils.mkdir_p(templates_dir)
  end

  after do
    FileUtils.rm_rf(templates_dir)
  end

  it 'makes app_data available in templates but not in window state' do
    # Create test template
    File.write(File.join(templates_dir, 'test.rue'), <<~RUE)
      <schema lang="js-zod" window="appState">
      const schema = z.object({
        user: z.string()
      });
      </schema>

      <template>
      <div>
        <h1>{{user}}</h1>
        <p>{{page_title}}</p>
        <div>{{{html_content}}}</div>
      </div>
      </template>
    RUE

    config = Rhales::Configuration.new do |c|
      c.template_paths = [templates_dir]
    end

    view = Rhales::View.new(
      nil, nil, nil, 'en',
      props: { user: 'Alice' },
      app_data: {
        page_title: 'Test Page',
        html_content: '<span>HTML</span>'
      },
      config: config
    )

    html = view.render('test')

    # Template should render both props and app_data
    expect(html).to include('<h1>Alice</h1>')
    expect(html).to include('<p>Test Page</p>')
    expect(html).to include('<span>HTML</span>')

    # Window state should ONLY contain props
    data_match = html.match(/<script id="rsfc-data-[^"]+"\s+type="application\/json"[^>]*>(.*?)<\/script>/m)
    expect(data_match).not_to be_nil

    json_data = JSON.parse(data_match[1])
    expect(json_data['user']).to eq('Alice')
    expect(json_data).not_to have_key('page_title')
    expect(json_data).not_to have_key('html_content')
  end

  it 'allows props and app_data to have overlapping keys (props win)' do
    File.write(File.join(templates_dir, 'overlap.rue'), <<~RUE)
      <schema lang="js-zod" window="data">
      const schema = z.object({
        title: z.string()
      });
      </schema>

      <template>
      <h1>{{title}}</h1>
      </template>
    RUE

    config = Rhales::Configuration.new do |c|
      c.template_paths = [templates_dir]
    end

    view = Rhales::View.new(
      nil, nil, nil, 'en',
      props: { title: 'From Props' },
      app_data: { title: 'From AppData' },
      config: config
    )

    html = view.render('overlap')
    expect(html).to include('From Props')
  end

  it 'works with Context.for_view factory method' do
    File.write(File.join(templates_dir, 'factory.rue'), <<~RUE)
      <schema lang="js-zod" window="state">
      const schema = z.object({
        data: z.string()
      });
      </schema>

      <template>
      <div>
        <span>{{data}}</span>
        <em>{{helper}}</em>
      </div>
      </template>
    RUE

    config = Rhales::Configuration.new do |c|
      c.template_paths = [templates_dir]
    end

    context = Rhales::Context.for_view(
      nil, nil, nil, 'en',
      props: { data: 'Important' },
      app_data: { helper: 'Template Only' },
      config: config
    )

    # Verify both are accessible in context
    expect(context.get('data')).to eq('Important')
    expect(context.get('helper')).to eq('Template Only')

    # Verify only props are in props
    expect(context.props).to eq({ 'data' => 'Important' })
  end

  it 'works with Context.minimal for testing' do
    config = Rhales::Configuration.new

    context = Rhales::Context.minimal(
      props: { test: 'value' },
      app_data: { template: 'only' },
      config: config
    )

    expect(context.get('test')).to eq('value')
    expect(context.get('template')).to eq('only')
    expect(context.props).to eq({ 'test' => 'value' })
  end

  it 'preserves app_data through layout rendering' do
    # Create layout template
    File.write(File.join(templates_dir, 'with_layout.rue'), <<~RUE)
      <schema lang="js-zod" window="pageData" layout="simple_layout">
      const schema = z.object({
        username: z.string()
      });
      </schema>

      <template>
      <main>
        <h2>{{page_subtitle}}</h2>
        <p>User: {{username}}</p>
      </main>
      </template>
    RUE

    # Create layout
    File.write(File.join(templates_dir, 'simple_layout.rue'), <<~RUE)
      <template>
      <html>
      <head><title>{{site_title}}</title></head>
      <body>
        {{{content}}}
      </body>
      </html>
      </template>
    RUE

    config = Rhales::Configuration.new do |c|
      c.template_paths = [templates_dir]
    end

    view = Rhales::View.new(
      nil, nil, nil, 'en',
      props: { username: 'Bob' },
      app_data: {
        site_title: 'My Site',
        page_subtitle: 'Welcome'
      },
      config: config
    )

    html = view.render('with_layout')

    # Both layout and content should access app_data
    expect(html).to include('<title>My Site</title>')
    expect(html).to include('<h2>Welcome</h2>')
    expect(html).to include('<p>User: Bob</p>')

    # Window state should only have props
    data_match = html.match(/<script id="rsfc-data-[^"]+"\s+type="application\/json"[^>]*>(.*?)<\/script>/m)
    expect(data_match).not_to be_nil

    json_data = JSON.parse(data_match[1])
    expect(json_data['username']).to eq('Bob')
    expect(json_data).not_to have_key('site_title')
    expect(json_data).not_to have_key('page_subtitle')
  end

  it 'handles empty app_data gracefully' do
    File.write(File.join(templates_dir, 'empty_app.rue'), <<~RUE)
      <schema lang="js-zod" window="data">
      const schema = z.object({
        value: z.string()
      });
      </schema>

      <template>
      <div>{{value}}</div>
      </template>
    RUE

    config = Rhales::Configuration.new do |c|
      c.template_paths = [templates_dir]
    end

    view = Rhales::View.new(
      nil, nil, nil, 'en',
      props: { value: 'test' },
      app_data: {},  # Empty app_data
      config: config
    )

    html = view.render('empty_app')
    expect(html).to include('<div>test</div>')
  end
end
