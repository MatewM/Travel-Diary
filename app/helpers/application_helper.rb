module ApplicationHelper
  # Convierte un código ISO 3166-1 alpha-2 (ej: "ES", "CY") en el emoji de bandera correspondiente.
  # Cuando trip.country sea un objeto con .code (fase futura), usar: flag_emoji(trip.country.code)
  # Por ahora trip.country es un string libre — si no es un código de 2 letras retorna 🌍.
  def flag_emoji(country_code)
    return "🌍" if country_code.blank?
    code = country_code.to_s.strip.upcase
    return "🌍" unless code.match?(/\A[A-Z]{2}\z/)
    code.chars.map { |c| (0x1F1E6 + (c.ord - "A".ord)).chr(Encoding::UTF_8) }.join
  end
end
