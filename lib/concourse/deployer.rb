require "concourse/deployer/version"
require "concourse/deployer/utils"
require "erb"
require "open-uri"
require "nokogiri"
require "yaml"
require "rake"
require "tempfile"

module Concourse
  class Deployer
    include Rake::DSL
    include Concourse::Deployer::Utils

    GCP_SERVICE_ACCOUNT_FILE = "service-account.key.json"
    ENVRC_FILE = ".envrc"

    BBL_STATE_FILE = "bbl-state.json"
    BBL_VARS_DIR = "vars"

    BOSH_DEPLOYMENT = "concourse"
    BOSH_SECRETS = "secrets.yml"
    BOSH_VARS_STORE = "cluster-creds.yml"
    BOSH_OPERATIONS = "operations.yml"

    CONCOURSE_DEPLOYMENT_VARS = "deployment-vars.yml"

    def bbl_init
      unless_which "bbl", "https://github.com/cloudfoundry/bosh-bootloader/releases"
      unless_which "bosh", "https://github.com/cloudfoundry/bosh-cli/releases"
      unless_which "terraform", "https://www.terraform.io/downloads.html"
    end

    def bbl_gcp_prompt_for_service_account
      return true unless File.exist?(GCP_SERVICE_ACCOUNT_FILE)

      overwrite = prompt "A #{GCP_SERVICE_ACCOUNT_FILE} file already exists. Do you want to overwrite it? (y/n)", "n"
      return !!(overwrite =~ /^y/i)
    end

    def bbl_gcp_init(project_id)
      bbl_init
      unless_which "gcloud", "https://cloud.google.com/sdk/downloads"
      ensure_in_gitcrypt GCP_SERVICE_ACCOUNT_FILE
      ensure_in_envrc "BBL_GCP_PROJECT_ID", project_id
      ensure_in_envrc "BBL_IAAS", "gcp"
      ensure_in_envrc "BBL_GCP_REGION", "us-central1"
      ensure_in_envrc "BBL_GCP_SERVICE_ACCOUNT_KEY", GCP_SERVICE_ACCOUNT_FILE

      if bbl_gcp_prompt_for_service_account
        service_account_name = "concourse-bbl-service-account"

        sh %Q{gcloud --project=#{project_id} iam service-accounts create '#{service_account_name}'}
        sh %Q{gcloud --project=#{project_id} iam service-accounts keys create '#{GCP_SERVICE_ACCOUNT_FILE}' --iam-account '#{service_account_name}@#{project_id}.iam.gserviceaccount.com'}
        sh %Q{gcloud projects add-iam-policy-binding '#{project_id}' --member 'serviceAccount:#{service_account_name}@#{project_id}.iam.gserviceaccount.com' --role 'roles/editor'}
      end
    end

    def bbl_gcp_up
      unless ENV["BBL_GCP_PROJECT_ID"]
        error "Environment variable BBL_GCP_PROJECT_ID is not set. Did you run `rake bbl:gcp:init` and `direnv allow`?"
      end

      ensure_in_gitcrypt BBL_STATE_FILE
      ensure_in_gitcrypt "#{BBL_VARS_DIR}/*"
      ensure_in_envrc 'eval "$(bbl print-env)"'

      note ""
      note "running `bbl up` on GCP ... go get a coffee."
      note "(If you get an error about 'Access Not Configured', follow the URL in the error message and enable API access for your project!)"
      note ""
      sh "bbl plan --lb-type concourse"
      sh "bbl up --lb-type concourse"
    end

    def bosh_init
      ensure_git_submodule "https://github.com/concourse/concourse-bosh-deployment", "master"
      ensure_in_gitcrypt BOSH_SECRETS
      ensure_in_envrc "BOSH_DEPLOYMENT", BOSH_DEPLOYMENT

      bosh_secrets do |v|
        v["external_dns_name"] ||= prompt("Please enter a DNS name if you have one", bbl_external_ip)

        v["postgres_host"] ||= prompt("External postgres host IP")
        v["postgres_port"] ||= prompt("External postgres port", 5432)
        v["postgres_role"] ||= prompt("External postgres role", "postgres")
        v["postgres_password"] ||= prompt("External postgres password")

        v["postgres_client_cert"] = (v["postgres_client_cert"] || {}).tap do |cert|
          cert["certificate"] ||= prompt_for_file_contents "Path to client-cert.pem"
          cert["private_key"] ||= prompt_for_file_contents "Path to client-key.pem"
        end
        v["postgres_ca_cert"] = (v["postgres_ca_cert"] || {}).tap do |cert|
          cert["certificate"] ||= prompt_for_file_contents "Path to server-ca.pem"
        end

        if v["github_client"].nil?
          if prompt("Would you like to configure a github oauth2 application", "n") =~ /^y/i
            v["github_client"] = {}.tap do |gc|
              gc["username"] = prompt "Github Client ID"
              gc["password"] = prompt "Github Client Secret"
            end
            v["main_team"] ||= {}.tap do |mt|
              mt["github_users"] ||= []
              mt["github_orgs"] ||= []
              mt["github_teams"] ||= []
            end
          end
        end
        if v["main_team"].nil?
          v["local_user"] = (v["local_user"] || {}).tap do |local_user|
            local_user["username"] = "concourse"
            local_user["password"] ||= if which "apg"
                `apg -m32 -n1`.strip
              else
                prompt "Please enter a password"
              end
          end
        end
      end

      ensure_file CONCOURSE_DEPLOYMENT_VARS do |f|
        f.write({
                  "web_instances" => 1,
                  "worker_instances" => 2, # 1
                  "web_vm_type" => "default",
                  "worker_vm_type" => "default", # "n1-standard-2"
                  "worker_ephemeral_disk" => "50GB_ephemeral_disk",
                  "max-active-tasks-per-worker" => 4, # twice the vCPUs (?)
                }.to_yaml)
      end
    end

    def bosh_update_concourse_deployment(commitish)
      commitish ||= "master"
      ensure_git_submodule "https://github.com/concourse/concourse-bosh-deployment", commitish
    end

    def bosh_update_ubuntu_stemcell
      bosh_update_stemcell "bosh-google-kvm-ubuntu-xenial-go_agent"
    end

    # def bosh_update_windows_stemcell
    #   bosh_update_stemcell "bosh-google-kvm-windows2012R2-go_agent"
    # end

    # def bosh_update_concourse_windows_release
    #   # bosh_update_from_git_repo "https://github.com/pivotal-cf-experimental/concourse-windows-release"
    #   bosh_update_release "pivotal-cf-experimental/concourse-windows-worker-release"
    # end

    # def bosh_update_windows_ruby_dev_tools
    #   # bosh_update_from_git_repo "https://github.com/flavorjones/windows-ruby-dev-tools-release"
    #   bosh_update_release "flavorjones/windows-ruby-dev-tools-release"
    # end

    # def bosh_update_windows_utilities_release
    #   bosh_update_release "cloudfoundry-incubator/windows-utilities-release"
    # end

    def bosh_deploy(command: "deploy")
      unless File.exists?(BOSH_SECRETS)
        error "File #{BOSH_SECRETS} does not exist. Please run `rake bosh:init` first."
      end

      unless File.exists?(CONCOURSE_DEPLOYMENT_VARS)
        error "File #{CONCOURSE_DEPLOYMENT_VARS} does not exist. Please run `rake bosh:init` first."
      end

      ensure_in_gitcrypt BOSH_SECRETS
      ensure_in_gitcrypt BOSH_VARS_STORE

      external_dns_name = bosh_secrets["external_dns_name"]
      external_url = "https://#{external_dns_name}"

      ops_files = Dir[File.join(File.dirname(__FILE__), "deployer", "operations", "*.yml")]

      # command will be run in the bosh deployment submodule's cluster directory
      command = [].tap do |c|
        c << "bosh #{command} concourse.yml"
        # c << "--no-redact" # DEBUG
        c << "-l ../versions.yml"
        c << "-l ../../#{BOSH_SECRETS}"
        c << "--vars-store ../../#{BOSH_VARS_STORE}"
        c << "-o operations/basic-auth.yml" unless bosh_secrets["main_team"]
        c << "-o operations/web-network-extension.yml"
        c << "-o operations/external-postgres.yml"
        c << "-o operations/external-postgres-tls.yml"
        c << "-o operations/external-postgres-client-cert.yml"
        c << "-o operations/worker-ephemeral-disk.yml"
        c << "-o operations/x-frame-options-sameorigin.yml"
        c << "-o operations/container-placement-strategy-limit-active-tasks.yml"
        c << "-o operations/scale.yml"
        c << "-o ../../#{BOSH_OPERATIONS}" if File.exists?(BOSH_OPERATIONS)
        c << "-o operations/github-auth.yml" if bosh_secrets["github_client"]
        c << "--var network_name=default"
        c << "--var azs=[z1]"
        c << "--var external_host='#{external_dns_name}'"
        c << "--var external_url='#{external_url}'"
        c << "--var deployment_name=#{BOSH_DEPLOYMENT}"
        c << "--var web_network_name=private"
        c << "--var web_network_vm_extension=lb"
        c << "-l ../../#{CONCOURSE_DEPLOYMENT_VARS}"
        ops_files.each do |ops_file|
          c << "-o #{ops_file}"
        end
      end.join(" ")

      Dir.chdir("concourse-bosh-deployment/cluster") do
        sh command
      end
    end

    def db_connect
      tempfile_cert = Tempfile.new
      tempfile_key = Tempfile.new
      tempfile_ca = Tempfile.new
      begin
        tempfile_cert.write bosh_secrets["postgres_client_cert"]["certificate"]
        tempfile_key.write bosh_secrets["postgres_client_cert"]["private_key"]
        tempfile_ca.write bosh_secrets["postgres_ca_cert"]["certificate"]

        tempfile_cert.close
        tempfile_key.close
        tempfile_ca.close

        command = %Q{psql "sslmode=verify-ca sslrootcert=#{tempfile_ca.path} sslcert=#{tempfile_cert.path} sslkey=#{tempfile_key.path} hostaddr=#{bosh_secrets["postgres_host"]} user=#{bosh_secrets["postgres_role"]} dbname=atc"}

        sh command
      ensure
        tempfile_cert.unlink
        tempfile_key.unlink
        tempfile_ca.unlink
      end
    end

    def create_tasks!
      namespace "bbl" do
        namespace "gcp" do
          desc "initialize bosh-bootloader for GCP"
          task "init", ["gcp_project_id"] do |t, args|
            gcp_project_id = args["gcp_project_id"]
            unless gcp_project_id
              error "You must specify an existing GCP project id, like `rake #{t.name}[unique-project-name]`"
            end
            bbl_gcp_init gcp_project_id
          end

          desc "terraform your environment and deploy the bosh director"
          task "up" do
            bbl_gcp_up
          end
        end
      end

      namespace "bosh" do
        desc "prepare the concourse bosh deployment"
        task "init" do
          bosh_init
        end

        desc "macro task for all `update` subtasks"
        task "update" => [
               "bosh:update:concourse_deployment",
               "bosh:update:ubuntu_stemcell",
             ]

        namespace "update" do
          desc "update the git submodule for concourse-bosh-deployment (default: master)"
          task "concourse_deployment", ["commitish"] do |t, args|
            bosh_update_concourse_deployment args["commitish"]
          end

          desc "upload ubuntu stemcell to the director"
          task "ubuntu_stemcell" do
            bosh_update_ubuntu_stemcell
          end

          #       desc "upload windows stemcell to the director"
          #       task "windows_stemcell" do
          #         bosh_update_windows_stemcell
          #       end

          #       desc "upload concourse windows release to the director"
          #       task "concourse_windows_release" do
          #         bosh_update_concourse_windows_release
          #       end

          #       desc "upload windows-ruby-dev-tools release to the director"
          #       task "windows_ruby_dev_tools" do
          #         bosh_update_windows_ruby_dev_tools
          #       end

          #       desc "upload windows-utilities release to the director"
          #       task "windows_utilities_release" do
          #         bosh_update_windows_utilities_release
          #       end
        end

        desc "deploy concourse"
        task "deploy" do
          bosh_deploy
        end

        desc "view interpolated manifest"
        task "interpolate" do
          bosh_deploy command: "interpolate"
        end
      end

      namespace "db" do
        desc "connect to the postgres database"
        task "connect" do
          db_connect
        end
      end
    end
  end
end
