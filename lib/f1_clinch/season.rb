require "yaml"

module F1Clinch
  Driver = Data.define(:position, :name, :team, :points, :wins)
  Race = Data.define(:round, :name, :location, :date)

  # 決勝のポイント制度。着順は 1..10 と OUT(=11, 11位以下) で表す
  class PointsSystem
    OUT = 11

    attr_reader :table

    def initialize(table)
      @table = table.dup.freeze
    end

    def positions
      (1..OUT).to_a
    end

    def points_for(position)
      return 0 if position == OUT || position > @table.size

      @table.fetch(position - 1)
    end

    def max_points
      @table.first
    end

    # 自分以外が取れる最高点（自分が優勝したら2位の点）
    def best_other_points(my_position)
      my_position == 1 ? @table[1] : @table[0]
    end

    def self.label(position)
      position == OUT ? "圏外" : "P#{position}"
    end
  end

  class Season
    attr_reader :year, :as_of, :drivers, :races, :points, :assumptions

    def self.load(path)
      new(YAML.load_file(path))
    end

    def initialize(data)
      @year = data.fetch("season")
      @as_of = data.fetch("as_of")
      @drivers = data.fetch("standings").map do |row|
        Driver.new(position: row.fetch("position"), name: row.fetch("driver"), team: row.fetch("team"),
                   points: row.fetch("points"), wins: row.fetch("wins"))
      end.sort_by(&:position)
      @races = data.fetch("remaining_races").map do |row|
        Race.new(round: row.fetch("round"), name: row.fetch("name"), location: row.fetch("location"),
                 date: row.fetch("date"))
      end.sort_by(&:round)
      @points = PointsSystem.new(data.fetch("points_system").fetch("race"))
      @assumptions = data.fetch("assumptions", [])
    end

    def remaining
      @races.size
    end

    def leader
      @drivers.first
    end

    def driver(name)
      @drivers.find { |d| d.name == name } or raise ArgumentError, "unknown driver: #{name}"
    end
  end
end
