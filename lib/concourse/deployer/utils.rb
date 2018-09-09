require 'term/ansicolor'

module Concourse
  class Deployer
    module Utils
      include Term::ANSIColor

      GITIGNORE_FILE           = ".gitignore"
      GITATTRIBUTES_FILE       = ".gitattributes"

      def sh command
        running command
        super command, verbose: false
      end

      def running message
        print bold, red, "RUNNING: ", reset, message, "\n"
      end

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

      def ensure_in_gitignore_or_gitcrypt ignore_entry
        if File.exist?(GITATTRIBUTES_FILE)
          crypt_entry = "#{ignore_entry} filter=git-crypt diff=git-crypt"
          if File.read(GITATTRIBUTES_FILE).split("\n").include?(crypt_entry)
            note "found '#{crypt_entry}' already present in #{GITATTRIBUTES_FILE}"
          else
            note "adding '#{ignore_entry}' to #{GITATTRIBUTES_FILE}"
            File.open(GITATTRIBUTES_FILE, "a") { |f| f.puts crypt_entry }
          end
          return
        end
        ensure_in_gitignore ignore_entry
      end

      def ensure_in_envrc entry_key, entry_value=nil
        entries = if File.exist?(ENVRC_FILE)
                    File.read(ENVRC_FILE).split("\n")
                  else
                    Array.new
                  end

        if entry_value
          #
          #  set an env var
          #
          entry_match = /^export #{entry_key}=/
          entry_contents = "export #{entry_key}=#{entry_value}"

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
        else
          #
          #  add a line of bash
          #
          entry_contents = entry_key
          found_entry = entries.find { |line| line == entry_contents }

          if found_entry.nil?
            note "adding '#{entry_contents}' to #{ENVRC_FILE}"
            File.open(ENVRC_FILE, "a") { |f| f.puts entry_contents }
          else
            note "found '#{entry_contents}' already present in #{ENVRC_FILE}"
            return
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

      def bosh_update_stemcell name
        doc = Nokogiri::XML(open("https://bosh.io/stemcells/#{name}"))
        url = doc.at_xpath("//a[contains(text(), 'Light Stemcell')]/@href")
        if url.nil?
          error "Could not find the latest stemcell `#{name}`"
        end
        sh "bosh upload-stemcell #{url}"
      end

      def bosh_update_release repo
        doc = Nokogiri::XML(open("https://bosh.io/releases/github.com/#{repo}?all=1"))
        url = doc.at_xpath("//a[contains(text(), 'Release Tarball')]/@href")
        if url.nil?
          error "Could not find the latest release `#{repo}`"
        end
        if url.value =~ %r{\A/}
          url = "https://bosh.io#{url}"
        end
        sh "bosh upload-release #{url}"
      end

      def bosh_update_from_git_repo git
        dirname = File.basename(git)
        Dir.mktmpdir do |dir|
          Dir.chdir dir do
            sh "git clone '#{git}'"
            Dir.chdir dirname do
              sh "bosh create-release"
              sh "bosh upload-release"
            end
          end
        end
      end

    end
  end
end
