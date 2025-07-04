require_relative '../app'
require 'bcrypt'

# Create demo account
demo_account = Account.create(
  email: 'demo@example.com',
  password_hash: BCrypt::Password.create('password123'),
  name: 'Demo User'
)

puts "Seed data created successfully!"
puts "Demo account: demo@example.com / password123"
