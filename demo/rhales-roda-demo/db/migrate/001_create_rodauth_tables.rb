# Rodauth migration for basic authentication tables
Sequel.migration do
  up do
    # Main accounts table
    create_table(:accounts) do
      primary_key :id, type: :Bignum
      String :email, null: false
      String :status, null: false, default: 'unverified'

      index :email, unique: true

      # Timestamps
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Password hashes stored separately for security
    create_table(:account_password_hashes) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :password_hash, null: false

      # For password history/rotation features if needed later
      DateTime :changed_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # For remember me functionality (optional but common)
    create_table(:account_remember_keys) do
      foreign_key :account_id, :accounts, type: :Bignum
      String :key, null: false
      DateTime :deadline, null: false

      primary_key [:account_id, :key]
    end
  end

  down do
    drop_table(:account_remember_keys)
    drop_table(:account_password_hashes)
    drop_table(:accounts)
  end
end
