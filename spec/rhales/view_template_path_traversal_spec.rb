# spec/rhales/view_template_path_traversal_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Template names can reach Rhales::View from request-facing code (notably
# HydrationEndpoint, which is designed to be wired to an API route). A name
# derived from request input must never be able to escape the configured
# template directories and read arbitrary files off disk.
RSpec.describe 'Rhales::View template name path-traversal protection' do
  let(:view) { Rhales::View.new(nil) }

  def resolve(name)
    view.send(:resolve_template_path, name)
  end

  describe 'rejecting unsafe template names' do
    unsafe_names = [
      '../secrets',
      '../../etc/passwd',
      'web/../../../etc/passwd',
      'web/../../config/database',
      '..\\..\\windows\\system32\\config',
      '/etc/passwd',
      'C:\\Windows\\System32',
      '..',
    ]

    unsafe_names.each do |bad_name|
      it "raises TemplateNotFoundError for #{bad_name.inspect}" do
        expect { resolve(bad_name) }
          .to raise_error(Rhales::View::TemplateNotFoundError, /Unsafe template name|Invalid template name/)
      end
    end

    it 'rejects names containing an embedded null byte' do
      expect { resolve("web/#{0.chr}passwd") }
        .to raise_error(Rhales::View::TemplateNotFoundError, /Unsafe template name/)
    end

    it 'rejects before any filesystem lookup occurs' do
      # The validation guard raises with the "Unsafe" message; the not-found
      # path (which only fires after File.exist? checks) uses a different one.
      expect { resolve('../../etc/passwd') }
        .to raise_error(Rhales::View::TemplateNotFoundError, /Unsafe template name/)
    end

    it 'rejects nil and empty names' do
      expect { resolve(nil) }.to raise_error(Rhales::View::TemplateNotFoundError, /Invalid template name/)
      expect { resolve('') }.to raise_error(Rhales::View::TemplateNotFoundError, /Invalid template name/)
    end
  end

  describe 'accepting legitimate template names' do
    safe_names = %w[
      homepage
      web/homepage
      layouts/main
      partials/header
      a_b-c/d.e
      deeply/nested/path/template
    ]

    safe_names.each do |good_name|
      it "resolves #{good_name.inspect} to a .rue path" do
        expect { resolve(good_name) }.not_to raise_error
        expect(resolve(good_name)).to end_with("#{good_name}.rue")
      end
    end
  end
end
