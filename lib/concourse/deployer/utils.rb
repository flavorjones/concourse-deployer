require 'term/ansicolor'

module Concourse
  class Deployer
    module Utils
      include Term::ANSIColor

      GITIGNORE_FILE           = ".gitignore"
      GITATTRIBUTES_FILE       = ".gitattributes"

      def sh command
        running "(in #{Dir.pwd}) #{command}"
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

      def ensure_in_gitignore file_glob
        if File.exist?(GITIGNORE_FILE)
          if File.read(GITIGNORE_FILE).split("\n").include?(file_glob)
            note "found '#{file_glob}' already present in #{GITIGNORE_FILE}"
            return
          end
        end
        note "adding '#{file_glob}' to #{GITIGNORE_FILE}"
        File.open(GITIGNORE_FILE, "a") { |f| f.puts file_glob }
      end

      def ensure_in_gitcrypt file_glob
        crypt_entry = "#{file_glob} filter=git-crypt diff=git-crypt"
        if File.exist?(GITATTRIBUTES_FILE)
          if File.read(GITATTRIBUTES_FILE).split("\n").include?(crypt_entry)
            note "found '#{file_glob}' already git-crypted in #{GITATTRIBUTES_FILE}"
            return
          end
        end
        note "adding '#{file_glob}' as git-crypted to #{GITATTRIBUTES_FILE}"
        File.open(GITATTRIBUTES_FILE, "a") { |f| f.puts crypt_entry }
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

      def ensure_git_submodule repo_url, commitish
        repo_name = File.basename repo_url
        sh "git submodule add '#{repo_url}'" unless Dir.exists?(repo_name)
        Dir.chdir(repo_name) do
          sh "git checkout '#{commitish}'"
        end
      end

      def update_git_submodule repo_url, commitish
        ensure_git_submodule repo_url, commitish

        repo_name = File.basename repo_url
        Dir.chdir(repo_name) do
          sh "git remote update"
          sh "git pull --rebase"
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

      def prompt_for_file_contents query
        loop do
          path = prompt query
          return File.read(path) if File.exists?(path)
          error("File '#{path}' does not exist.", true)
        end
      end

      def bbl_external_ip
        `bbl lbs`.split(":").last.strip
      end

      def bosh_secrets &block
        vars = File.exists?(BOSH_SECRETS) ? YAML.load_file(BOSH_SECRETS) : {}
        return vars unless block_given?

        yield vars
        File.open(BOSH_SECRETS, "w") { |f| f.write vars.to_yaml }
        vars
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
