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

  # Renderiza un icono de bandera circular para un País.
  # Carga un asset SVG desde app/assets/images/flags/{code}.svg
  # Si el asset no existe, renderiza un emoji como fallback.
  def country_flag_icon(country, size: "w-10 h-10")
    return nil if country.blank?

    flag_code = country.code.downcase
    flag_path = "flags/#{flag_code}.svg"

    image_tag(
      flag_path,
      alt: country.name,
      class: "#{size} rounded-full object-cover shadow-sm flex-shrink-0",
      title: country.name
    )
  end
end
