require_relative "test_helper"

# 検算値（手計算）との突き合わせ
class CalculatorTest < Minitest::Test
  include TestHelper

  def test_shortest_clinch
    assert_equal 1, calc.shortest_clinch(driver("Antonelli"))
    %w[Russell Hamilton Verstappen Leclerc Norris].each do |name|
      assert_equal 6, calc.shortest_clinch(driver(name)), name
    end
    assert_nil calc.shortest_clinch(driver("Piastri"))
  end

  # Antonelli: (獲得点 − ライバル獲得点) の必要値
  def test_antonelli_margins
    result = F1Clinch::Analysis.new(season, calc).to_h
    margins = result[:drivers].first[:margins].to_h { |m| [m[:rival].split.last, m[:required_diff]] }
    assert_equal({ "Russell" => 24, "Hamilton" => 15, "Verstappen" => 7, "Leclerc" => 1, "Norris" => -13 },
                 margins.slice("Russell", "Hamilton", "Verstappen", "Leclerc", "Norris"))
  end

  # 同点時の優勝数判定で1点緩む: Antonelli 優勝なら Russell 2点(P9)でも確定
  def test_antonelli_tie_relaxation
    pat = calc.pattern(driver("Antonelli"), [1])
    russell = pat.allowance_for("George Russell")
    assert russell.allows?(2, 0)
    refute russell.allows?(4, 0)
    assert_equal 1, russell.max_gain_strict
    assert_equal 2, russell.max_gain
  end

  def test_antonelli_must_win_austin
    assert calc.pattern(driver("Antonelli"), [1]).feasible?
    (2..11).each { |p| refute calc.pattern(driver("Antonelli"), [p]).feasible?, "P#{p}" }
  end

  # 6戦全勝時に Antonelli に許される6戦合計の最大点（同点を除く）
  def test_all_wins_allowance_for_antonelli
    expected = { "Russell" => 47, "Hamilton" => 38, "Verstappen" => 30, "Leclerc" => 24, "Norris" => 10 }
    expected.each do |name, max|
      a = calc.pattern(driver(name), [1] * 6).allowance_for("Kimi Antonelli")
      assert_equal max, a.max_gain_strict, name
    end
  end

  # 同点処理: Russell は同点(48)でも優勝数 9 > 8 で確定、Verstappen は同点(31)だと優勝数8=8で未確定
  def test_all_wins_tie_handling
    assert_equal 48, calc.pattern(driver("Russell"), [1] * 6).allowance_for("Kimi Antonelli").max_gain
    assert_equal 30, calc.pattern(driver("Verstappen"), [1] * 6).allowance_for("Kimi Antonelli").max_gain
    assert_equal 10, calc.pattern(driver("Norris"), [1] * 6).allowance_for("Kimi Antonelli").max_gain
  end

  def test_physical_cap_when_driver_wins
    a = calc.pattern(driver("Antonelli"), [1]).allowance_for("Max Verstappen")
    assert_equal 18, a.physical_max
    assert a.unlimited?
  end

  def test_pareto_minimum_gain
    gain, pats = calc.pareto_conditions(driver("Russell"), 6).first
    assert_equal 103, gain # 238+103 = 341 > 340
    assert(pats.all?(&:feasible?))
  end

  def test_leader_next_race_table
    rows = calc.next_race_table(season.leader)
    p1 = rows.first
    assert p1[:possible]
    assert_equal 9, p1[:allowed]["George Russell"].min
    assert_equal 5, p1[:allowed]["Lewis Hamilton"].min
    assert_equal 2, p1[:allowed]["Max Verstappen"].min
    rows.drop(1).each { |r| refute r[:possible] }
  end
end
