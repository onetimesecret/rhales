require_relative '../app'
require 'bcrypt'

# Access the database through the RhalesDemo class
db = RhalesDemo::DB

# Create demo account (if it doesn't already exist)
if db[:accounts].where(email: 'demo@example.com').first
  puts 'Demo account already exists: demo@example.com / demo123'
else
  password_hash = BCrypt::Password.create('demo123')
  db[:accounts].insert(
    email: 'demo@example.com',
    password_hash: password_hash,
  )
  puts 'Demo account created: demo@example.com / demo123'
end

puts 'Seed data setup completed successfully!'
