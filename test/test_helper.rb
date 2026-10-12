require "minitest/autorun"
require_relative "../lib/f1_clinch"

module TestHelper
  DATA = File.expand_path("../data/season.yml", __dir__)

  def season
    @season ||= F1Clinch::Season.load(DATA)
  end

  def calc
    @calc ||= F1Clinch::Calculator.new(season)
  end

  def driver(name)
    season.drivers.find { |d| d.name.end_with?(name) }
  end
end
