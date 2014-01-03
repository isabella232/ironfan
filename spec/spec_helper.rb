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
  SimpleCov.start

  # Requires custom matchers & macros, etc from files in ./spec_helper/
  Dir[IRONFAN_DIR("spec/spec_helper/*.rb")].each {|f| require f}

  def load_example_cluster(name)
    require(IRONFAN_DIR('spec/data/clusters', "#{name}.rb"))
  end

  def get_example_cluster name
    load_example_cluster(name)
    Ironfan.load_cluster(name)
  end

  def initialize_ironfan
    require IRONFAN_DIR("lib/chef/knife/cluster_create")
    knife_create = Chef::Knife::ClusterCreate.new
    knife_create.config[:from_file] = IRONFAN_DIR('spec/data/cluster_definition.json')
    knife_create.config[:yes] = true
    knife_create.config[:verbosity] = 2
    knife_create.name_args = 'hadoop_cluster_test'
    knife_create.load_ironfan
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
