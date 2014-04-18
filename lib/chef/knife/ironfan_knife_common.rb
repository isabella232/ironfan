#
#   Portions Copyright (c) 2012-2014 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

require 'chef/knife'
require 'ironfan/constants'

module Ironfan
  module KnifeCommon

    include Ironfan::Error

    # Exit Status of Knife commands
    SUCCESS ||= 0
    FAILURE ||= 1
    CREATE_FAILURE ||= 2
    BOOTSTRAP_FAILURE ||= 3
    DELETE_FAILURE ||= 4
    STOP_FAILURE ||= 5
    START_FAILURE ||= 6

    MAXIMUM_CONCURRENT_NODES ||= 100

    def self.load_deps
      require 'json'
      require 'formatador'
      require 'chef/node'
      require 'chef/api_client'
    end

    def load_ironfan
      $LOAD_PATH << File.join(Chef::Config[:ironfan_path], '/lib') if Chef::Config[:ironfan_path]
      require 'ironfan'
      require 'ironfan/monitor'
      extend Ironfan::Monitor

      $stdout.sync = true
      Ironfan.ui          = self.ui
      Ironfan.chef_config = self.config

      Chef::Log::Formatter.show_time = true # initialize logger

      initialize_ironfan_broker(config[:from_file]) if config[:from_file] # for :vsphere cloud
    end

    def initialize_ironfan_broker(config_file)
      require 'ironfan/iaas_layer' 

      initialize_iaas_provider(config_file)
      save_distro_info(config_file)
      save_cluster_file(config_file, true)
    end

    def save_cluster_file config_file, overwrite
      Chef::Log.debug("Creating cluster file")
      Ironfan.create_cluster(config_file, overwrite)
    end

    def initialize_iaas_provider(filename)
      Ironfan::IaasProvider.init(JSON.parse(File.read(filename))) # initialize IaasProvider
    end

    def save_distro_info(filename)
      Chef::Log.debug("Loading hadoop distro info")
      begin
        cluster_def = JSON.parse(File.read(filename))['cluster_definition']
        distro_name = cluster_def['distro']
        # package_repos is an array of yum (or apt) server repo url which points to yum server providing the hadoop rpm packages
        package_repos = cluster_def['distro_package_repos'] || [] # this is user specified yum server repos for this hadoop distro
        # tell chef recipes install hadoop from tarball or rpms
        is_install_from_tarball = package_repos.empty?
        # add Serengeti internal yum server repo which provides hortonworks vsphere ha packages and other packages
        package_repos.concat(Chef::Config[:knife][:yum_repos]).uniq!

        distro_repo = cluster_def['distro_map'] || {} # 'distro_map' is a Hash: { 'hadoop' => tarball_url, 'hbase' => tarball_url, ... }
        distro_repo['package_repos'] = package_repos
        distro_repo['is_install_from_tarball'] = is_install_from_tarball
        distro_repo['id'] = distro_name
      rescue StandardError => e
        raise "Malformed hadoop distro info in cluster definition file: #{e}"
      end

      Chef::Log.debug("Saving hadoop distro info to Chef Data Bag: #{distro_repo}")
      save_databag_item("hadoop_distros", distro_name, distro_repo)
    end

    def target_name
      @name_args.length > 1 ? @name_args.join('-') : @name_args[0]
    end

    def cluster_name
      if @name_args.length > 1
        return @name_args[0] # when @name_args is [clustername facet index]
      else
        return @name_args[0].split('-')[0] # when @name_args is [clustername-facet-index]
      end
    end

    def cluster
      @cluster ||= Ironfan.load_cluster(cluster_name)
    end

    def cloud
      @cloud ||= cluster.cloud
    end

    #
    # A slice of a cluster:
    #
    # @param [String] cluster_name  -- cluster to slice
    # @param [String] facet_name    -- facet to slice (or nil for all in cluster)
    # @param [Array, String] slice_indexes -- servers in that facet (or nil for all in facet).
    #   You must specify a facet if you use slice_indexes.
    #
    # @return [Ironfan::ServerSlice] the requested slice
    def get_slice(slice_string, *args)
      if not args.empty?
        slice_string = [slice_string, args].flatten.join("-")
        ui.info("")
        ui.warn("Please specify server slices joined by dashes and not separate args:\n\n  knife cluster #{sub_command} #{slice_string}\n\n")
      end
      cluster_name, facet_name, slice_indexes = slice_string.split(/[\s\-]/, 3)
      Chef::Log.info("Inventorying servers in #{predicate_str(cluster_name, facet_name, slice_indexes)}")
      cluster = Ironfan.load_cluster(cluster_name)
      cluster.resolve!
      cluster.discover!
      cluster.slice(facet_name, slice_indexes)
    end

    def predicate_str(cluster_name, facet_name, slice_indexes)
      [ "#{ui.color(cluster_name, :bold)} cluster",
        (facet_name    ? "#{ui.color(facet_name, :bold)} facet"      : "#{ui.color("all", :bold)} facets"),
        (slice_indexes ? "servers #{ui.color(slice_indexes, :bold)}" : "#{ui.color("all", :bold)} servers")
      ].join(', ')
    end

    # method to nodes should be filtered on
    def relevant?(server)
      server.exists?
    end

    # is valid server ?
    def valid?(server)
      relevant?(server) and !server.bogus?
    end

    # override in subclass to confirm risky actions
    def confirm_execution(*args)
      # pass
    end

    #
    # Get a slice of nodes matching the given filter
    #
    # @example
    #    target = get_relevant_slice(* @name_args)
    #
    def get_relevant_slice( *predicate )
      full_target = get_slice( *predicate )
      ui.info("Finding relevant servers to #{sub_command}:")
      display(full_target) do |svr|
        rel = relevant?(svr)
        { :relevant? => (rel ? "[blue]#{rel}[reset]" : '-' ) }
      end

      if not full_target.bogus_servers.empty?
        ui.info("Deleting bogus servers which are not defined in this cluster")
        full_target.bogus_servers.each(&:sync_to_chef)
        full_target.bogus_servers.each(&:sync_to_cloud)
      end

      full_target.select { |svr| valid?(svr) }
    end

    def get_valid_slice(target)
      target.select { |svr| valid?(svr) }
    end

    # passes target to ClusterSlice#display, will show headings in server slice
    # tables based on the --verbose flag
    def display(target, display_style=nil, &block)
      display_style ||= (config[:verbosity] == 0 ? :default : :expanded)
      target.display(display_style, &block)
    end

    def configure_dry_run
      if config[:dry_run]
        # TODO
      end
    end

    # Show a pretty progress bar while we wait for a set of threads to finish.
    def progressbar_for_threads(threads)
      section "Waiting for servers:"
      total      = threads.length
      remaining  = threads.select(&:alive?)
      start_time = Time.now
      until remaining.empty?
        remaining = remaining.select(&:alive?)
        if config[:verbose]
          ui.info "waiting for threads to complete: #{total - remaining.length} / #{total}, #{(Time.now - start_time).to_i}s"
          sleep 5
        else
          Formatador.redisplay_progressbar(total - remaining.length, total, {:started_at => start_time })
          sleep 1
        end
      end
      # Collapse the threads
      threads.each(&:join)
      ui.info ''
    end

    def bootstrapper(server, hostname)
      bootstrap = Chef::Knife::Bootstrap.new
      bootstrap.config.merge!(config)

      # load SSH info from knife.rb
      config[:ssh_user] ||= Chef::Config[:knife][:ssh_user]
      config[:ssh_password] ||= Chef::Config[:knife][:ssh_password]

      bootstrap.name_args               = [ hostname ]
      bootstrap.config[:node]           = server
      bootstrap.config[:run_list]       = server.combined_run_list
      bootstrap.config[:ssh_user]       = config[:ssh_user]       || server.cloud.ssh_user
      bootstrap.config[:ssh_password]   = config[:ssh_password]
      bootstrap.config[:attribute]      = config[:attribute]
      bootstrap.config[:identity_file]  = config[:identity_file]  || server.cloud.ssh_identity_file
      bootstrap.config[:distro]         = config[:distro]         || server.cloud.bootstrap_distro
      bootstrap.config[:use_sudo]       = true unless config[:use_sudo] == false
      bootstrap.config[:chef_node_name] = server.fullname
      bootstrap.config[:client_key]     = server.client_key.body  if server.client_key.body

      bootstrap
    end

    def run_bootstrap(node, hostname)
      ret = 0
      nodename = "node #{node.name} (#{hostname})"
      bs = bootstrapper(node, hostname)
      if config[:dry_run]
        ui.info "Skip bootstrapping #{nodename} in dry run mode"
      else
        begin
          ui.info "Start bootstrapping #{nodename}"
          ret = bs.run
        rescue StandardError => e
          ui.error "Error thrown when bootstrapping #{nodename} : #{e}"
          ui.error e.backtrace.pretty_inspect
          ui.error "Node data is : #{node.pretty_inspect}"
          ret = BOOTSTRAP_FAILURE
        end
      end

      ui.info "Bootstrapping #{nodename} completed with exit status #{ret.to_s}"
      ret
    end

    def bootstrap_cluster(target)
      return SUCCESS if target.empty?

      # in case service registry entries are in Chef Nodes, but the service daemon (which is depended by other daemons) is not started yet, e.g.
      # 1. hadoop namenode daemon is not started yet during a 'cluster start'
      # 2. hadoop namenode daemon is down before bootstrap the cluster
      # and hbase master/regionserver daemons require hadoop namenode daemon is running on the same or another VM,
      # so starting hbase daemons will fail when hadoop namenode daemon is down.
      # solution is: clear registry entries before bootstrapping cluster.
      target.clear_service_registry_entries

      target_name = target.name
      section("Start bootstrapping nodes in cluster #{target_name} at #{Time.now}")
      exit_status = []
      begin
        start_monitor_bootstrap(target)
        if Chef::Config[:knife][:bootstrap_by_facet]
          target.cluster.facets.each do |name, facet|
            servers = target.select { |svr| svr.facet_name == facet.name and svr.in_cloud? }
            next if servers.empty?
            section("Bootstrapping nodes in facet #{name}", :green)
            exit_status += bootstrap_servers(servers)
          end
        else
          exit_status = bootstrap_servers(target)
        end
      ensure
        end_monitor_bootstrap(target)
      end

      ui.info "Bootstrapping cluster #{target_name} completed with exit status #{exit_status.inspect} at #{Time.now}"
      exit_status.select{|i| i != SUCCESS}.empty? ? SUCCESS : BOOTSTRAP_FAILURE
    end

    def bootstrap_servers(target)
      exit_status = []

      # Bootstrapping more than about 100 nodes simultaneously requires a powerful Chef Server and couchdb.
      # Currently Chef Server is deployed on the same machine with Serengeti Server, and doesn't have this scalability.
      # So we limit the number of concurrent bootstrapping nodes to maximum_concurrent_nodes.
      max_nodes = maximum_concurrent_nodes
      if target.length > max_nodes and max_nodes > 0
        start = 0
        step = max_nodes
        while start < target.length
          step = [step, target.length - start].min
          ui.info "Bootstrapping nodes #{start} to #{start + step - 1} in cluster #{target.name}"
          partial_target = target.slice(start, step)
          watcher_threads = spawn_bootstrap_threads(partial_target)
          exit_status += watcher_threads.map{ |t| t.join.value }
          start += step
        end
      else
        watcher_threads = spawn_bootstrap_threads(target)
        exit_status += watcher_threads.map{ |t| t.join.value }
      end

      exit_status
    end

    def spawn_bootstrap_threads(target)
      target.parallelize do |svr|
        exit_value = bootstrap_server(svr)
        monitor_bootstrap_progress(target, svr, exit_value)
        exit_value
      end
    end

    def bootstrap_server(server)
      ip = server.fog_server.ipaddress
      if ip.to_s.empty?
        error = IRONFAN_ERRORS[:ERROR_IP_NOT_AVAILABLE]
        msg = error[:msg] % [server.name]
        ui.error msg
        set_error_msg(server.name, msg)
        return error[:code]
      end
      # Test SSH connection
      Chef::Log.debug("testing ssh connection to #{ip} of node #{server.name}")
      unless config[:dry_run]
        10.downto(0) do |i|
          break if tcp_test_ssh(ip)
          if i == 0
            error = IRONFAN_ERRORS[:ERROR_CAN_NOT_SSH_TO_NODE]
            msg = error[:msg] % [server.name, ip]
            ui.error msg
            set_error_msg(server.name, msg)
            return error[:code]
          end
          sleep 3
        end
      end
      # Run Bootstrap
      run_bootstrap(server, ip)
    end

    def tcp_test_ssh(hostname)
      tcp_socket = TCPSocket.new(hostname, 22)
      readable = IO.select([tcp_socket], nil, nil, 5)
      if readable
        Chef::Log.debug("sshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}")
        true
      else
        false
      end
    rescue Errno::ETIMEDOUT
      false
    rescue Errno::ECONNREFUSED
      false
    rescue Errno::ENETUNREACH
      false
    rescue
      false
    ensure
      tcp_socket && tcp_socket.close
    end

    def maximum_concurrent_nodes
      Chef::Config[:knife][:maximum_concurrent_nodes] || MAXIMUM_CONCURRENT_NODES
    end

    #
    # Utilities
    #

    def sub_command
      self.class.sub_command
    end

    def confirm_or_exit question, correct_answer
      response = ui.ask_question(question)
      unless response.chomp == correct_answer
        die "I didn't think so.", "Aborting!", 1
      end
      ui.info("")
    end

    #
    # Announce a new section of tasks
    #
    def section(desc, *style)
      style = [:green] if style.empty?
      ui.info(ui.color(desc, *style))
    end

    def exit_knife(target, exit_status)
      exit exit_status
    end

    def die *args
      Ironfan.die(*args)
    end

    module ClassMethods
      def sub_command
        self.to_s.gsub(/^.*::/, '').gsub(/^Cluster/, '').downcase
      end

      def import_banner_and_options(klass, options={})
        options[:except] ||= []
        deps{ klass.load_deps }
        klass.options.sort_by{|k,v| k.to_s}.each do |name, info|
          next if options.include?(name) || options[:except].include?(name)
          option name, info
        end
        options[:description] ||= "#{sub_command} all servers described by given cluster slice"
        banner "knife cluster #{"%-11s" % sub_command} CLUSTER[-FACET[-INDEXES]] (options) - #{options[:description]}"
      end
    end
    def self.included(base)
      base.class_eval do
        extend ClassMethods
      end
    end
  end
end

#
# Override the methods in Chef::Knife::Ssh to return the exit value of SSH command
#
# Need to explicitly require 'chef/knife/ssh' to ensure the methods defined here override the original one defined in 'chef/knife/ssh',
# because occasionally rubygem loads this file before the original 'chef/knife/ssh', then the overridden won't happen.
#
require 'chef/knife/ssh'

class Chef
  class Knife
    class Ssh < Knife
      def run
        extend Chef::Mixin::Command

        @longest = 0

        configure_attribute
        configure_user
        configure_identity_file
        configure_session

        exit_status = 
        case @name_args[1]
        when "interactive"
          interactive
        when "screen"
          screen
        when "tmux"
          tmux
        when "macterm"
          macterm
        when "csshx"
          csshx
        else
          ssh_command(@name_args[1..-1].join(" "))
        end

        session.close
        exit_status
      end

      def ssh_command(command, subsession=nil)
        exit_status = 0
        subsession ||= session
        command = fixup_sudo(command)
        subsession.open_channel do |ch|
          ch.request_pty
          ch.exec command do |ch, success|
            raise ArgumentError, "Cannot execute #{command}" unless success
            # note: you can't do the stderr calback because requesting a pty
            # squashes stderr and stdout together
            ch.on_data do |ichannel, data|
              print_data(ichannel[:host], data)
              if data =~ /^knife sudo password: /
                ichannel.send_data("#{get_password}\n")
              end
            end
            ch.on_request "exit-status" do |ichannel, data|
              exit_status = data.read_long
            end
          end
        end
        session.loop
        exit_status
      end
    end
  end
end
