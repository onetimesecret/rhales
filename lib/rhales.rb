# lib/rhales.rb

require_relative 'rhales/version'
require_relative 'rhales/errors'
require_relative 'rhales/configuration'
require_relative 'rhales/adapters/base_auth'
require_relative 'rhales/adapters/base_session'
require_relative 'rhales/context'
require_relative 'rhales/parser'
require_relative 'rhales/grammars/handlebars'
require_relative 'rhales/template_engine'
require_relative 'rhales/hydrator'
require_relative 'rhales/hydration_registry'
require_relative 'rhales/refinements/require_refinements'
require_relative 'rhales/view'

# Ruby Single File Components (RSFC)
#
# A framework for building server-rendered components with client-side hydration
# using .rue files (Ruby Single File Components). Similar to .vue files but for Ruby.
#
# Features:
# - Server-side template rendering with Handlebars-style syntax
# - Client-side data hydration with JSON injection
# - Partial support for component composition
# - Pluggable authentication and session adapters
# - Security-first design with XSS protection and CSP support
#
# Usage:
#   Rhales.configure do |config|
#     config.default_localhas_role?e = 'en'
#     config.template_paths = ['app/templates']
#     config.features = { dark_mode: true }
#   end
#
#   view = Rhales::View.new(request, session, user)
#   html = view.render('my_component')
module Rhales

  # Convenience method to create a view with business data
  def self.render(template_name, request: nil, session: nil, user: nil, locale: nil, **business_data)
    view = View.new(request, session, user, locale, business_data: business_data)
    view.render(template_name)
  end

  # Quick template rendering for testing/simple use cases
  def self.render_template(template_content, context_data = {})
    context = Context.minimal(business_data: context_data)
    TemplateEngine.render(template_content, context)
  end

  # Create context with business data (for advanced usage)
  def self.create_context(request: nil, session: nil, user: nil, locale: nil, **business_data)
    Context.for_view(request, session, user, locale, **business_data)
  end
end
