module F1Clinch
  # 計算結果をレポート用のハッシュにまとめる（result.json と report.md の共通ソース）
  class Analysis
    def initialize(season, calculator = Calculator.new(season))
      @season = season
      @calc = calculator
    end

    def to_h
      @to_h ||= {
        season: @season.year,
        as_of: @season.as_of,
        remaining_races: @season.races.map(&:to_h),
        points_system: { race: @season.points.table, out_of_points: 0 },
        contenders: @calc.contenders.map(&:name),
        drivers: @calc.contenders.map { |d| driver_result(d) },
        eliminated: @calc.eliminated.map { |d| eliminated_result(d) },
        leader_next_race: leader_table,
        assumptions: @season.assumptions + definitions
      }
    end

    def definitions
      [
        "k戦後に確定 = 残り N-k 戦がどんな結果でも全ライバルに逆転されない状態。" \
        "ライバルRごとに「自分の点 > Rの点 + 25×(N-k)」または「等号かつ 自分の優勝数 > Rの優勝数 + (N-k)」",
        "可能性あり = 現在の点 + 25×N が首位の現在の点以上（同点は優勝数で判定、優勝数も同じなら未確定として可能性ありに残す）",
        "最短確定レース = Dが全勝しライバル全員0点という最良ケースで確定できる最小のk",
        "ライバルの許容点は、Dの着順を踏まえて物理的に取れる最大点（Dが勝ったレースは18点）で頭打ちにする。" \
        "これ以上取れない場合は「制限なし」",
        "他のライバル同士の着順の衝突（2人のライバルが同じ順位を取れない）は条件を緩める方向にしか働かないため、" \
        "条件は各ライバル独立の上限として表す"
      ]
    end

    private

    def driver_result(driver)
      k = @calc.shortest_clinch(driver)
      return { driver: driver.name, team: driver.team, points: driver.points, wins: driver.wins, clinch_race: nil } unless k

      race = @season.races[k - 1]
      conditions = @calc.pareto_conditions(driver, k)
      min_gain, min_patterns = conditions.first
      all_win = @calc.pattern(driver, [1] * k)
      remaining = @season.remaining - k

      {
        driver: driver.name,
        team: driver.team,
        points: driver.points,
        wins: driver.wins,
        clinch_after_races: k,
        clinch_race: race.to_h,
        races_left_after_clinch: remaining,
        margins: margins(driver, k),
        minimum: {
          gain: min_gain,
          example_positions: min_patterns.first.labels,
          allowances: min_patterns.first.allowances.map(&:to_h)
        },
        all_wins: {
          positions: all_win.labels,
          gain: all_win.gain,
          allowances: all_win.allowances.map(&:to_h)
        },
        conditions: conditions.flat_map do |gain, pats|
          pats.map do |p|
            { gain: gain, wins: p.wins, positions: p.labels, allowances: p.allowances.map(&:to_h) }
          end
        end
      }
    end

    # 条件式: (Dの獲得点 − Rの獲得点) >= required_diff。同点時は優勝数条件付きで1点緩む
    def margins(driver, k)
      remaining = @season.remaining - k
      max = @season.points.max_points
      @calc.rivals_of(driver).map do |r|
        diff = r.points + max * remaining + 1 - driver.points
        {
          rival: r.name,
          required_diff: diff,
          tie_diff: diff - 1,
          tie_condition: "#{driver.name}の優勝数(#{driver.wins}+#{k}戦中の勝利数) > " \
                         "#{r.name}の優勝数(#{r.wins}+#{k}戦中の勝利数) + #{remaining}"
        }
      end
    end

    def eliminated_result(driver)
      max = driver.points + @season.points.max_points * @season.remaining
      { driver: driver.name, team: driver.team, points: driver.points, wins: driver.wins, max_possible: max,
        leader_points: @season.leader.points }
    end

    def leader_table
      leader = @season.leader
      rows = @calc.next_race_table(leader)
      {
        driver: leader.name,
        race: @season.races.first.to_h,
        rows: rows.map do |row|
          {
            position: PointsSystem.label(row[:position]),
            gain: row[:gain],
            clinch_possible: row[:possible],
            rivals: row[:allowed].to_h do |name, positions|
              [name, row[:possible] ? positions.map { |p| PointsSystem.label(p) } : []]
            end
          }
        end
      }
    end
  end
end
