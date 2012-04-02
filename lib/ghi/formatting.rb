# encoding: utf-8
require 'erb'

module GHI
  module Formatting
    THROBBERS = [
      %w(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏),
      %w(⠋ ⠙ ⠚ ⠞ ⠖ ⠦ ⠴ ⠲ ⠳ ⠓)
    ]

    autoload :Colors, 'ghi/formatting/colors'
    include Colors

    def puts *strings
      strings = strings.flatten.map { |s|
        highlight s.to_s, /@#{Authorization.username}\b/
      }
      Kernel.puts strings
    end

    def truncate string, reserved
      result = string.scan(/.{0,#{columns - reserved}}(?:\s|\Z)/).first.strip
      result << "..." if result != string
      result
    end

    def indent string, level = 4
      string = string.gsub(/\n{3,}/, "\n\n")
      lines = string.scan(/.{0,#{columns - level - 1}}(?:\s|\Z)/).map { |line|
        " " * level + line
      }
      lines.pop if lines.last.empty?
      lines.join "\n"
    end

    def columns
      dimensions[1] || 80
    end

    def dimensions
      `stty size`.chomp.split(' ').map { |n| n.to_i }
    end

    #--
    # Specific formatters:
    #++

    def format_issues_header
      header = "# #{repo || 'Global,'} #{assigns[:state] || 'open'} issues"
      if repo
        if assignee = assigns[:assignee]
          header << case assignee
            when '*'    then ', assigned'
            when 'none' then ', unassigned'
          else
            assignee = 'you' if Authorization.username == assignee
            ", assigned to #{assignee}"
          end
        end
        if mentioned = assigns[:mentioned]
          mentioned = 'you' if Authorization.username == mentioned
          header << ", mentioning #{mentioned}"
        end
      else
        header << case assigns[:filter]
          when 'created'    then ' you created'
          when 'mentioned'  then ' that mention you'
          when 'subscribed' then " you're subscribed to"
        else
          ' assigned to you'
        end
      end
      if labels = assigns[:labels]
        header << ", labeled #{assigns[:labels].gsub ',', ', '}"
      end
      if sort = assigns[:sort]
        header << ", by #{sort} #{reverse ? 'ascending' : 'descending'}"
      end
      format_state assigns[:state], header
    end

    def format_issues issues, include_repo
      include_repo and issues.each do |i|
        %r{/repos/[^/]+/([^/]+)} === i['url'] and i['repo'] = $1
      end

      nmax, rmax = %w(number repo).map { |f|
        issues.sort_by { |i| i[f].to_s.size }.last[f].to_s.size
      }

      issues.map { |i|
        n, title, labels = i['number'], i['title'], i['labels']
        l = 8 + nmax + rmax + no_color { format_labels labels }.to_s.length
        a = i['assignee'] && i['assignee']['login'] == Authorization.username
        l += 2 if a
        [
          "  #{i['repo'].to_s.rjust rmax} #{bright { n.to_s.rjust nmax }}:",
          truncate(title, l),
          format_labels(labels),
          (bright { fg(:yellow) { '@' } } if a)
        ].compact.join ' '
      }
    end

    def format_issue i
      ERB.new(<<EOF).result binding
<%= bright { indent '#%s: %s' % i.values_at('number', 'title'), 0 } %>
@<%= i['user']['login'] %> opened this issue <%= i['created_at'] %>.
<% if i['assignee'] %>\
@<%= i['assignee']['login'] %> is assigned. \
<% end %>\
<%= format_labels(i['labels']) %>
<% unless i['body'].empty? %>
<%= indent i['body'] %>\
<% end %>
EOF
    end

    def format_state state, string = state
      fg(state == 'closed' ? :red : :green) { string }
    end

    def format_labels labels
      return if labels.empty?
      format = colorize? ? ' %s ' : '[%s]'
      [*labels].map { |l| bg(l['color']) { format % l['name'] } }.join ' '
    end

    def throb position = 0, redraw = "\e[1A"
      throb = THROBBERS[rand(THROBBERS.length)]

      i = 0
      thread = Thread.new do
        dot = lambda do
          print(
            "\r\e[#{position}G#{throb[i = (i + 1) % throb.length]}\e[?25l"
          )
          sleep 0.1 and dot.call
        end
        dot.call
      end
      yield
    ensure
      thread.kill
      puts "\r\e[#{position}G#{redraw}\e[?25h"
    end
  end
end
