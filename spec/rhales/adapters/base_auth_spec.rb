# spec/rhales/adapters/base_auth_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable RSpec/MultipleDescribes
RSpec.describe Rhales::Adapters::BaseAuth do
  describe '#anonymous?' do
    it 'raises NotImplementedError' do
      expect { subject.anonymous? }.to raise_error(NotImplementedError)
    end
  end

  describe '#theme_preference' do
    it 'raises NotImplementedError' do
      expect { subject.theme_preference }.to raise_error(NotImplementedError)
    end
  end

  describe '#user_id' do
    it 'returns nil by default' do
      expect(subject.user_id).to be_nil
    end
  end

  describe '#role?' do
    it 'raises NotImplementedError' do
      expect { subject.role? }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe Rhales::Adapters::AnonymousAuth do
  describe '#anonymous?' do
    it 'returns true' do
      expect(subject.anonymous?).to be(true)
    end
  end

  describe '#theme_preference' do
    it 'returns light theme' do
      expect(subject.theme_preference).to eq('light')
    end
  end

  describe '#user_id' do
    it 'returns nil' do
      expect(subject.user_id).to be_nil
    end
  end

  describe '#role?' do
    it 'returns false (regardless of input)' do
      expect(subject.role?).to be(false)
      expect(subject.role?('admin')).to be(false)
      expect(subject.role?('user')).to be(false)
      expect(subject.role?('anonymous')).to be(false)
      expect(subject.role?('anon')).to be(false)
    end
  end

  describe '#display_name' do
    it 'returns Anonymous' do
      expect(subject.display_name).to eq('Anonymous')
    end
  end
end

RSpec.describe Rhales::Adapters::AuthenticatedAuth do
  subject { described_class.new(user_data) }

  let(:user_data) { { id: 123, name: 'John Doe', theme: 'dark', roles: %w[user editor] } }

  describe '#anonymous?' do
    it 'returns false' do
      expect(subject.anonymous?).to be(false)
    end
  end

  describe '#theme_preference' do
    it 'returns user theme' do
      expect(subject.theme_preference).to eq('dark')
    end

    context 'when no theme is set' do
      let(:user_data) { { id: 123 } }

      it 'returns default light theme' do
        expect(subject.theme_preference).to eq('light')
      end
    end
  end

  describe '#user_id' do
    it 'returns user ID' do
      expect(subject.user_id).to eq(123)
    end
  end

  describe '#display_name' do
    it 'returns user name' do
      expect(subject.display_name).to eq('John Doe')
    end
  end

  describe '#role?' do
    it 'returns true for user roles' do
      expect(subject.role?('user')).to be(true)
      expect(subject.role?('editor')).to be(true)
    end

    it 'returns false for roles user does not have' do
      expect(subject.role?('admin')).to be(false)
    end

    it 'handles string and symbol role names' do
      expect(subject.role?(:user)).to be(true)
      expect(subject.role?(:admin)).to be(false)
    end
  end

  describe '#attributes' do
    it 'returns user data' do
      expect(subject.attributes).to eq(user_data)
    end
  end
end
