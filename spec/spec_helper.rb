require 'rubygems' unless defined?(Gem)
require 'bundler'
require 'spork'
require 'simplecov'
require 'simplecov-rcov'


unless defined?(IRONFAN_DIR)
  IRONFAN_DIR = File.expand_path(File.dirname(__FILE__)+'/..')
  def IRONFAN_DIR(*paths) File.join(IRONFAN_DIR, *paths); end
  # load from vendored libraries, if present
  $LOAD_PATH.unshift(IRONFAN_DIR('lib'))
  Dir[IRONFAN_DIR("vendor/*/lib")].each{|dir| p dir ;  $LOAD_PATH.unshift(File.expand_path(dir)) } ; $LOAD_PATH.uniq!
end

Spork.prefork do # This code is run only once when the spork server is started

  require 'rspec'
  require 'chef'
  require 'chef/knife'

  CHEF_CONFIG_FILE = File.expand_path(IRONFAN_DIR('spec/test_config.rb')) unless defined?(CHEF_CONFIG_FILE)
  Chef::Config.from_file(CHEF_CONFIG_FILE)

  # start SimpleCov
  SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
  SimpleCov.start do
    # We only use static provider now, code of ec2 and ruby vsphere cloud provider is not used in production now.
    # So filter them out of coverage report.
    add_filter "lib/ironfan/ec2/"
    add_filter "lib/ironfan/vsphere/"
    add_filter "lib/ironfan/common/server_slice.rb"
    add_filter "lib/ironfan/private_key.rb"
    add_filter "lib/ironfan/security_group.rb"
    add_filter "lib/ironfan/role_implications.rb"
    add_filter "lib/ironfan/deprecated.rb"
    add_filter "lib/ironfan/volume.rb"
  end

  # Requires custom matchers & macros, etc from files in ./spec_helper/
  Dir[IRONFAN_DIR("spec/spec_helper/*.rb")].each {|f| require f}

  def initialize_ironfan
    require IRONFAN_DIR('spec/spec_helper/partial_search')
    require 'ironfan'
    Ironfan.ui = Chef::Knife.ui
  end

  def load_example_cluster(name)
    require(IRONFAN_DIR('spec/data/clusters', "#{name}.rb"))
  end

  def get_example_cluster name
    load_example_cluster(name)
    Ironfan.load_cluster(name)
  end

  def knife_cluster_name
    'hadoop_cluster_test'
  end

  def set_cluster_state(cluster_name, state)
    cluster = get_example_cluster(knife_cluster_name)
    cluster.cloud.fog_connection.servers.all.each do |svr|
      puts '-------' + svr.state
      svr.state = state
      puts '-------' + svr.state
    end
  end

  def stop_cluster(cluster_name)
    set_cluster_state(cluster_name, 'Powered Off')
  end

  def get_knife action
    action = action.to_s
    require IRONFAN_DIR("lib/chef/knife/cluster_#{action}")
    knife = eval("Chef::Knife::Cluster#{action.capitalize}.new")
    knife.class.load_deps
    knife.config[:from_file] = IRONFAN_DIR('spec/data/cluster_definition.json')
    knife.config[:yes] = true
    knife.config[:skip] = true
    knife.config[:dry_run] = true
    knife.config[:verbosity] = 1
    if ['create', 'launch', 'start'].include?(action)
      knife.config[:bootstrap] = true
    end
    if ['kill'].include?(action)
      knife.config[:cloud] = true
      knife.config[:chef] = true
    end
    knife.name_args = [knife_cluster_name]
    knife.load_ironfan
    knife
  end

  def run_knife(knife)
    begin
      knife.run
    rescue SystemExit => e
      return e.success?
    end
  end

  def create_hadoop_cluster_test
    initialize_ironfan

    cluster = Ironfan::create_cluster(IRONFAN_DIR('spec/data/cluster_definition.json'), true)
    cluster.resolve!
    cluster
  end

  def get_cluster_configuration
    json = JSON.parse(File.read(IRONFAN_DIR('spec/data/cluster_definition.json')))
    json['cluster_definition']['cluster_configuration'] || {}
  end

  def get_facet_configuration(facet_name)
    json = JSON.parse(File.read(IRONFAN_DIR('spec/data/cluster_definition.json')))
    facet = json['cluster_definition']['groups'].find { |f| f['name'] == facet_name.to_s }
    facet['cluster_configuration'] || {}
  end

  # Configure rspec
  RSpec.configure do |config|
  end
end

Spork.each_run do
  # This code will be run each time you run your specs.
end
