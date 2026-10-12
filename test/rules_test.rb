require_relative "test_helper"

class PointsTest < Minitest::Test
  include TestHelper

  def test_race_points
    pts = season.points
    assert_equal [25, 18, 15, 12, 10, 8, 6, 4, 2, 1, 0], pts.positions.map { |p| pts.points_for(p) }
    assert_equal 25, pts.max_points
  end

  def test_best_other_points
    assert_equal 18, season.points.best_other_points(1)
    assert_equal 25, season.points.best_other_points(2)
    assert_equal 25, season.points.best_other_points(F1Clinch::PointsSystem::OUT)
  end

  def test_season_data_is_loaded_from_yaml
    assert_equal 6, season.remaining
    assert_equal "アメリカGP", season.races.first.name
    assert_equal "アブダビGP", season.races.last.name
    assert_equal 19, season.drivers.size
    assert_equal "Kimi Antonelli", season.leader.name
  end
end

class TieTest < Minitest::Test
  def test_points_decide_first
    assert_equal 1, F1Clinch::Rules.compare(100, 0, 99, 9)
    assert_equal(-1, F1Clinch::Rules.compare(99, 9, 100, 0))
  end

  def test_wins_break_tie
    assert_equal 1, F1Clinch::Rules.compare(100, 3, 100, 2)
    assert_equal(-1, F1Clinch::Rules.compare(100, 2, 100, 3))
  end

  def test_same_points_and_wins_is_undetermined
    assert_equal 0, F1Clinch::Rules.compare(100, 2, 100, 2)
  end
end

class PossibilityTest < Minitest::Test
  include TestHelper

  def test_contenders
    assert_equal ["Kimi Antonelli", "George Russell", "Lewis Hamilton", "Max Verstappen", "Charles Leclerc",
                  "Lando Norris"], calc.contenders.map(&:name)
  end

  def test_piastri_is_out
    refute F1Clinch::Rules.possible?(driver("Piastri"), season.leader, 6, 25) # 138+150=288 < 340
  end

  def test_tie_with_leader_uses_wins
    leader = F1Clinch::Driver.new(position: 1, name: "L", team: "T", points: 200, wins: 3)
    more = F1Clinch::Driver.new(position: 2, name: "A", team: "T", points: 50, wins: 0)   # 200, 6勝
    fewer = F1Clinch::Driver.new(position: 3, name: "B", team: "T", points: 50, wins: 0)
    assert F1Clinch::Rules.possible?(more, leader, 6, 25)
    refute F1Clinch::Rules.possible?(fewer, leader, 5, 25) # 175 < 200
    same = F1Clinch::Driver.new(position: 2, name: "C", team: "T", points: 50, wins: 0)
    leader9 = F1Clinch::Driver.new(position: 1, name: "L", team: "T", points: 200, wins: 6)
    assert F1Clinch::Rules.possible?(same, leader9, 6, 25), "点も優勝数も同じ=未確定は可能性ありに残す"
    leader10 = F1Clinch::Driver.new(position: 1, name: "L", team: "T", points: 200, wins: 7)
    refute F1Clinch::Rules.possible?(same, leader10, 6, 25)
  end
end

class ClinchTest < Minitest::Test
  def clinched?(*args) = F1Clinch::Rules.clinched_against?(*args, 25)

  def test_strictly_ahead
    assert clinched?(365, 0, 238, 3, 5)  # 365 > 238+125=363
    refute clinched?(362, 9, 238, 3, 5)
  end

  def test_equal_with_more_wins
    assert clinched?(363, 9, 238, 3, 5)  # 等号 363 = 238+125, 9 > 3+5
    refute clinched?(363, 8, 238, 3, 5)  # 等号, 8 = 3+5 → 未確定
    refute clinched?(363, 7, 238, 3, 5)
  end

  def test_final_race
    assert clinched?(388, 9, 388, 8, 0)
    refute clinched?(388, 8, 388, 8, 0)
    refute clinched?(387, 9, 388, 0, 0)
  end
end
