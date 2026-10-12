module F1Clinch
  # 順位比較・可能性・確定の判定（定義そのもの）
  module Rules
    module_function

    # a が上なら 1、b が上なら -1、点も優勝数も同じなら 0（=未確定）
    def compare(a_points, a_wins, b_points, b_wins)
      return a_points <=> b_points unless a_points == b_points

      a_wins <=> b_wins
    end

    # 残り remaining 戦がどんな結果でも、ライバルに逆転されないか
    def clinched_against?(my_points, my_wins, rival_points, rival_wins, remaining, max_points)
      rival_best = rival_points + max_points * remaining
      return true if my_points > rival_best

      my_points == rival_best && my_wins > rival_wins + remaining
    end

    def clinched?(me, rivals, remaining, max_points)
      rivals.all? { |r| clinched_against?(me[:points], me[:wins], r[:points], r[:wins], remaining, max_points) }
    end

    # 残り全勝で現在の首位に並ぶ／上回るか（優勝数も同じ＝未確定は可能性ありとして残す）
    def possible?(driver, leader, remaining, max_points)
      return true if driver == leader

      compare(driver.points + max_points * remaining, driver.wins + remaining, leader.points, leader.wins) >= 0
    end
  end
end
