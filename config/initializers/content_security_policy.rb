# frozen_string_literal: true

# Content Security Policy - protege contra XSS y carga de recursos no autorizados
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

  # Empezar en modo report-only para no romper funcionalidad existente
  config.content_security_policy_report_only = true
end
