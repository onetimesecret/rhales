require_relative 'app'

# Add the lib directory to the load path for middleware
$:.unshift(File.expand_path('../../lib', __dir__))
require 'rhales/middleware/json_responder'

# Enable JSON responses for API clients
# When Accept: application/json header is present, return hydration data as JSON
use Rhales::Middleware::JsonResponder,
  enabled: true,
  include_metadata: ENV['RACK_ENV'] == 'development'

run RhalesDemo.freeze.app
