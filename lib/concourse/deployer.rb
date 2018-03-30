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

    GITIGNORE_FILE           = ".gitignore"
    GITATTRIBUTES_FILE       = ".gitattributes"
    BBL_STATE_FILE           = "bbl-state.json"
    GCP_SERVICE_ACCOUNT_FILE = "service-account.key.json"
    ENVRC_FILE               = ".envrc"
    BOSH_MANIFEST_FILE       = "concourse.yml"
    BOSH_MANIFEST_ERB_FILE   = "concourse.yml.erb"
    BOSH_RSA_KEY             = "rsa_ssh"
    BOSH_VARS_STORE          = "private.yml"
    CONCOURSE_DB_BACKUP_FILE = "concourse.atc.pg.gz"
    LETSENCRYPT_BACKUP_FILE  = "letsencrypt.tar.gz"

    PG_PATH = "/var/vcap/packages/postgres-9*/bin"
    PG_USER = "vcap"

    def sh command
      running command
      super command, verbose: false
    end

    def bbl_init
      ensure_in_gitignore_or_gitcrypt BBL_STATE_FILE
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
      ensure_in_gitignore_or_gitcrypt GCP_SERVICE_ACCOUNT_FILE
      unless_which "gcloud", "https://cloud.google.com/sdk/downloads"

      ensure_in_envrc "BBL_GCP_PROJECT_ID", project_id
      ensure_in_envrc "BBL_GCP_SERVICE_ACCOUNT_KEY", GCP_SERVICE_ACCOUNT_FILE
      ensure_in_envrc "BBL_GCP_ZONE", "us-east1-b"
      ensure_in_envrc "BBL_GCP_REGION", "us-east1"

      if bbl_gcp_prompt_for_service_account
        service_account_name = "concourse-bbl-service-account"

        sh %Q{gcloud --project=#{project_id} iam service-accounts create '#{service_account_name}'}
        sh %Q{gcloud --project=#{project_id} iam service-accounts keys create '#{GCP_SERVICE_ACCOUNT_FILE}' --iam-account '#{service_account_name}@#{project_id}.iam.gserviceaccount.com'}
        sh %Q{gcloud projects add-iam-policy-binding '#{project_id}' --member 'serviceAccount:#{service_account_name}@#{project_id}.iam.gserviceaccount.com' --role 'roles/editor'}
      end

      important "Please make sure to save '#{GCP_SERVICE_ACCOUNT_FILE}' somewhere private and safe."
    end

    def bbl_gcp_up
      ensure_in_gitignore_or_gitcrypt BOSH_RSA_KEY
      ensure_in_envrc "BOSH_GW_PRIVATE_KEY", BOSH_RSA_KEY

      unless ENV['BBL_GCP_PROJECT_ID']
        error "Environment variable BBL_GCP_PROJECT_ID is not set. Did you run `rake bbl:gcp:init` and `direnv allow`?"
      end
      note "running `bbl up` on GCP ... go get a coffee."
      note "If you get an error about 'Access Not Configured', follow the URL in the error message and enable API access for your project!"
      sh "bbl up --iaas gcp"
      sh "bbl create-lbs --type concourse"

      sh "bbl ssh-key > #{BOSH_RSA_KEY}"
      sh "chmod go-rwx #{BOSH_RSA_KEY}"
    end

    def bosh_prompt_to_overwrite_bosh_manifest
      return true unless File.exist?(BOSH_MANIFEST_FILE)

      overwrite = prompt "A #{BOSH_MANIFEST_FILE} file already exists. Do you want to overwrite it? (y/n)", "n"
      return !! (overwrite =~ /^y/i)
    end

    def bosh_init dns_name
      ensure_in_envrc "BOSH_CLIENT", "`bbl director-username`"
      ensure_in_envrc "BOSH_CLIENT_SECRET", "`bbl director-password`"
      ensure_in_envrc "BOSH_CA_CERT", "`bbl director-ca-cert`"
      ensure_in_envrc "BOSH_ENVIRONMENT", "`bbl director-address`"
      ensure_in_envrc "BOSH_DEPLOYMENT", "concourse"

      if bosh_prompt_to_overwrite_bosh_manifest
        File.open(BOSH_MANIFEST_FILE, "w") do |f|
          # variables passed into the erb template via `binding`
          director_uuid = `bosh env`.split("\n").grep(/UUID/).first.split(/\s+/)[1]

          f.write ERB.new(File.read(File.join(File.dirname(__FILE__), "deployer", "artifacts", BOSH_MANIFEST_ERB_FILE)), nil, "%-").result(binding)
        end
      end
    end

    def bosh_update_stemcell name
      doc = Nokogiri::XML(open("https://bosh.io/stemcells/#{name}"))
      url = doc.at_xpath("//span[@class='stemcell-name'][contains(text(), 'Light')]/../..//a[@title='#{name}']/@href")
      if url.nil?
        error "Could not find the latest stemcell `#{name}`"
      end
      sh "bosh upload-stemcell #{url}"
    end

    def bosh_update_ubuntu_stemcell
      bosh_update_stemcell "bosh-google-kvm-ubuntu-trusty-go_agent"
    end

    def bosh_update_windows_stemcell
      bosh_update_stemcell "bosh-google-kvm-windows2012R2-go_agent"
    end

    def bosh_update_release repo
      doc = Nokogiri::XML(open("https://bosh.io/releases/github.com/#{repo}"))
      url = doc.at_xpath("//a[text()='download']/@href")
      if url.nil?
        error "Could not find the latest release `#{repo}`"
      end
      if url.value =~ %r{\A/}
        url = "https://bosh.io#{url}"
      end
      sh "bosh upload-release #{url}"
    end

    def bosh_update_garden_runc_release
      bosh_update_release "cloudfoundry/garden-runc-release"
    end

    def bosh_update_concourse_release
      bosh_update_release "concourse/concourse"
    end

    def bosh_update_postgres_release
      bosh_update_release "cloudfoundry/postgres-release"
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

    def bosh_update_concourse_windows_release
      # bosh_update_from_git_repo "https://github.com/pivotal-cf-experimental/concourse-windows-release"
      bosh_update_release "pivotal-cf-experimental/concourse-windows-worker-release"
    end

    def bosh_update_windows_ruby_dev_tools
      # bosh_update_from_git_repo "https://github.com/flavorjones/windows-ruby-dev-tools-release"
      bosh_update_release "flavorjones/windows-ruby-dev-tools-release"
    end

    def bosh_update_windows_utilities_release
      bosh_update_release "cloudfoundry-incubator/windows-utilities-release"
    end

    def bosh_deploy
      ensure_in_gitignore_or_gitcrypt BOSH_VARS_STORE
      sh "bosh deploy '#{BOSH_MANIFEST_FILE}' --vars-store=#{BOSH_VARS_STORE}"
    end

    def bosh_concourse_backup
      ensure_in_gitignore CONCOURSE_DB_BACKUP_FILE

      sh "bosh ssh db 'rm -rf /tmp/#{CONCOURSE_DB_BACKUP_FILE}'"
      sh "bosh ssh db '#{PG_PATH}/pg_dumpall -c --username=#{PG_USER} | gzip > /tmp/#{CONCOURSE_DB_BACKUP_FILE}'"
      sh "bosh scp db:/tmp/#{CONCOURSE_DB_BACKUP_FILE} ."
    end

    def bosh_concourse_restore
      ensure_in_gitignore CONCOURSE_DB_BACKUP_FILE

      sh "bosh stop" # everything
      sh "bosh start db" # so we can load the db

      sh "bosh scp #{CONCOURSE_DB_BACKUP_FILE} db:/tmp"
      sh "bosh ssh db 'gunzip -c /tmp/#{CONCOURSE_DB_BACKUP_FILE} | #{PG_PATH}/psql --username=#{PG_USER} postgres'"

      sh "bosh start" # everything, and migrate the db if necessary
    end

    def dns_name
      @dns_name ||= YAML.load_file(BOSH_MANIFEST_FILE)["variables"].find {|h| h["name"] == "atc_tls"}["options"]["common_name"]
    end

    def letsencrypt_create
      sh "bosh ssh web -c 'sudo add-apt-repository -y ppa:certbot/certbot'"
      sh "bosh ssh web -c 'sudo apt-get update'"
      sh "bosh ssh web -c 'sudo apt-get install -y certbot'"
      sh "bosh stop web"
      begin
        note "logging you into the web server. run this command: sudo certbot certonly --standalone -d \"#{dns_name}\""
        sh "bosh ssh web"
      ensure
        sh "bosh start web"
      end
    end

    def letsencrypt_backup
      ensure_in_gitignore_or_gitcrypt LETSENCRYPT_BACKUP_FILE
      sh %Q{bosh ssh web -c 'sudo tar -zcvf /var/tmp/#{LETSENCRYPT_BACKUP_FILE} -C /etc letsencrypt'}
      sh %Q{bosh scp web:/var/tmp/#{LETSENCRYPT_BACKUP_FILE} .}
    end

    def letsencrypt_import
      ensure_in_gitignore_or_gitcrypt LETSENCRYPT_BACKUP_FILE
      sh "tar -zxf #{LETSENCRYPT_BACKUP_FILE}"
      begin
        note "importing certificate and private key for #{dns_name} ..."
        private = YAML.load_file BOSH_VARS_STORE
        private["atc_tls"]["certificate"] = File.read "letsencrypt/live/#{dns_name}/fullchain.pem"
        private["atc_tls"]["private_key"] = File.read "letsencrypt/live/#{dns_name}/privkey.pem"
        private["atc_tls"].delete("ca")
        File.open BOSH_VARS_STORE, "w" do |f|
          f.write private.to_yaml
        end
      ensure
        sh "rm -rf letsencrypt"
      end
    end

    def letsencrypt_restore
      ensure_in_gitignore_or_gitcrypt LETSENCRYPT_BACKUP_FILE
      sh "bosh ssh web -c 'sudo rm -rf /etc/letsencrypt /var/tmp/#{LETSENCRYPT_BACKUP_FILE}'"

      sh "bosh scp #{LETSENCRYPT_BACKUP_FILE} web:/var/tmp"
      sh "bosh ssh web -c 'sudo tar -zxvf /var/tmp/#{LETSENCRYPT_BACKUP_FILE} -C /etc'"
      sh "bosh ssh web -c 'sudo chown -R root:root /etc/letsencrypt'"
    end

    def letsencrypt_renew
      sh "bosh ssh web -c 'sudo add-apt-repository -y ppa:certbot/certbot'"
      sh "bosh ssh web -c 'sudo apt-get update'"
      sh "bosh ssh web -c 'sudo apt-get install -y certbot'"
      begin
        sh "bosh stop web"
        sh "bosh ssh web -c 'sudo certbot renew'"
      ensure
        sh "bosh start web"
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
        desc "prepare a bosh manifest for your concourse deployment"
        task "init", ["dns_name"] do |t, args|
          dns_name = args["dns_name"]
          unless dns_name
            error "You must specify a domain name at which your concourse web server will be available, like `rake #{t.name}[dns_name]`"
          end
          bosh_init dns_name
        end

        desc "upload stemcells and releases to the director"
        task "update" => [
               "bosh:update:ubuntu_stemcell",
               "bosh:update:windows_stemcell",
               "bosh:update:garden_runc_release",
               "bosh:update:postgres_release",
               "bosh:update:concourse_release",
               "bosh:update:concourse_windows_release",
               "bosh:update:windows_ruby_dev_tools",
               "bosh:update:windows_utilities_release",
             ]

        namespace "update" do
          desc "upload ubuntu stemcell to the director"
          task "ubuntu_stemcell" do
            bosh_update_ubuntu_stemcell
          end

          desc "upload windows stemcell to the director"
          task "windows_stemcell" do
            bosh_update_windows_stemcell
          end

          desc "upload garden release to the director"
          task "garden_runc_release" do
            bosh_update_garden_runc_release
          end

          desc "upload concourse release to the director"
          task "concourse_release" do
            bosh_update_concourse_release
          end

          desc "upload concourse windows release to the director"
          task "concourse_windows_release" do
            bosh_update_concourse_windows_release
          end

          desc "upload windows-ruby-dev-tools release to the director"
          task "windows_ruby_dev_tools" do
            bosh_update_windows_ruby_dev_tools
          end

          desc "upload windows-utilities release to the director"
          task "windows_utilities_release" do
            bosh_update_windows_utilities_release
          end

          desc "upload postgres release to the director"
          task "postgres_release" do
            bosh_update_postgres_release
          end
        end

        desc "deploy concourse"
        task "deploy" do
          bosh_deploy
        end

        namespace "concourse" do
          desc "backup your concourse database to `#{CONCOURSE_DB_BACKUP_FILE}`"
          task "backup" do
            bosh_concourse_backup
          end

          desc "restore your concourse database from `#{CONCOURSE_DB_BACKUP_FILE}`"
          task "restore" do
            bosh_concourse_restore
          end
        end

        namespace "cloud-config" do
          desc "download the bosh cloud config to `cloud-config.yml`"
          task "download" do
            sh "bosh cloud-config > cloud-config.yml"
          end

          desc "upload a bosh cloud config from `cloud-config.yml`"
          task "upload" do
            sh "bosh update-cloud-config cloud-config.yml"
          end
        end
      end

      namespace "letsencrypt" do
        desc "create a cert"
        task "create" do
          letsencrypt_create
        end

        desc "backup web:/etc/letsencrypt to local disk"
        task "backup" do
          letsencrypt_backup
        end

        desc "import letsencrypt keys into `#{BOSH_VARS_STORE}` from backup"
        task "import" do
          letsencrypt_import
        end

        desc "restore web:/etc/letsencrypt from backup"
        task "restore" do
          letsencrypt_restore
        end

        desc "renew the certificate"
        task "renew" do
          letsencrypt_renew
        end
      end
    end
  end
end
