require 'term/ansicolor'

module Concourse
  class Deployer
    module Utils
      include Term::ANSIColor
      
      def note message
        print bold, green, "NOTE: ", reset, message, "\n"
      end

      def important message
        print bold, "NOTE: ", message, reset, "\n"
      end

      def error message, continue=false
        print red, bold, "ERROR: #{message}", reset, "\n"
        exit 1 unless continue
      end

      def ensure_in_gitignore ignore_entry
        if File.exist?(GITIGNORE_FILE)
          if File.read(GITIGNORE_FILE).split("\n").include?(ignore_entry)
            note "found '#{ignore_entry}' already present in #{GITIGNORE_FILE}"
            return
          end
        end
        note "adding '#{ignore_entry}' to #{GITIGNORE_FILE}"
        File.open(GITIGNORE_FILE, "a") { |f| f.puts ignore_entry }
      end

      def ensure_in_envrc entry_key, entry_value
        entry_match = /^export #{entry_key}=/
        entry_contents = "export #{entry_key}=#{entry_value}"

        entries = if File.exist?(ENVRC_FILE)
                    File.read(ENVRC_FILE).split("\n")
                  else
                    Array.new
                  end
        found_entry = entries.grep(entry_match).first

        if found_entry.nil?
          note "adding '#{entry_key}=#{entry_value}' to #{ENVRC_FILE}"
          File.open(ENVRC_FILE, "a") { |f| f.puts entry_contents }
        else
          if found_entry == entry_contents
            note "found '#{entry_key}=#{entry_value}' already present in #{ENVRC_FILE}"
            return
          else
            note "overwriting '#{entry_key}' entry with '#{entry_value}' in #{ENVRC_FILE}"
            entries.map! do |jentry|
              jentry =~ entry_match ? entry_contents : jentry
            end
            File.open(ENVRC_FILE, "w") { |f| f.puts entries.join("\n") }
          end
        end
      end

      def which command
        found = `which #{command}`
        return $?.success? ? found : nil
      end

      def unless_which command, whereto
        if which command
          note "found command '#{command}'"
          return
        end
        error "please install '#{command}' by visiting #{whereto}"
      end

      def prompt query, default=nil
        loop do
          message = query
          message += " [#{default}]" if default
          message += ": "
          print bold, message, reset
          answer = STDIN.gets.chomp.strip
          if answer.empty?
            return default if default
            error "Please provide an answer.", true
          else
            return answer
          end
        end
      end
    end
  end
end
