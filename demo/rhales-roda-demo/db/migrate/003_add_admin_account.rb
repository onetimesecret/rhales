# demo/rhales-roda-demo/db/migrate/003_add_admin_account.rb
#
# frozen_string_literal: true

require 'bcrypt'

Sequel.migration do
  up do
    # Ensure secrets table exists and get/create HMAC secret
    #
    # For the convenience of demo use only. Don't do this in production. It
    # allows for consistent secret to be used between app restarts without
    # having to manually generate and specify an environment variable.
    create_table(:_demo_secrets) do
      primary_key :id
      String :name, unique: true, null: false
      String :value, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Create demo account
    unless from(:accounts).where(email: 'demo@example.com').first
      demo_account_id = from(:accounts).insert(
        email: 'demo@example.com',
        status_id: 2,  # Verified status
      )

      demo_password_hash = BCrypt::Password.create('demo123')
      from(:account_password_hashes).insert(
        id: demo_account_id,
        password_hash: demo_password_hash,
      )
    end

    # Create admin account
    unless from(:accounts).where(email: 'admin@example.com').first
      admin_account_id = from(:accounts).insert(
        email: 'admin@example.com',
        status_id: 2,  # Verified status
      )

      admin_password_hash = BCrypt::Password.create('admin123')
      from(:account_password_hashes).insert(
        id: admin_account_id,
        password_hash: admin_password_hash,
      )
    end
  end

  down do
    p '[demo] Removing the following secrets:'
    p from(:_demo_secrets)

    drop_table(:_demo_secrets)

    # Remove admin account and password hash
    if admin_account = from(:accounts).where(email: 'admin@example.com').first
      from(:account_password_hashes).where(id: admin_account[:id]).delete
      from(:accounts).where(id: admin_account[:id]).delete
    end

    # Remove demo account and password hash
    if demo_account = from(:accounts).where(email: 'demo@example.com').first
      from(:account_password_hashes).where(id: demo_account[:id]).delete
      from(:accounts).where(id: demo_account[:id]).delete
    end
  end
end
