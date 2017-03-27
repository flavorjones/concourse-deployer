require "concourse/deployer/version"
require 'term/ansicolor'

module Concourse
  class Deployer
    include Rake::DSL
    include Term::ANSIColor

    GITIGNORE_FILE           = ".gitignore"
    BBL_STATE_FILE           = "bbl-state.json"
    GCP_SERVICE_ACCOUNT_FILE = "service-account.key.json"

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

    def bbl_init
      ensure_in_gitignore BBL_STATE_FILE
      unless_which "bbl", "https://github.com/cloudfoundry/bosh-bootloader/releases"
      unless_which "bosh", "https://github.com/cloudfoundry/bosh-cli/releases"
      unless_which "terraform", "https://www.terraform.io/downloads.html"
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

    def bbl_gcp_prompt_for_service_account
      return true unless File.exist?(GCP_SERVICE_ACCOUNT_FILE)

      overwrite = prompt "A #{GCP_SERVICE_ACCOUNT_FILE} file already exists. Do you want to overwrite it? (y/n)", "n"
      return !! (overwrite =~ /^y/i)
    end

    def bbl_gcp_init
      bbl_init
      ensure_in_gitignore GCP_SERVICE_ACCOUNT_FILE
      unless_which "gcloud", "https://cloud.google.com/sdk/downloads"

      if bbl_gcp_prompt_for_service_account
        project_id = prompt "GCP project id (needs to have been already created)"
        service_account_name = prompt "GCP service account name", "concourse-bbl-service-account"

        sh %Q{gcloud --project=#{project_id} iam service-accounts create '#{service_account_name}'}
        sh %Q{gcloud --project=#{project_id} iam service-accounts keys create '#{GCP_SERVICE_ACCOUNT_FILE}' --iam-account '#{service_account_name}@#{project_id}.iam.gserviceaccount.com'}
        sh %Q{gcloud projects add-iam-policy-binding '#{project_id}' --member 'serviceAccount:#{service_account_name}@#{project_id}.iam.gserviceaccount.com' --role 'roles/editor'}
      end

      important "Please make sure to save '#{GCP_SERVICE_ACCOUNT_FILE}' somewhere private and safe."
    end

    def create_tasks!
      namespace "bbl" do
        namespace "gcp" do
          desc "initialize bosh-bootloader for GCP"
          task("init") { bbl_gcp_init }
        end
      end

      namespace "bosh" do

      end
    end
  end
end
