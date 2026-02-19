# frozen_string_literal: true

# Gemini API configuration.
# Model note: using gemini-2.5-flash (250 req/day, ~88.69% accuracy).
# When scaling to production, switch to gemini-2.5-flash-lite (1000 req/day)
# by changing GEMINI_MODEL below.
module Gemini
  BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
  MODEL     = "gemini-2.0-flash-exp"
  TIMEOUT   = 30
end
