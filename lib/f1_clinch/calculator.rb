module F1Clinch
  # パターン(Dのk戦分の着順)に対して、1人のライバルがk戦で取ってよい点の上限
  #   strict_max   : これ以下なら点差だけで確定
  #   tie_max_wins : strict_max+1 点（同点）でも、ライバルのk戦中の優勝数がこれ以下なら確定（nil は同点不可）
  #   physical_max : Dの着順を踏まえてライバルが物理的に取れる最大点
  Allowance = Data.define(:rival, :strict_max, :tie_max_wins, :physical_max, :open_wins) do
    def allows?(gain, wins)
      gain <= strict_max || (!tie_max_wins.nil? && gain == strict_max + 1 && wins <= tie_max_wins)
    end

    def unlimited?
      strict_max >= physical_max
    end

    def tie_usable?
      !unlimited? && !tie_max_wins.nil? && strict_max + 1 <= physical_max
    end

    # 同点の勝利数条件が実質無条件か（ライバルが勝てるレース数以上を許容）
    def tie_unconditional?
      tie_usable? && tie_max_wins >= open_wins
    end

    # 表示用の最大許容点（同点を含む）。nil は 0点でも不可
    def max_gain
      return physical_max if unlimited?

      value = tie_usable? ? strict_max + 1 : strict_max
      value.negative? ? nil : value
    end

    # 同点を除いた最大許容点
    def max_gain_strict
      return physical_max if unlimited?

      strict_max.negative? ? nil : strict_max
    end

    def zero_ok?
      allows?(0, 0)
    end

    # パレート比較用キー（大きいほど緩い）
    def key
      return [physical_max, 0] if unlimited?
      return [strict_max, 0] unless tie_usable?

      [strict_max, 1 + [tie_max_wins, open_wins].min]
    end

    def to_h
      {
        rival: rival.name,
        max_gain: max_gain,
        max_gain_without_tie: max_gain_strict,
        unlimited: unlimited?,
        tie_allowed: tie_usable?,
        tie_requires_rival_wins_at_most: tie_usable? && !tie_unconditional? ? tie_max_wins : nil,
        physical_max: physical_max
      }
    end
  end

  Pattern = Data.define(:driver, :positions, :gain, :wins, :allowances) do
    def feasible?
      allowances.all?(&:zero_ok?)
    end

    def allowance_for(rival_name)
      allowances.find { |a| a.rival.name == rival_name }
    end

    def key
      allowances.map(&:key)
    end

    def labels
      positions.map { |p| PointsSystem.label(p) }
    end
  end

  class Calculator
    attr_reader :season

    def initialize(season)
      @season = season
      @points = season.points
    end

    def n
      season.remaining
    end

    def contenders
      season.drivers.select { |d| Rules.possible?(d, season.leader, n, @points.max_points) }
    end

    def eliminated
      season.drivers - contenders
    end

    def rivals_of(driver)
      season.drivers.reject { |d| d == driver }
    end

    # Dの着順パターン positions (k戦分) に対する各ライバルの許容
    def pattern(driver, positions)
      (@patterns ||= {})[[driver.name, positions.sort]] ||= build_pattern(driver, positions)
    end

    def build_pattern(driver, positions)
      k = positions.size
      remaining = n - k
      gain = positions.sum { |p| @points.points_for(p) }
      kwins = positions.count(1)
      my_points = driver.points + gain
      my_wins = driver.wins + kwins
      physical_max = positions.sum { |p| @points.best_other_points(p) }
      open_wins = k - kwins

      allowances = rivals_of(driver).map do |r|
        strict_max = my_points - r.points - @points.max_points * remaining - 1
        tie_wins = my_wins - r.wins - remaining - 1
        Allowance.new(rival: r, strict_max: strict_max, tie_max_wins: tie_wins.negative? ? nil : tie_wins,
                      physical_max: physical_max, open_wins: open_wins)
      end
      Pattern.new(driver: driver, positions: positions.sort, gain: gain, wins: kwins, allowances: allowances)
    end

    # Dが全勝・ライバル全員0点で確定できる最小のk（無ければ nil）
    def shortest_clinch(driver)
      (1..n).find { |k| pattern(driver, [1] * k).feasible? }
    end

    # k戦分の着順の重複組合せ
    def patterns(driver, k)
      @points.positions.repeated_combination(k).map { |c| pattern(driver, c) }
    end

    # Dの獲得点ごとに、支配されないパターンだけを残す
    def pareto_conditions(driver, k)
      feasible = patterns(driver, k).select(&:feasible?)
      feasible.group_by(&:gain).sort_by { |gain, _| gain }.map do |gain, group|
        uniq = group.group_by(&:key).map { |_, same| same.first }
        front = uniq.reject { |p| uniq.any? { |q| !q.equal?(p) && dominates?(q, p) } }
        [gain, front.sort_by { |p| [-p.wins, p.positions] }]
      end
    end

    def dominates?(a, b)
      a.key.zip(b.key).all? { |x, y| (x <=> y) >= 0 }
    end

    # 条件式による判定: Dの着順とライバルの獲得点・優勝数から確定かどうか
    def clinched_by_condition?(driver, positions, rival_results)
      pat = pattern(driver, positions)
      pat.allowances.all? do |a|
        res = rival_results.fetch(a.rival.name, { gain: 0, wins: 0 })
        a.allows?(res[:gain], res[:wins])
      end
    end

    # 定義どおりの判定
    def clinched_by_definition?(driver, k, results)
      standing = lambda do |d|
        res = results.fetch(d.name, { gain: 0, wins: 0 })
        { points: d.points + res[:gain], wins: d.wins + res[:wins] }
      end
      Rules.clinched?(standing.(driver), rivals_of(driver).map(&standing), n - k, @points.max_points)
    end

    # 首位ドライバーが次戦で確定する条件: 自分の着順 × 各ライバルの許容着順
    def next_race_table(driver, rivals = contenders - [driver])
      @points.positions.map do |my_pos|
        pat = pattern(driver, [my_pos])
        allowed = rivals.to_h do |r|
          a = pat.allowance_for(r.name)
          ok = @points.positions.select do |rp|
            next false if rp == my_pos && rp != PointsSystem::OUT

            a.allows?(@points.points_for(rp), rp == 1 ? 1 : 0)
          end
          [r.name, ok]
        end
        { position: my_pos, gain: pat.gain, possible: pat.feasible?, allowed: allowed }
      end
    end
  end
end
