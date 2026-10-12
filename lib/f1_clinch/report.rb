require "json"

module F1Clinch
  class Report
    def initialize(result)
      @r = result
    end

    def json
      JSON.pretty_generate(@r)
    end

    def summary
      lines = ["F1 #{@r[:season]} ドライバーズタイトル 最短確定条件（#{@r[:as_of]["date"]} #{@r[:as_of]["after_race"]}終了時点）"]
      lines << "可能性あり: #{@r[:contenders].join(', ')}"
      @r[:drivers].each do |d|
        unless d[:clinch_race]
          lines << "- #{d[:driver]}: 自力確定なし"
          next
        end
        rivals = d[:all_wins][:allowances].reject { |a| a[:unlimited] }
                                         .map { |a| "#{short(a[:rival])} #{a[:max_gain_without_tie]}" }
        lines << "- #{d[:driver]}: 最短 #{d[:clinch_race][:name]}(#{d[:clinch_after_races]}戦後) / " \
                 "必要最小 #{d[:minimum][:gain]}点 (#{d[:minimum][:example_positions].join(',')}) / " \
                 "全勝時の許容: #{rivals.empty? ? '制限なし' : rivals.join(', ')}"
      end
      lines << "可能性なし: #{@r[:eliminated].map { |d| d[:driver] }.join(', ')}"
      lines.join("\n")
    end

    def markdown
      out = []
      out << "# F1 #{@r[:season]} ドライバーズチャンピオン 最短確定条件"
      out << ""
      out << "- 基準: #{@r[:as_of]["date"]} #{@r[:as_of]["after_race"]}終了時点"
      out << "- 残り#{@r[:remaining_races].size}戦: " + @r[:remaining_races].map { |r| "#{r[:round]}.#{r[:name]}(#{r[:date]})" }.join(" / ")
      out << "- 可能性あり: #{@r[:contenders].join('、')}"
      out << ""
      out << "## 要約"
      out << ""
      out << "| ドライバー | 現在 | 最短確定 | 必要最小獲得点 | 着順例 |"
      out << "|---|---|---|---|---|"
      @r[:drivers].each do |d|
        out << "| #{d[:driver]} | #{d[:points]}点 #{d[:wins]}勝 | #{race_label(d)} | #{d.dig(:minimum, :gain)} | " \
               "#{d.dig(:minimum, :example_positions)&.join(', ')} |"
      end
      out << ""
      @r[:drivers].each { |d| out.concat(driver_section(d)) }
      out.concat(leader_section)
      out.concat(eliminated_section)
      out << "## 採用した仮定・定義"
      out << ""
      @r[:assumptions].each { |a| out << "- #{a}" }
      out << ""
      out.join("\n")
    end

    private

    def short(name)
      name.split.last
    end

    def race_label(d)
      return "なし" unless d[:clinch_race]

      "#{d[:clinch_race][:name]}（#{d[:clinch_after_races]}戦後）"
    end

    def cell(a)
      return "制限なし(最大#{a[:physical_max]})" if a[:unlimited]
      return "不可" if a[:max_gain].nil?

      base = a[:max_gain_without_tie].nil? ? "—" : a[:max_gain_without_tie].to_s
      return base unless a[:tie_allowed]

      cond = a[:tie_requires_rival_wins_at_most]
      tie = "同点#{a[:max_gain]}可"
      tie += "※R優勝#{cond}以下" if cond
      "#{base}（#{tie}）"
    end

    def columns(d)
      contenders = @r[:contenders] - [d[:driver]]
      binding = d[:conditions].flat_map { |c| c[:allowances] }.reject { |a| a[:unlimited] }.map { |a| a[:rival] }
      contenders | binding.uniq
    end

    def driver_section(d)
      out = ["## #{d[:driver]}（#{d[:team]}、#{d[:points]}点・#{d[:wins]}勝）", ""]
      unless d[:clinch_race]
        out << "自力でタイトルを確定できる結果がありません。" << ""
        return out
      end
      cols = columns(d)
      left = d[:races_left_after_clinch]
      out << "- **最短確定レース: #{d[:clinch_race][:name]}（#{d[:clinch_race][:date]}、残り#{left}戦）**"
      out << "- 確定に必要な最小獲得点: **#{d[:minimum][:gain]}点**（着順例: #{d[:minimum][:example_positions].join(', ')}）"
      allow = d[:all_wins][:allowances].select { |a| cols.include?(a[:rival]) }
      out << "- #{d[:clinch_after_races]}戦全勝（#{d[:all_wins][:gain]}点）した場合に各ライバルへ許される最大獲得点（#{d[:clinch_after_races]}戦合計）:"
      allow.each { |a| out << "  - #{a[:rival]}: #{cell(a)}" }
      out << ""
      out << "### 条件式（#{d[:clinch_after_races]}戦後）"
      out << ""
      out << "「#{short(d[:driver])}の獲得点 − ライバルの獲得点」が次の値以上なら確定。" \
             "1点少ない（同点）場合は優勝数の条件を満たせば確定。"
      out << ""
      out << "| ライバル | 必要な点差 | 同点時（点差#{'−'}1）の条件 |"
      out << "|---|---|---|"
      d[:margins].select { |m| cols.include?(m[:rival]) }.each do |m|
        out << "| #{m[:rival]} | #{m[:required_diff]} | #{m[:tie_condition]} |"
      end
      out << ""
      out << "### 条件表（パレート最適、ライバルの#{d[:clinch_after_races]}戦合計の最大許容点）"
      out << ""
      out << "数値は同点を除く最大許容点。「同点N可」は優勝数比較で同点でも確定できる場合で、" \
             "「※R優勝x以下」はそのライバルが#{d[:clinch_after_races]}戦中の優勝をx回以下に抑えることが条件。" \
             "「制限なし(最大M)」は着順の都合でライバルが取りうる最大M点まで取っても確定する意味。"
      out << ""
      out << "| #{short(d[:driver])}獲得点 | 着順例 | " + cols.map { |c| short(c) }.join(" | ") + " |"
      out << "|---|---|" + cols.map { "---" }.join("|") + "|"
      d[:conditions].each do |c|
        cells = cols.map { |name| cell(c[:allowances].find { |a| a[:rival] == name }) }
        out << "| #{c[:gain]} | #{c[:positions].join(', ')} | #{cells.join(' | ')} |"
      end
      out << ""
      out
    end

    def leader_section
      t = @r[:leader_next_race]
      rivals = t[:rows].first[:rivals].keys
      out = ["## 首位 #{t[:driver]} が次戦（#{t[:race][:name]}）で確定する条件", ""]
      out << "各セルはそのライバルに許される着順（その順位以下なら可）。1人でも満たさなければ確定しない。"
      out << ""
      out << "| #{short(t[:driver])}の着順 | 獲得点 | " + rivals.map { |r| short(r) }.join(" | ") + " |"
      out << "|---|---|" + rivals.map { "---" }.join("|") + "|"
      t[:rows].each do |row|
        cells = rivals.map do |r|
          next "—" unless row[:clinch_possible]

          positions_label(row[:rivals][r], row[:position])
        end
        label = row[:clinch_possible] ? row[:position] : "#{row[:position]}（確定不可）"
        out << "| #{label} | #{row[:gain]} | #{cells.join(' | ')} |"
      end
      out << ""
      out
    end

    def positions_label(allowed, my_pos)
      all = (1..10).map { |p| "P#{p}" } + ["圏外"]
      all -= [my_pos] unless my_pos == "圏外"
      return "不可" if allowed.empty?
      return "制限なし" if allowed == all

      "#{allowed.first}以下"
    end

    def eliminated_section
      out = ["## 可能性なし", ""]
      out << "| ドライバー | 現在 | 残り全勝時の最大 | 首位の現在点 |"
      out << "|---|---|---|---|"
      @r[:eliminated].each do |d|
        out << "| #{d[:driver]} | #{d[:points]}点 | #{d[:max_possible]}点 | #{d[:leader_points]}点 |"
      end
      out << "| 20位以下 | 5点以下 | — | — |"
      out << ""
      out
    end
  end
end
