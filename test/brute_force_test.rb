require_relative "test_helper"

# 定義どおりの判定（Rules.clinched?）と条件式による判定（許容点の表）が一致することを総当たりで確認する
class BruteForceTest < Minitest::Test
  include TestHelper

  OUT = F1Clinch::PointsSystem::OUT

  # 1レース分: count 人に着順を割り当てる全通り（P1..P10 は重複不可、圏外は重複可）
  def race_outcomes(count)
    @race_outcomes ||= {}
    @race_outcomes[count] ||= begin
      list = []
      walk = lambda do |acc, used|
        if acc.size == count
          list << acc.dup
          next
        end
        (1..OUT).each do |p|
          next if p != OUT && used[p]

          used[p] = true if p != OUT
          acc << p
          walk.(acc, used)
          acc.pop
          used[p] = false if p != OUT
        end
      end
      walk.([], {})
      list
    end
  end

  def results_for(drivers, races)
    pts = season.points
    drivers.each_with_index.to_h do |d, i|
      positions = races.map { |race| race[i] }
      [d.name, { gain: positions.sum { |p| pts.points_for(p) }, wins: positions.count(1), positions: positions }]
    end
  end

  def check(drivers, races, k, tally)
    results = results_for(drivers, races)
    drivers.each do |d|
      by_def = calc.clinched_by_definition?(d, k, results)
      by_cond = calc.clinched_by_condition?(d, results[d.name][:positions], results)
      assert_equal by_def, by_cond, "#{d.name} k=#{k} #{results.transform_values { |v| v[:positions] }}"
      tally[d.name] += 1 if by_def
    end
  end

  # k=1: 可能性ありの6人の着順を全列挙（424,051通り）
  def test_k1_all_six_drivers
    drivers = calc.contenders
    outcomes = race_outcomes(drivers.size)
    assert_equal 424_051, outcomes.size
    tally = Hash.new(0)
    outcomes.each { |race| check(drivers, [race], 1, tally) }

    assert_operator tally["Kimi Antonelli"], :>, 0
    assert_equal ["Kimi Antonelli"], tally.keys
  end

  # k=2: 6人の同時全列挙は 424,051^2 ≈ 1.8×10^11 通りで現実的でないため、
  # 確定判定がライバルごとの条件の AND に分解できることを利用し、
  # (D, ライバル) の全ペアについて2戦分の着順を全列挙する（111^2 = 12,321 通り × 30ペア）
  def test_k2_all_pairs
    tally = Hash.new(0)
    calc.contenders.permutation(2) do |pair|
      outcomes = race_outcomes(2)
      outcomes.product(outcomes) { |r1, r2| check(pair, [r1, r2], 2, tally) }
    end
    assert_operator tally["Kimi Antonelli"], :>, 0
    assert_equal ["Kimi Antonelli"], tally.keys
  end

  # k=2: 6人同時のランダム標本（固定シード）でも一致を確認
  def test_k2_six_drivers_sample
    drivers = calc.contenders
    outcomes = race_outcomes(drivers.size)
    rng = Random.new(2026)
    tally = Hash.new(0)
    50_000.times { check(drivers, [outcomes.sample(random: rng), outcomes.sample(random: rng)], 2, tally) }
    # Antonelli が両戦優勝する結果も必ず含めて確認する
    wins = outcomes.select { |o| o[0] == 1 }
    5_000.times { check(drivers, [wins.sample(random: rng), wins.sample(random: rng)], 2, tally) }
    assert_operator tally["Kimi Antonelli"], :>, 0
  end
end
