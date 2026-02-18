module AuthenticationHelpers
  # Realiza un login real via el SessionsController para que la cookie
  # firmada quede correctamente seteada en la sesión Rack::Test.
  def sign_in(user, password: "password123")
    post session_path, params: { email: user.email, password: password }
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end
