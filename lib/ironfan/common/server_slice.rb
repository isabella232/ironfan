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

require 'ironfan/monitor'

module Ironfan
  module Common
    class ServerSlice < Ironfan::ServerSlice
      include Ironfan::Monitor

      #
      # Override VM actions methods defined in base class
      #

      def start(bootstrap = false)
        set_chef_client_flag(bootstrap, true)

        start_monitor_progess(self)
        task = cloud.fog_connection.start_cluster
        while !task.finished?
          sleep(monitor_interval)
          monitor_start_progress(self, task.get_progress, !bootstrap)
        end
        monitor_start_progress(self, task.get_progress, !bootstrap)
        update_fog_servers(task.get_progress.result.servers)

        set_chef_client_flag(bootstrap, false)

        return task.get_result.succeed?
      end

      def stop
        start_monitor_progess(self)
        task = cloud.fog_connection.stop_cluster
        while !task.finished?
          sleep(monitor_interval)
          monitor_stop_progress(self, task.get_progress)
        end
        monitor_stop_progress(self, task.get_progress)
        update_fog_servers(task.get_progress.result.servers)

        return task.get_result.succeed?
      end

      def destroy
        return true if target_empty?
        start_monitor_progess(self)
        task = cloud.fog_connection.delete_cluster
        while !task.finished?
          sleep(monitor_interval)
          monitor_delete_progress(self, task.get_progress)
        end
        monitor_delete_progress(self, task.get_progress)
        update_fog_servers(task.get_progress.result.servers)

        return task.get_result.succeed?
      end

      def config
        return true if target_empty?
        start_monitor_progess(self)
        task = cloud.fog_connection.config_cluster
        while !task.finished?
          sleep(monitor_interval)
          monitor_config_progress(self, task.get_progress)
        end
        monitor_config_progress(self, task.get_progress)
        update_fog_servers(task.get_progress.result.servers)

        return task.get_result.succeed?
      end

      def create_servers(threaded = true)
        start_monitor_progess(self)
        task = cloud.fog_connection.create_cluster
        while !task.finished?
          sleep(monitor_interval)
          Chef::Log.debug("Reporting progress of creating cluster VMs: #{task.get_progress.inspect}")
          monitor_launch_progress(self, task.get_progress)
        end
        Chef::Log.debug("Result of creating cluster VMs: #{task.get_progress.inspect}")
        update_fog_servers(task.get_progress.result.servers)

        Chef::Log.debug("Reporting final status of creating cluster VMs")
        monitor_launch_progress(self, task.get_progress)

        return task.get_result.succeed?
      end

      # if serengeti server will run chef-client in the node, set the flag to tell the node not run chef-client when powered on by serengeti server,
      # so as to avoid conflict of the two running chef-client.
      def set_chef_client_flag(bootstrap, run_by_serengeti)
        if bootstrap
          nodes = cluster_nodes(self)
          nodes.each do |node|
            node[:run_by_serengeti] = run_by_serengeti
            node.save
          end
        end
      end

      protected

      # Update fog_servers of this ServerSlice with fog_servers returned by CloudManager
      def update_fog_servers(fog_servers)
        fog_servers.each do |fog_server|
          server = self.servers.find { |svr| svr.fullname == fog_server.name }
          server.fog_server = fog_server if server
        end
      end

      def target_empty?
        if self.empty? then
          report_refined_result(self, true)
          return true
        end
        return false
      end

    end
  end
end
