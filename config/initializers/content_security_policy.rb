Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, "https://lh3.googleusercontent.com", "https://*.googleusercontent.com"
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.connect_src :self
    policy.frame_src   :none
    policy.base_uri    :self
    policy.form_action :self, "https://accounts.google.com", "https://appleid.apple.com"
  end

  # IMPORTANTE: usar nonce para permitir scripts inline de Rails/Importmap/Turbo
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # report_only = false para que la política sea activa (no solo logging)
  # config.content_security_policy_report_only = true  ← COMENTADA
end
