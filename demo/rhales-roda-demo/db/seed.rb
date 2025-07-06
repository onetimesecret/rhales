require_relative '../app'
require 'bcrypt'

# Access the database through the RhalesDemo class
db = RhalesDemo::DB

# Create demo account using Rodauth's schema
if db[:accounts].where(email: 'demo@example.com').first
  puts 'Demo account already exists: demo@example.com / demo123'
else
  # Insert into accounts table
  account_id = db[:accounts].insert(
    email: 'demo@example.com',
    status: 'verified'  # Skip email verification for demo
  )

  # Insert password hash into separate table
  password_hash = BCrypt::Password.create('demo123')
  db[:account_password_hashes].insert(
    id: account_id,
    password_hash: password_hash
  )

  puts 'Demo account created: demo@example.com / demo123'
end

puts 'Seed data setup completed successfully!'
