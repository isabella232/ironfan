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
  module Static
    class ServerSlice < Ironfan::ServerSlice
      include Ironfan::Monitor

      #
      # Define VM info for code backward compitibility
      #
      class VmInfo
         attr_accessor :id
         attr_accessor :name
         attr_accessor :hostname
         attr_accessor :physical_host
         attr_accessor :rack
         attr_accessor :ip_address
         attr_accessor :ipaddress
         attr_accessor :public_ip_address
         attr_accessor :private_ip_address
         attr_accessor :volumes
         attr_accessor :flavor_id
         attr_accessor :image_id
         attr_accessor :volumes
         attr_accessor :state
         attr_accessor :status
         attr_accessor :action
         attr_accessor :created
         attr_accessor :deleted
         attr_accessor :ha
         attr_accessor :created_at

         def initialize(hash)
            @id                 = hash["id"]
            @name               = hash["name"]
            @hostname           = hash["hostname"]
            @physical_host      = hash["physical_host"]
            @rack               = hash["rack"]
            @ip_address         = hash["ip_address"]
            @ipaddress          = hash["ip_address"]
            @private_ip_address = hash["ip_address"]
            @public_ip_address  = hash["ip_address"]
            @volumes            = []
            @state              = hash["state"]
            @status             = hash["status"]
            @action             = hash["action"]
            @created            = hash["created"]
            @deleted            = hash["deleted"]
            @ha                 = hash["ha"]
            @created_at         = hash["created_at"]
         end
      end

      #
      # Override VM actions methods defined in base class
      #

      def start(cluster_def_file, bootstrap = false)
        update_fog_servers(load_servers_from_file(cluster_def_file))
        true
      end

      def stop(cluster_def_file)
        update_fog_servers(load_servers_from_file(cluster_def_file))
        true
      end

      def destroy
        true
      end

      def create_servers(cluster_def_file, threaded = true)
        update_fog_servers(load_servers_from_file(cluster_def_file))
        true
      end

      protected


      # Load VMs from cluster defination file
      def load_servers_from_file cluster_def_file, deleted = false
         spec = JSON.parse File.read(cluster_def_file)

         groups = spec["cluster_data"]["groups"]
         instances = groups.collect{|g| g["instances"]}.reduce([]) {|acc, e| acc.concat e}

         # append deleted/created flag for compatibility
         vms = instances.map do |vm_hash|
            vm_hash["created"] = true if !deleted
            vm_hash["deleted"] = true if deleted
            VmInfo.new vm_hash
         end

         Chef::Log.debug("Result of loading cluster VMs: #{vms.inspect}")
         vms
      end

      # Update fog_servers of this ServerSlice with fog_servers returned by CloudManager
      def update_fog_servers(fog_servers)
        fog_servers.each do |fog_server|
          server = self.servers.find { |svr| svr.fullname == fog_server.name }
          server.fog_server = fog_server if server
        end
      end

    end
  end
end
