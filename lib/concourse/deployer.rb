require "concourse/deployer/version"
require "concourse/deployer/utils"
require "erb"
require "open-uri"
require "nokogiri"
require "yaml"

module Concourse
  class Deployer
    include Rake::DSL
    include Concourse::Deployer::Utils

    GCP_SERVICE_ACCOUNT_FILE = "service-account.key.json"
    ENVRC_FILE               = ".envrc"

    BBL_STATE_FILE           = "bbl-state.json"
    BBL_VARS_DIR             = "vars"

    BOSH_SECRETS             = "secrets.yml"
    BOSH_VARS_STORE          = "cluster-creds.yml"

    # BOSH_MANIFEST_FILE       = "concourse.yml"
    # BOSH_MANIFEST_ERB_FILE   = "concourse.yml.erb"
    # CONCOURSE_DB_BACKUP_FILE = "concourse.atc.pg.gz"
    # LETSENCRYPT_BACKUP_FILE  = "letsencrypt.tar.gz"

    # PG_PATH = "/var/vcap/packages/postgres-9*/bin"
    # PG_USER = "vcap"

    def bbl_init
      unless_which "bbl", "https://github.com/cloudfoundry/bosh-bootloader/releases"
      unless_which "bosh", "https://github.com/cloudfoundry/bosh-cli/releases"
      unless_which "terraform", "https://www.terraform.io/downloads.html"
    end

    def bbl_gcp_prompt_for_service_account
      return true unless File.exist?(GCP_SERVICE_ACCOUNT_FILE)

      overwrite = prompt "A #{GCP_SERVICE_ACCOUNT_FILE} file already exists. Do you want to overwrite it? (y/n)", "n"
      return !! (overwrite =~ /^y/i)
    end

    def bbl_gcp_init project_id
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
      unless ENV['BBL_GCP_PROJECT_ID']
        error "Environment variable BBL_GCP_PROJECT_ID is not set. Did you run `rake bbl:gcp:init` and `direnv allow`?"
      end

      ensure_in_gitcrypt BBL_STATE_FILE
      ensure_in_gitcrypt "#{BBL_VARS_DIR}/*"
      ensure_in_envrc 'eval "$(bbl print-env)"'

      note ""
      note "running `bbl up` on GCP ... go get a coffee."
      note "(If you get an error about 'Access Not Configured', follow the URL in the error message and enable API access for your project!)"
      note ""
      sh "bbl up --lb-type concourse"
    end

    def bosh_init
      ensure_git_submodule "https://github.com/concourse/concourse-bosh-deployment", "master"
      ensure_in_gitcrypt BOSH_SECRETS

      bosh_secrets do |v|
        v["local_user"] ||= {}.tap do |local_user|
          local_user["username"] = "concourse"
          local_user["password"] = if which "apg"
                                     `apg -n1`.strip
                                   else
                                     prompt "Please enter a password"
                                   end
        end

        v["external_dns_name"] ||= prompt("Please enter a DNS name if you have one", bbl_external_ip)

        v["postgres_host"] ||= prompt("External postgres host IP")
        v["postgres_port"] ||= prompt("External postgres port", 5432)
        v["postgres_role"] ||= prompt("External postgres role", "postgres")
        v["postgres_password"] ||= prompt("External postgres password")
      end
    end

    def bosh_update_ubuntu_stemcell
      bosh_update_stemcell "bosh-google-kvm-ubuntu-xenial-go_agent"
    end

    # def bosh_update_windows_stemcell
    #   bosh_update_stemcell "bosh-google-kvm-windows2012R2-go_agent"
    # end

    # def bosh_update_garden_runc_release
    #   bosh_update_release "cloudfoundry/garden-runc-release"
    # end

    # def bosh_update_concourse_release
    #   bosh_update_release "concourse/concourse"
    # end

    # def bosh_update_postgres_release
    #   bosh_update_release "cloudfoundry/postgres-release"
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

    def bosh_deploy
      unless File.exists?(BOSH_SECRETS)
        error "File #{BOSH_SECRETS} does not exist. Please run `rake bosh:init` first."
      end

      ensure_in_gitcrypt BOSH_SECRETS
      ensure_in_gitcrypt BOSH_VARS_STORE

      external_dns_name = bosh_secrets['external_dns_name']
      external_url = "https://#{external_dns_name}"

      # command will be run in the bosh deployment submodule's cluster directory
      command = [].tap do |c|
        c << "bosh deploy -d concourse concourse.yml"
        c << "-l ../versions.yml"
        c << "-l ../../#{BOSH_SECRETS}"
        c << "--vars-store ../../#{BOSH_VARS_STORE}"
        c << "-o operations/basic-auth.yml"
        c << "-o operations/privileged-http.yml"
        c << "-o operations/privileged-https.yml"
        c << "-o operations/tls.yml"
        c << "-o operations/tls-vars.yml"
        c << "-o operations/web-network-extension.yml"
        c << "-o operations/external-postgres.yml"
        c << "--var network_name=default"
        c << "--var external_host='#{external_dns_name}'"
        c << "--var external_url='#{external_url}'"
        c << "--var web_vm_type=default"
        c << "--var db_vm_type=default"
        c << "--var db_persistent_disk_type=10GB"
        c << "--var worker_vm_type=default"
        c << "--var deployment_name=concourse"
        c << "--var web_network_name=private"
        c << "--var web_network_vm_extension=lb"
      end.join(" ")

      Dir.chdir("concourse-bosh-deployment/cluster") do
        sh command
      end
    end

    # def bosh_concourse_backup
    #   ensure_in_gitignore CONCOURSE_DB_BACKUP_FILE

    #   sh "bosh ssh db 'rm -rf /tmp/#{CONCOURSE_DB_BACKUP_FILE}'"
    #   sh "bosh ssh db '#{PG_PATH}/pg_dumpall -c --username=#{PG_USER} | gzip > /tmp/#{CONCOURSE_DB_BACKUP_FILE}'"
    #   sh "bosh scp db:/tmp/#{CONCOURSE_DB_BACKUP_FILE} ."
    # end

    # def bosh_concourse_restore
    #   ensure_in_gitignore CONCOURSE_DB_BACKUP_FILE

    #   sh "bosh stop" # everything
    #   sh "bosh start db" # so we can load the db

    #   sh "bosh scp #{CONCOURSE_DB_BACKUP_FILE} db:/tmp"
    #   sh "bosh ssh db 'gunzip -c /tmp/#{CONCOURSE_DB_BACKUP_FILE} | #{PG_PATH}/psql --username=#{PG_USER} postgres'"

    #   sh "bosh start" # everything, and migrate the db if necessary
    # end

    # def dns_name
    #   @dns_name ||= YAML.load_file(BOSH_MANIFEST_FILE)["variables"].find {|h| h["name"] == "atc_tls"}["options"]["common_name"]
    # end

    # def letsencrypt_create
    #   sh "bosh ssh web -c 'sudo add-apt-repository -y ppa:certbot/certbot'"
    #   sh "bosh ssh web -c 'sudo apt-get update'"
    #   sh "bosh ssh web -c 'sudo apt-get install -y certbot'"
    #   sh "bosh stop web"
    #   begin
    #     note "logging you into the web server. run this command: sudo certbot certonly --standalone -d \"#{dns_name}\""
    #     sh "bosh ssh web"
    #   ensure
    #     sh "bosh start web"
    #   end
    # end

    # def letsencrypt_backup
    #   ensure_in_gitignore_or_gitcrypt LETSENCRYPT_BACKUP_FILE
    #   sh %Q{bosh ssh web -c 'sudo tar -zcvf /var/tmp/#{LETSENCRYPT_BACKUP_FILE} -C /etc letsencrypt'}
    #   sh %Q{bosh scp web:/var/tmp/#{LETSENCRYPT_BACKUP_FILE} .}
    # end

    # def letsencrypt_import
    #   ensure_in_gitignore_or_gitcrypt LETSENCRYPT_BACKUP_FILE
    #   sh "tar -zxf #{LETSENCRYPT_BACKUP_FILE}"
    #   begin
    #     note "importing certificate and private key for #{dns_name} ..."
    #     private = YAML.load_file BOSH_VARS_STORE
    #     private["atc_tls"]["certificate"] = File.read "letsencrypt/live/#{dns_name}/fullchain.pem"
    #     private["atc_tls"]["private_key"] = File.read "letsencrypt/live/#{dns_name}/privkey.pem"
    #     private["atc_tls"].delete("ca")
    #     File.open BOSH_VARS_STORE, "w" do |f|
    #       f.write private.to_yaml
    #     end
    #   ensure
    #     sh "rm -rf letsencrypt"
    #   end
    # end

    # def letsencrypt_restore
    #   ensure_in_gitignore_or_gitcrypt LETSENCRYPT_BACKUP_FILE
    #   sh "bosh ssh web -c 'sudo rm -rf /etc/letsencrypt /var/tmp/#{LETSENCRYPT_BACKUP_FILE}'"

    #   sh "bosh scp #{LETSENCRYPT_BACKUP_FILE} web:/var/tmp"
    #   sh "bosh ssh web -c 'sudo tar -zxvf /var/tmp/#{LETSENCRYPT_BACKUP_FILE} -C /etc'"
    #   sh "bosh ssh web -c 'sudo chown -R root:root /etc/letsencrypt'"
    # end

    # def letsencrypt_renew
    #   sh "bosh ssh web -c 'sudo add-apt-repository -y ppa:certbot/certbot'"
    #   sh "bosh ssh web -c 'sudo apt-get update'"
    #   sh "bosh ssh web -c 'sudo apt-get install -y certbot'"
    #   begin
    #     sh "bosh stop web"
    #     sh "bosh ssh web -c 'sudo certbot renew'"
    #   ensure
    #     sh "bosh start web"
    #   end
    # end

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
        desc "prepare the concourse bosh deployment (dns_name is optional)"
        task "init" do
          bosh_init
        end

        desc "upload stemcells and releases to the director"
        task "update" => [
               "bosh:update:ubuntu_stemcell",
    #            "bosh:update:windows_stemcell",
    #            "bosh:update:garden_runc_release",
    #            "bosh:update:postgres_release",
    #            "bosh:update:concourse_release",
    #            "bosh:update:concourse_windows_release",
    #            "bosh:update:windows_ruby_dev_tools",
    #            "bosh:update:windows_utilities_release",
             ]

        namespace "update" do
          desc "upload ubuntu stemcell to the director"
          task "ubuntu_stemcell" do
            bosh_update_ubuntu_stemcell
          end

    #       desc "upload windows stemcell to the director"
    #       task "windows_stemcell" do
    #         bosh_update_windows_stemcell
    #       end

    #       desc "upload garden release to the director"
    #       task "garden_runc_release" do
    #         bosh_update_garden_runc_release
    #       end

    #       desc "upload concourse release to the director"
    #       task "concourse_release" do
    #         bosh_update_concourse_release
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

    #       desc "upload postgres release to the director"
    #       task "postgres_release" do
    #         bosh_update_postgres_release
    #       end
        end

        desc "deploy concourse"
        task "deploy" do
          bosh_deploy
        end

    #     namespace "concourse" do
    #       desc "backup your concourse database to `#{CONCOURSE_DB_BACKUP_FILE}`"
    #       task "backup" do
    #         bosh_concourse_backup
    #       end

    #       desc "restore your concourse database from `#{CONCOURSE_DB_BACKUP_FILE}`"
    #       task "restore" do
    #         bosh_concourse_restore
    #       end
    #     end

    #     namespace "cloud-config" do
    #       desc "download the bosh cloud config to `cloud-config.yml`"
    #       task "download" do
    #         sh "bosh cloud-config > cloud-config.yml"
    #       end

    #       desc "upload a bosh cloud config from `cloud-config.yml`"
    #       task "upload" do
    #         sh "bosh update-cloud-config cloud-config.yml"
    #       end
    #     end
    #   end

    #   namespace "letsencrypt" do
    #     desc "create a cert"
    #     task "create" do
    #       letsencrypt_create
    #     end

    #     desc "backup web:/etc/letsencrypt to local disk"
    #     task "backup" do
    #       letsencrypt_backup
    #     end

    #     desc "import letsencrypt keys into `#{BOSH_VARS_STORE}` from backup"
    #     task "import" do
    #       letsencrypt_import
    #     end

    #     desc "restore web:/etc/letsencrypt from backup"
    #     task "restore" do
    #       letsencrypt_restore
    #     end

    #     desc "renew the certificate"
    #     task "renew" do
    #       letsencrypt_renew
    #     end
      end
    end
  end
end
