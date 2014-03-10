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
    add_filter "lib/ironfan/private_key.rb"
    add_filter "lib/ironfan/security_group.rb"
    add_filter "lib/ironfan/deprecated.rb"
  end

  # Requires custom matchers & macros, etc from files in ./spec_helper/
  Dir[IRONFAN_DIR("spec/spec_helper/*.rb")].each {|f| require f}

  def initialize_ironfan
    require IRONFAN_DIR('spec/spec_helper/partial_search')
  end

  def load_example_cluster(name)
    require(IRONFAN_DIR('spec/data/clusters', "#{name}.rb"))
  end

  def get_example_cluster name
    load_example_cluster(name)
    Ironfan.load_cluster(name)
  end

  def get_knife_create
    require IRONFAN_DIR("lib/chef/knife/cluster_create")
    knife = Chef::Knife::ClusterCreate.new
    knife.class.load_deps
    knife.config[:from_file] = IRONFAN_DIR('spec/data/cluster_definition.json')
    knife.config[:yes] = true
    knife.config[:bootstrap] = true
    knife.config[:skip] = true
    knife.config[:dry_run] = true
    knife.config[:verbosity] = 1
    knife.name_args = ['hadoop_cluster_test']
    knife.load_ironfan
    knife
  end

  def get_knife_kill
    require IRONFAN_DIR("lib/chef/knife/cluster_kill")
    knife = Chef::Knife::ClusterKill.new
    knife.class.load_deps
    knife.config[:from_file] = IRONFAN_DIR('spec/data/cluster_definition.json')
    knife.config[:yes] = true
    knife.config[:skip] = true
    knife.config[:dry_run] = true
    knife.config[:chef] = true
    knife.config[:cloud] = false
    knife.config[:verbosity] = 1
    knife.name_args = ['hadoop_cluster_test']
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
