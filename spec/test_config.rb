log_level     :debug
log_location  STDOUT

chef_dir   = File.expand_path('~/.chef')
organization  = ENV['CHEF_ORG'] || 'chef'
username      = ENV['CHEF_USERNAME'] || 'serengeti'
cookbook_root = ENV['CHEF_COOKBOOK_REPOS'] || File.expand_path('../../pantry', File.dirname(__FILE__))

ironfan_path    File.expand_path(cookbook_root + '/../ironfan')
keypair_path    ENV['CHEF_SERVER_KEYPAIR_PATH'] || chef_dir

cookbook_path   [ "cookbooks"].map{|path| File.join(cookbook_root, path) }
cluster_path    [ "spec/data/clusters" ].map{|path| File.join(ironfan_path, path) }

node_name                username
validation_client_name   "#{organization}-validator"
validation_key           "#{keypair_path}/#{organization}-validator.pem"
client_key               "#{keypair_path}/#{username}.pem"
unless ENV['CHEF_SERVER_URL']
  puts "Please export env variable CHEF_SERVER_URL, " +
       "put validation key file #{organization}-validator.pem and client key file #{username}.pem in #{keypair_path}"
  exit 1
end
chef_server_url          ENV['CHEF_SERVER_URL'] # "https://api.opscode.com/organizations/#{organization}"

# Configure Bootstrap
knife[:ssh_user] = 'serengeti'
knife[:ssh_password] = 'the_password'

# Configure Monitor #
knife[:monitor_disabled] = true

# if true, bootstrap the nodes facet by facet; if false, bootstrap all nodes in paralell.
knife[:bootstrap_by_facet] = false
# maximum number of nodes bootstrapping in paralell. 0 means unlimited.
knife[:maximum_concurrent_nodes] = 0

## yum server
knife[:yum_repos] = [ 'https://localhost/yum/repos/centos/serengeti-base.repo' ] # the urls to yum server's .repo file
# The standard OS yum repos means the default yum repos for CentOS/RHEL. Serengeti has installed the required RPMs from default yum repos into Serengeti internal yum server, so the default yum repos will be disabled by default.
knife[:enable_standard_os_yum_repos] = false
# yum install timeout
knife[:yum_timeout] = 20
# don't change default password of user serengeti
knife[:vm_use_default_password] = true
