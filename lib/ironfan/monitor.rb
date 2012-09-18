#
#   Copyright (c) 2012 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

module Ironfan
  module Monitor
    MONITOR_INTERVAL ||= 10

    # VM Status
    STATUS_VM_NOT_EXIST ||= 'Not Exist'
    STATUS_BOOTSTAP_SUCCEED ||= 'Service Ready'
    STATUS_BOOTSTAP_FAIL ||= 'Bootstrap Failed'

    # Actions being performed on VM
    ACTION_CREATE_VM ||= 'Creating VM'
    ACTION_BOOTSTRAP_VM ||= 'Bootstrapping VM'

    # Error Message
    ERROR_BOOTSTAP_FAIL ||= 'Bootstrapping VM failed.'

    def start_monitor_bootstrap(target)
      Chef::Log.debug("Initialize monitoring bootstrap progress of cluster #{target.name}")
      nodes = cluster_nodes(target)
      nodes.each do |node|
        attrs = get_provision_attrs(node)
        attrs[:finished] = false
        attrs[:succeed] = nil
        attrs[:bootstrapped] = false
        attrs[:progress] = 50
        attrs[:action] = ACTION_BOOTSTRAP_VM
        set_provision_attrs(node, attrs)
        node.save
      end

      report_progress(target)
    end

    def start_monitor_progess(target)
      Chef::Log.debug("Initialize monitoring progress of cluster #{target.name}")
      nodes = cluster_nodes(target)
      nodes.each do |node|
        attrs = get_provision_attrs(node)
        attrs[:finished] = false
        attrs[:succeed] = nil
        attrs[:progress] = 0
        attrs[:action] = ''
        set_provision_attrs(node, attrs)
        node.save
      end
    end

    def monitor_iaas_action_progress(target, progress, is_last_action = false)
      if progress.result.servers.empty? || (progress.finished? and !progress.result.succeed?)
        report_refined_progress(target, progress)
        return
      end

      has_progress = false
      progress.result.servers.each do |vm|
        next unless target.include?(vm.name)

        # Get VM attributes
        attrs = vm.to_hash
        # when creating VM is done, set the progress to 50%; once bootstrapping VM is done, set the progress to 100%
        attrs[:progress] = vm.get_progress / 2 if !is_last_action
        # reset to correct status
        if !is_last_action and attrs[:finished] and attrs[:succeed]
          attrs[:finished] = false
          attrs[:succeed] = nil
        end

        # Save progress data to ChefNode
        node = Chef::Node.load(vm.name)
        if (node[:provision] and
            node[:provision][:progress] == attrs[:progress] and
            node[:provision][:action] == attrs[:action])

          Chef::Log.debug("skip updating server #{vm.name} since no progress")
          next
        end
        has_progress = true
        set_provision_attrs(node, attrs)
        node.save
      end

      if has_progress
        report_progress(target)
      else
        Chef::Log.debug("skip reporting cluster status since no progress")
      end
    end

    def monitor_bootstrap_progress(target, svr, exit_code)
      Chef::Log.debug("Monitoring bootstrap progress of cluster #{target.name} with data: #{[exit_code, svr]}")

      # Save progress data to ChefNode
      node = Chef::Node.load(svr.fullname)
      attrs = get_provision_attrs(node)
      if exit_code == 0
        attrs[:finished] = true
        attrs[:bootstrapped] = true
        attrs[:succeed] = true
        attrs[:status] = STATUS_BOOTSTAP_SUCCEED
        attrs[:error_msg] = ''
      else
        attrs[:finished] = true
        attrs[:bootstrapped] = false
        attrs[:succeed] = false
        attrs[:status] = STATUS_BOOTSTAP_FAIL
        attrs[:error_msg] = ERROR_BOOTSTAP_FAIL
      end
      attrs[:action] = ''
      attrs[:progress] = 100
      set_provision_attrs(node, attrs)
      node.save
    end

    # Monitor the progress of cluster creation
    def monitor_launch_progress(target, progress)
      Chef::Log.debug("Begin reporting progress of launching cluster #{target.name}: #{progress.inspect}")
      monitor_iaas_action_progress(target, progress)
    end

    # report progress of deleting cluster to MessageQueue
    def monitor_delete_progress(target, progress)
      Chef::Log.debug("Begin reporting progress of deleting cluster #{target.name}: #{progress.inspect}")
      if progress.finished?
        # if not all VMs of the cluster exists in vCenter (e.g. execute 'cluster kill' after 'cluster launch' failed),
        # monitor_iaas_action_progress() won't work, so call report_refined_progress().
        report_refined_progress(target, progress)
      else
        monitor_iaas_action_progress(target, progress, true)
      end
    end

    # report progress of stopping cluster to MessageQueue
    def monitor_stop_progress(target, progress)
      Chef::Log.debug("Begin reporting progress of stopping cluster #{target.name}: #{progress.inspect}")
      monitor_iaas_action_progress(target, progress, true)
    end

    # report progress of starting cluster to MessageQueue
    def monitor_start_progress(target, progress, is_last_action)
      Chef::Log.debug("Begin reporting progress of starting cluster #{target.name}: #{progress.inspect}")
      monitor_iaas_action_progress(target, progress, is_last_action)
    end

    # report cluster provision progress without VM detail info to MessageQueue
    def report_refined_progress(target, progress)
      cluster = Mash.new
      cluster[:progress] = progress.progress
      cluster[:finished] = progress.finished?
      cluster[:succeed] = progress.result.succeed?
      cluster[:total] = progress.result.total
      cluster[:success] = progress.result.success
      cluster[:failure] = progress.result.failure
      cluster[:running] = progress.result.running
      cluster[:error_msg] = progress.result.error_msg
      cluster[:cluster_data] = Mash.new
      cluster[:cluster_data][:name] = get_cluster_name(target.name)

      data = JSON.parse(cluster.to_json)

      # send to MQ
      send_to_mq(data)
    end

    def report_refined_result(target, succeed)
      cluster = Mash.new
      cluster[:progress] = 100
      cluster[:finished] = true
      cluster[:succeed] = succeed
      cluster[:total] = target.length
      cluster[:success] = target.length
      cluster[:failure] = 0
      cluster[:running] = 0
      cluster[:error_msg] = ''
      cluster[:cluster_data] = Mash.new
      cluster[:cluster_data][:name] = get_cluster_name(target.name)

      data = JSON.parse(cluster.to_json)

      # send to MQ
      send_to_mq(data)
    end

    # report cluster provision progress to MessageQueue
    def report_progress(target)
      Chef::Log.debug("Begin reporting status of cluster #{target.name}")

      data = get_cluster_data(target)

      merge_nodes_data(data)

      # send to MQ
      send_to_mq(data)
      Chef::Log.debug('End reporting cluster status')
    end

    def send_to_mq(data)
      if (@last_data == data.to_json)
        Chef::Log.debug("Skip reporting progress since no change")
        return
      end
      @last_data = data.to_json

      Chef::Log.debug("About to send data to MessageQueue: \n#{data.pretty_inspect}")

      return if monitor_disabled?

      require 'bunny'

      # load MessageQueque configuration
      mq_server = Chef::Config[:knife][:rabbitmq_host]
      mq_exchange_id = Chef::Config[:knife][:rabbitmq_exchange]
      mq_channel_id = Chef::Config[:knife][:rabbitmq_channel]

      b = Bunny.new(:host => mq_server, :logging => false)
      # start a communication session with the RabbitMQ server
      b.start

      # create/get exchange
      exch = b.exchange(mq_exchange_id, :durable => true)

      # publish message to exchange
      exch.publish(data.to_json, :key => mq_channel_id)

      # message should now be picked up by the consumer so we can stop
      b.stop
    end

    def monitor_disabled?
      if Chef::Config[:knife][:monitor_disabled]
        Chef::Log.warn('Monitoring is disabled. Will not send message to MQ.')
        return true
      else
        return false
      end
    end

    def monitor_interval
      Chef::Config[:knife][:monitor_interval] || MONITOR_INTERVAL
    end

    def get_cluster_name(target_name)
      target_name.split('-')[0]
    end

    def cluster_nodes(target)
      target_name = target.name
      cluster_name = get_cluster_name(target_name)
      nodes = []
      Chef::Search::Query.new.search(:node, "cluster_name:#{cluster_name}") do |n|
        # only return the nodes related to this target
        nodes.push(n) if n.name.start_with?(target_name) and target.include?(n.name)
      end
      raise "Can't find any Chef Nodes belonging to cluster #{target_name}." if nodes.empty?
      nodes.sort_by! { |n| n.name }
    end

    # generate cluster nodes data in JSON format
    def get_cluster_data(target)
      cluster = Mash.new
      cluster[:total] = 0
      cluster[:success] = 0
      cluster[:failure] = 0
      cluster[:running] = 0
      cluster[:finished] = false
      cluster[:succeed] = nil
      cluster[:progress] = 0
      cluster[:error_msg] = ''
      cluster[:cluster_data] = Mash.new
      groups = cluster[:cluster_data][:groups] = Mash.new
      nodes = cluster_nodes(target)
      nodes.each do |node|
        server = get_provision_attrs(node).to_mash
        # create groups
        group = groups[node.facet_name] || Mash.new
        group[:name] ||= node.facet_name
        group[:instances] ||= []
        group[:instances] << server
        groups[node.facet_name] = group
        # create cluster summary
        cluster[:success] += 1 if server[:finished] and server[:succeed]
        cluster[:failure] += 1 if server[:finished] and !server[:succeed]
        cluster[:running] += 1 if !server[:finished]
        cluster[:progress] += server[:progress] || 0
      end
      cluster[:total] = nodes.length
      cluster[:progress] /= cluster[:total] if cluster[:total] != 0
      cluster[:finished] = (cluster[:running] == 0)
      cluster[:succeed] = (cluster[:success] == cluster[:total])
      cluster[:error_msg] = ERROR_BOOTSTAP_FAIL if cluster[:finished] and !cluster[:succeed]

      JSON.parse(cluster.to_json) # convert keys from symbol to string
    end

    def report_cluster_data(target)
      target.servers.each do |svr|
        vm = svr.fog_server

        node = Chef::Node.load(svr.name.to_s)
        attrs = vm ? JSON.parse(vm.to_json) : {}
        attrs.delete("action") unless attrs.empty?
        if vm.nil?
          attrs["status"] = 'Not Exist'
        elsif svr.running?
          attrs.delete("status")
        else
          attrs["status"] = 'Powered Off'
        end
        set_provision_attrs(node, get_provision_attrs(node).merge(attrs))
        node.save
      end

      cluster = Mash.new
      cluster[:progress] = 100
      cluster[:finished] = true
      cluster[:succeed] = !target.nil? and !target.empty?
      cluster[:total] = target.length
      cluster[:success] = target.length
      cluster[:failure] = 0
      cluster[:running] = 0
      cluster[:error_msg] = ''
      cluster[:cluster_data] = Mash.new
      cluster[:cluster_data][:name] = get_cluster_name(target.name)
      groups = cluster[:cluster_data][:groups] = Mash.new
      nodes = cluster_nodes(target)
      nodes.each do |node|
        server = get_provision_attrs(node).to_mash
        # create groups
        group = groups[node.facet_name] || Mash.new
        group[:name] ||= node.facet_name
        group[:instances] ||= []
        group[:instances] << server
        groups[node.facet_name] = group
      end

      data = JSON.parse(cluster.to_json)

      merge_nodes_data(data)

      # send to MQ
      send_to_mq(data)
    end

    protected

    def get_provision_attrs(chef_node)
      chef_node[:provision] ? chef_node[:provision].to_hash : Hash.new
    end

    def set_provision_attrs(chef_node, attrs)
      chef_node[:provision] = attrs
    end

    # merge nodes data with cluster definition
    def merge_nodes_data(data)
      groups = data['cluster_data']['groups']
      cluster_meta = cloud.fog_connection.connection_desc['cluster_definition'].dup
      cluster_meta['groups'].delete_if { |x| !groups[x['name']] }
      cluster_meta['groups'].each do |meta_group|
        meta_group['instances'] = groups[meta_group['name']]['instances']
      end
      data['cluster_data'].merge!(cluster_meta)
    end
  end
end
