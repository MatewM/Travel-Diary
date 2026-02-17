# frozen_string_literal: true

class User < ApplicationRecord
  has_many :identities, dependent: :destroy
  has_many :trips, dependent: :destroy

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:google_oauth2, :apple]

  validates :email, presence: true, uniqueness: true

  def self.from_omniauth(auth)
    provider = normalize_provider(auth.provider)
    identity = Identity.find_by(provider: provider, uid: auth.uid)
    return identity.user if identity

    email = auth.info&.email
    raise ActiveRecord::RecordInvalid, "Email requerido para autenticación" if email.blank?

    user = find_or_initialize_by(email:)
    user.assign_attributes(
      name: auth.info.name.presence || user.name,
      avatar_url: sanitize_avatar_url(auth.info.image || auth.info.picture) || user.avatar_url
    )
    user.password = Devise.friendly_token[0, 20] if user.new_record? && user.encrypted_password.blank?
    user.save!

    user.identities.create!(
      provider: provider,
      uid: auth.uid,
      token: auth.credentials&.token,
      refresh_token: auth.credentials&.refresh_token,
      expires_at: auth.credentials&.expires_at ? Time.at(auth.credentials.expires_at) : nil
    )
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

  def password_required?
    super && identities.where(provider: "email").exists?
  end
end
