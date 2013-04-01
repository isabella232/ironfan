#
# Author:: Philip (flip) Kromer (<flip@infochimps.com>)
# Copyright:: Copyright (c) 2011 Infochimps, Inc
# Portions Copyright (c) 2012-2013 VMware, Inc. All Rights Reserved.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require File.expand_path('ironfan_script',       File.dirname(__FILE__))

class Chef
  class Knife
    class ClusterStart < Ironfan::Script
      import_banner_and_options(Ironfan::Script)

      deps do
        require 'time'
        require 'socket'
        Chef::Knife::ClusterBootstrap.load_deps
      end

      option :bootstrap,
        :long        => "--[no-]bootstrap",
        :description => "Also bootstrap the launched node (default is NOT to bootstrap)",
        :boolean     => true,
        :default     => false
      option :set_chef_client_flag,
        :long        => "--set-chef-client-flag [true|false]",
        :description => "Instead of running bootstrap, set chef client flag and return"

      def relevant?(server)
        server.startable?
      end

      def perform_execution(target)
        if config[:set_chef_client_flag] == 'true'
          target.set_chef_client_flag(true, true) if !target.empty?
          return SUCCESS
        end
        if config[:set_chef_client_flag] == 'false'
          target.set_chef_client_flag(true, false) if !target.empty?
          return SUCCESS
        end
        section("Starting cluster #{target_name}")
        ret = target.start(config[:bootstrap])
        die('Starting cluster failed. Abort!', START_FAILURE) if !ret

        # Sync vm ip, vm attached disks, vm rack and other info to Chef
        section("Sync'ing to chef after cluster VMs are started")
        target.sync_to_chef

        exit_status = 0
        if config[:bootstrap]
          exit_status = bootstrap_cluster(target)
        end

        section("Starting cluster #{target_name} completed.")
        return exit_status
      end
    end
  end
end
