require_relative '../app'
require 'bcrypt'

# Create demo accounts
demo_account = Account.create(
  email: 'demo@example.com',
  password_hash: BCrypt::Password.create('password123'),
  name: 'Demo User'
)

user_account = Account.create(
  email: 'user@example.com',
  password_hash: BCrypt::Password.create('userpass'),
  name: 'Test User'
)

# Create sample posts for demo account
Post.create(
  account_id: demo_account.id,
  title: 'Welcome to Rhales RSFC',
  content: 'This demo showcases Ruby Single File Components with secure client-side hydration.',
  status: 'published'
)

Post.create(
  account_id: demo_account.id,
  title: 'Understanding RSFC Templates',
  content: 'RSFC templates combine data, template, and logic sections in a single .rue file.',
  status: 'published'
)

Post.create(
  account_id: demo_account.id,
  title: 'Draft: Advanced Rhales Features',
  content: 'Coming soon: WebSocket support, real-time updates, and more!',
  status: 'draft'
)

puts "Seed data created successfully!"
puts "Demo accounts:"
puts "  - demo@example.com / password123"
puts "  - user@example.com / userpass"
