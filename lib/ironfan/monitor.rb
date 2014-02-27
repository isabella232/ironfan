#
#   Copyright (c) 2012-2013 VMware, Inc. All Rights Reserved.
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

require 'ironfan/constants'

module Ironfan
  module Monitor
    include Ironfan::Error

    MONITOR_INTERVAL ||= 10

    # VM Status
    STATUS_VM_NOT_EXIST ||= 'Not Exist'
    STATUS_VM_READY ||= 'VM Ready'
    STATUS_VM_POWERED_ON ||= 'Powered On'
    STATUS_VM_POWERED_OFF ||= 'Powered Off'
    STATUS_BOOTSTRAP_SUCCEED ||= 'Service Ready'
    STATUS_BOOTSTRAP_FAIL ||= 'Bootstrap Failed'

    # Actions being performed on VM
    ACTION_BOOTSTRAP_VM ||= 'Bootstrapping VM'

    # flag name for aborting bootstrap
    ABORT_BOOTSTAP ||= 'abort'

    # Chef Roles which are depended on by other roles during bootstrapping
    KEY_ROLES ||= [
      'role[hadoop_namenode]', 'role[hadoop_jobtracker]', 'role[hadoop_resourcemanager]', 'role[hadoop_journalnode]',
      'role[hadoop_master]', 'role[hbase_master]', 'role[zookeeper]', 'role[hadoop_secondarynamenode]',
      'role[mapr_zookeeper]', 'role[mapr_mysql_server]'
    ]

    def start_monitor_bootstrap(target)
      Chef::Log.debug("Initialize monitoring bootstrap progress of cluster #{target.name}")
      nodes = cluster_nodes(target)
      nodes.each do |node|
        attrs = get_provision_attrs(node)
        attrs[:finished] = false
        attrs[:succeed] = nil
        attrs[:bootstrapped] = false
        attrs[:status] = STATUS_VM_READY
        attrs[:progress] = 10
        attrs[:action] = ACTION_BOOTSTRAP_VM
        attrs[:error_msg] = ''
        set_provision_attrs(node, attrs)
        node.save
      end

      unset_abort_signal(target.cluster_name.to_s)
    end

    def end_monitor_bootstrap(target)
      unset_abort_signal(target.cluster_name.to_s)
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
        attrs[:error_msg] = ''
        set_provision_attrs(node, attrs)
        node.save
      end
    end

    def monitor_iaas_action_progress(target, progress, is_last_action = false)
      progress.result.servers.each do |vm|
        next unless target.include?(vm.name)

        # Get VM attributes
        attrs = vm.to_hash
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
        set_provision_attrs(node, attrs)
        node.save
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
        attrs[:status] = STATUS_BOOTSTRAP_SUCCEED
        attrs[:error_msg] = ''
      else
        attrs[:finished] = true
        attrs[:bootstrapped] = false
        attrs[:succeed] = false
        attrs[:status] = STATUS_BOOTSTRAP_FAIL
        # error_msg will be set by chef-client on the node when chef-client exits
        attrs[:error_msg] = IRONFAN_ERRORS[:ERROR_BOOTSTRAP_FAILURE][:msg] % [svr.fullname] if attrs[:error_msg].to_s.empty?

        handle_node_failure(svr)
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
      monitor_iaas_action_progress(target, progress, true)
    end

    def monitor_config_progress(target, progress)
      Chef::Log.debug("Begin reporting progress of configuring cluster #{target.name}: #{progress.inspect}")
      monitor_iaas_action_progress(target, progress, true)
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

    def report_cluster_data(target)
      target.servers.each do |svr|
        vm = svr.fog_server

        node = Chef::Node.load(svr.name.to_s)
        attrs = vm ? JSON.parse(vm.to_hash.to_json) : {}
        attrs.delete("action") unless attrs.empty?
        if vm.nil?
          attrs["status"] = STATUS_VM_NOT_EXIST
          attrs["ip_address"] = nil
        elsif svr.running?
          attrs.delete("status")
          if vm.public_ip_address.nil?
            attrs["status"] = STATUS_VM_POWERED_ON
          else
            attrs["status"] = STATUS_VM_READY
          end
          if node["provision"]["bootstrapped"]
            attrs["status"] = STATUS_BOOTSTRAP_SUCCEED
          else
            attrs["status"] = STATUS_BOOTSTRAP_FAIL
          end
        else
          attrs["status"] = STATUS_VM_POWERED_OFF
        end

        set_provision_attrs(node, get_provision_attrs(node).merge(attrs.to_mash))
        node.save
      end
    end

    # If any key nodes (e.g. namenode/jobtracker) failed during bootstrapping, notify all nodes of cluster to stop bootstrapping.
    def handle_node_failure(server)
      return if get_abort_signal(server.cluster_name.to_s) # if abort signal already is set, no need to set twice
      roles = server.combined_run_list
      roles.each do |role|
        if KEY_ROLES.include?(role)
          Chef::Log.error("The node with #{role} failed during bootstrapping.")
          set_abort_signal(server.cluster_name.to_s)
          break
        end
      end
    end

    # Set a signal to tell all nodes to stop bootstrapping
    def set_abort_signal(cluster_name)
      Chef::Log.info("The abort signal is set to notify all nodes in cluster #{cluster_name} to stop bootstrapping.")
      save_databag_item(cluster_name, cluster_name, { ABORT_BOOTSTAP => true })
    end

    # Unset the abort bootstrapping signal
    def unset_abort_signal(cluster_name)
      Chef::Log.debug("Unset abort signal.")
      save_databag_item(cluster_name, cluster_name, { ABORT_BOOTSTAP => false })
    end

    # Get the abort bootstrapping signal
    def get_abort_signal(cluster_name)
      item = get_databag_item(cluster_name, cluster_name)
      item ? item.raw_data[ABORT_BOOTSTAP] : nil
    end

    # Save a Chef DataBag Item
    def save_databag_item(data_bag_name, item_name, item_value)
      databag = Chef::DataBag.load(data_bag_name) rescue databag = nil
      if databag.nil?
        databag = Chef::DataBag.new
        databag.name(data_bag_name)
        databag.create
      end

      databag_item = Chef::DataBagItem.load(data_bag_name, item_name) rescue databag_item = nil
      databag_item ||= Chef::DataBagItem.new
      item_value['id'] = item_name

      changed = false
      item_value.each do |key, value|
        if databag_item.raw_data[key] != value
          changed = true
          break
        end
      end
      if changed
        databag_item.data_bag(data_bag_name)
        databag_item.raw_data.merge!(item_value)
        databag_item.save
      end
    end

    # Get a Chef DataBag Item
    def get_databag_item(data_bag_name, item_name)
      databag_item = Chef::DataBagItem.load(data_bag_name, item_name) rescue databag_item = nil
      databag_item
    end

    protected

    def get_provision_attrs(chef_node)
      chef_node[:provision] ? chef_node[:provision].dup : Mash.new
    end

    def set_provision_attrs(chef_node, attrs)
      chef_node.normal[:provision] = attrs.to_mash
    end

    def set_error_msg(node_name, msg = '')
      chef_node = Chef::Node.load(node_name)
      attrs = get_provision_attrs(chef_node)
      if attrs[:error_msg] != msg
        attrs[:error_msg] = msg
        set_provision_attrs(chef_node, attrs)
        chef_node.save
      end
    end
  end
end
