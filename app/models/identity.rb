# frozen_string_literal: true

class Identity < ApplicationRecord
  belongs_to :user

  encrypts :token
  encrypts :refresh_token

  validates :provider, presence: true, inclusion: { in: %w[google apple email] }
  validates :uid, presence: true
  validates :uid, uniqueness: { scope: :provider }
end
