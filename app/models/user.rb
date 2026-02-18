# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password validations: false

  has_many :sessions, dependent: :destroy
  has_many :trips, dependent: :destroy
  has_many :tickets, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :provider, presence: true, inclusion: { in: %w[email google apple] }
  validates :password, presence: true, length: { minimum: 8 },
            if: -> { provider == "email" && (new_record? || password.present?) }

  def self.from_omniauth(auth)
    provider_name = normalize_provider(auth.provider)

    user = find_by(provider: provider_name, uid: auth.uid)
    if user
      new_avatar = sanitize_avatar_url(auth.info.image || auth.info.picture)
      user.update!(avatar_url: new_avatar) if new_avatar.present?
      return user
    end

    email = auth.info&.email
    raise "Email requerido para autenticación" if email.blank?

    user = find_or_initialize_by(email: email)
    user.assign_attributes(
      name: auth.info.name.presence || user.name || email.split("@").first,
      provider: provider_name,
      uid: auth.uid,
      avatar_url: sanitize_avatar_url(auth.info.image || auth.info.picture) || user.avatar_url
    )
    user.save!
    user
  end

  def self.normalize_provider(provider)
    case provider
    when "google_oauth2" then "google"
    else provider
    end
  end

  def self.sanitize_avatar_url(url)
    return nil if url.blank?

    uri = URI.parse(url)
    return url if uri.host&.end_with?("googleusercontent.com", "apple.com")

    nil
  rescue URI::InvalidURIError
    nil
  end
end
