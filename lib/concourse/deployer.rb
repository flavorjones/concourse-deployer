require "concourse/deployer/version"
require 'term/ansicolor'

module Concourse
  class Deployer
    include Rake::DSL
    include Term::ANSIColor

    GITIGNORE           = ".gitignore"
    BBL_STATE           = "bbl-state.json"
    GCP_SERVICE_ACCOUNT = "service-account.key.json"

    def note message
      print bold, green, "NOTE: ", reset, message, "\n"
    end

    def error message
      print red, bold, "ERROR: #{message}", reset, "\n"
      exit 1
    end

    def ensure_in_gitignore ignore_entry
      if File.exist?(GITIGNORE)
        if File.read(GITIGNORE).split("\n").include?(ignore_entry)
          note "found '#{ignore_entry}' already present in #{GITIGNORE}"
          return
        end
      end
      note "adding '#{ignore_entry}' to #{GITIGNORE}"
      File.open(GITIGNORE, "a") { |f| f.puts ignore_entry }
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
      ensure_in_gitignore BBL_STATE
      unless_which "bbl", "https://github.com/cloudfoundry/bosh-bootloader/releases"
      unless_which "bosh", "https://github.com/cloudfoundry/bosh-cli/releases"
      unless_which "terraform", "https://www.terraform.io/downloads.html"
    end

    def bbl_gcp_init
      bbl_init
      ensure_in_gitignore GCP_SERVICE_ACCOUNT
      unless_which "gcloud", "https://cloud.google.com/sdk/downloads"
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
