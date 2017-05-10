require "concourse/deployer/version"
require "concourse/deployer/utils"
require "erb"
require "open-uri"
require "nokogiri"

module Concourse
  class Deployer
    include Rake::DSL
    include Concourse::Deployer::Utils

    GITIGNORE_FILE           = ".gitignore"
    BBL_STATE_FILE           = "bbl-state.json"
    GCP_SERVICE_ACCOUNT_FILE = "service-account.key.json"
    ENVRC_FILE               = ".envrc"
    BOSH_MANIFEST_FILE     = "concourse.yml"
    BOSH_MANIFEST_ERB_FILE = "concourse.yml.erb"

    def bbl_init
      ensure_in_gitignore BBL_STATE_FILE
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
      ensure_in_gitignore GCP_SERVICE_ACCOUNT_FILE
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
      unless ENV['BBL_GCP_PROJECT_ID']
        error "Environment variable BBL_GCP_PROJECT_ID is not set. Did you run `rake bbl:gcp:init` and `direnv allow`?"
      end
      note "running `bbl up` on GCP ... go get a coffee."
      note "If you get an error about 'Access Not Configured', follow the URL in the error message and enable API access for your project!"
      sh "bbl up --iaas gcp"
      sh "bbl create-lbs --type concourse"
    end

    def bosh_prompt_to_overwrite_bosh_manifest
      return true unless File.exist?(BOSH_MANIFEST_FILE)

      overwrite = prompt "A #{BOSH_MANIFEST_FILE} file already exists. Do you want to overwrite it? (y/n)", "n"
      return !! (overwrite =~ /^y/i)
    end

    def bosh_init external_url
      ensure_in_envrc "BOSH_CLIENT", "`bbl director-username`"
      ensure_in_envrc "BOSH_CLIENT_SECRET", "`bbl director-password`"
      ensure_in_envrc "BOSH_CA_CERT", "`bbl director-ca-cert`"
      ensure_in_envrc "BOSH_ENVIRONMENT", "`bbl director-address`"
      ensure_in_envrc "BOSH_DEPLOYMENT", "concourse"
      ensure_in_envrc "BOSH_GW_PRIVATE_KEY", "rsa_ssh"

      if bosh_prompt_to_overwrite_bosh_manifest
        File.open(BOSH_MANIFEST_FILE, "w") do |f|
          # variables passed into the erb template via `binding`
          director_uuid = `bosh env`.split("\n").grep(/UUID/).first.split(/\s+/)[1]

          f.write ERB.new(File.read(File.join(File.dirname(__FILE__), "deployer", "artifacts", BOSH_MANIFEST_ERB_FILE)), nil, "%-").result(binding)
        end
      end
    end

    def bosh_update_ubuntu_stemcell
      doc = Nokogiri::XML(open("https://bosh.io/stemcells/bosh-google-kvm-ubuntu-trusty-go_agent"))
      url = doc.at_xpath("//span[@class='stemcell-name'][text()='Google KVM Light']/../..//a[@title='bosh-google-kvm-ubuntu-trusty-go_agent']/@href")
      if url.nil?
        error "Could not figure out where the latest Google KVM Light stemcell is"
      end
      sh "bosh upload-stemcell #{url}"
    end

    def bosh_update_release repo
      doc = Nokogiri::XML(open("https://bosh.io/releases/github.com/#{repo}"))
      url = doc.at_xpath("//a[text()='download']/@href")
      if url.nil?
        error "Could not figure out where the latest #{repo} release is"
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

    def bosh_update
      bosh_update_ubuntu_stemcell
      bosh_update_garden_runc_release
      bosh_update_concourse_release
    end

    def bosh_deploy
      sh "bosh deploy '#{BOSH_MANIFEST_FILE}'"
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
        task "init", ["external_url"] do |t, args|
          external_url = args["external_url"]
          unless external_url
            error "You must specify an external URL at which your concourse web server will be available, like `rake #{t.name}[external_url]`"
          end
          bosh_init external_url
        end

        desc "upload stemcells and releases to the director"
        task "update" do
          bosh_update
        end

        desc "deploy concourse"
        task "deploy" do
          bosh_deploy
        end

        namespace "concourse" do
          desc "backup your concourse database to `concourse.atc.pgdump`"
          task "backup" do
          end

          desc "restore your concourse database from `concourse.atc.pgdump`"
          task "restore" do
          end
        end

        namespace "cloud-config" do
          desc "download the bosh cloud config to `cloud-config.yml`"
          task "download" do
          end

          desc "upload a bosh cloud config from `cloud-config.yml`"
          task "upload" do
          end
        end
      end

      namespace "letsencrypt" do
        desc "backup web:/etc/letsencrypt to local disk"
        task "backup" do
        end

        desc "import letsencrypt keys into `private.yml` from backup"
        task "import" do
        end

        desc "restore web:/etc/letsencrypt from backup" # TODO check ownership is root root afterwards
        task "restore" do
        end

        desc "renew the certificate" # TODO https://certbot.eff.org/#ubuntutrusty-other
        task "renew" do
        end
      end
    end
  end
end
