log_level     :debug
log_location  STDOUT

chef_dir   = File.expand_path('~/.chef')
organization  = ENV['CHEF_ORG'] || 'chef'
username      = ENV['CHEF_USERNAME'] || 'chefuser'

cookbook_root = ENV['CHEF_COOKBOOK_REPOS'] || File.expand_path('../../ironfan-homebase', File.dirname(__FILE__))

ironfan_path    File.expand_path(cookbook_root + '/../ironfan')
keypair_path    File.expand_path(chef_dir + "/keypairs")

cookbook_path   [ "cookbooks"].map{|path| File.join(cookbook_root, path) }
cluster_path    [ "spec/data/clusters" ].map{|path| File.join(ironfan_path, path) }

node_name                username
validation_client_name   "#{organization}-validator"
validation_key           "#{keypair_path}/#{organization}-validator.pem"
client_key               "#{keypair_path}/#{username}-client_key.pem"
chef_server_url          ENV['CHEF_SERVER_URL'] || "https://api.opscode.com/organizations/#{organization}"

# Configure Bootstrap
knife[:ssh_user] = 'serengeti'
knife[:ssh_password] = 'the_password'

# Configure Monitor #
knife[:monitor_disabled] = true