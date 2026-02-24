class DashboardPresenter
  def self.call(user, year)
    new(user, year).call
  end

  def initialize(user, year)
    @user = user
    @year = year
  end

  def call
    rows = GapDetectorService.call(@user, @year)

    total_days_by_country = calculate_total_days_by_country(rows)

    {
      rows: rows,
      total_days_by_country: total_days_by_country,
      alerts: [] # Por ahora vacío, se implementará después
    }
  end

  private

  def calculate_total_days_by_country(rows)
    rows
      .select { |row| row[:type].in?([:trip, :inherited_trip]) }
      .group_by { |row| row[:country] }
      .transform_values { |country_rows| country_rows.sum { |row| row[:days].to_i } }
  end
end
