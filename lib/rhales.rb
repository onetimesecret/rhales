# lib/rhales.rb

# Core framework files
require_relative 'rhales/version'
require_relative 'rhales/configuration'
require_relative 'rhales/errors'

# Security
require_relative 'rhales/security/csp'

# Load components in dependency order
require_relative 'rhales/adapters'
require_relative 'rhales/parsers'
require_relative 'rhales/utils'
require_relative 'rhales/core'
require_relative 'rhales/hydration'
require_relative 'rhales/integrations'
require_relative 'rhales/middleware'

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
# Modular Loading:
#   require 'rhales'           # Loads everything (default)
#   require 'rhales/core'      # Core engine only
#   require 'rhales/hydration' # Hydration system only
#   require 'rhales/parsers'   # Template parsers only
#   require 'rhales/utils'     # Utilities only
#   require 'rhales/all'       # Explicit full load
#
# Usage:
#   Rhales.configure do |config|
#     config.default_locale = 'en'
#     config.template_paths = ['app/templates']
#     config.features = { dark_mode: true }
#
#     # Hydration configuration
#     config.hydration.injection_strategy = :early  # :early or :late (default)
#     config.hydration.mount_point_selectors = ['#app', '#root', '[data-mount]']
#     config.hydration.fallback_to_late = true
#   end
#
#   view = Rhales::View.new(request)
#   html = view.render('my_component')
module Rhales
  # Convenience method to create a view with props
  def self.render(template_name, request: nil, locale: nil, **props)
    view = View.new(request, locale, props: props)
    view.render(template_name)
  end

  # Quick template rendering for testing/simple use cases
  def self.render_template(template_content, context_data = {})
    context = Context.minimal(props: context_data)
    TemplateEngine.render(template_content, context)
  end

  # Create context with props (for advanced usage)
  def self.create_context(request: nil, locale: nil, **props)
    Context.for_view(request, locale, **props)
  end
end
