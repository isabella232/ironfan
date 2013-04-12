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
  module Static
    class CloudManager

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
         attr_accessor :tags

         def initialize(hash)
            @id                 = hash["id"]
            @name               = hash["name"]
            @hostname           = hash["hostname"]
            @physical_host      = hash["hostname"]
            @rack               = hash["rack"]
            @ip_address         = hash["ip_address"]
            @ipaddress          = hash["ip_address"]
            @private_ip_address = hash["ip_address"]
            @public_ip_address  = hash["ip_address"]
            @volumes            = hash["volumes"] || ['/dev/sdc']
            @state              = hash["status"]
            @status             = hash["status"]
            @action             = hash["action"]
            @created            = hash["created"]
            @deleted            = hash["deleted"]
            @ha                 = hash["ha"]
            @created_at         = hash["created_at"]

            node = load_chef_node @name
            if !node.nil? && !node[:provision].nil?
               node[:provision][:status] = @status
               node.save
            end
         end

         def state
            node = load_chef_node @name
            if !node.nil? && !node[:provision].nil?
               state = node[:provision][:status]
            end
            state || @state
         end

         def to_hash
            attrs = {}     
            attrs[:name]          = @name
            attrs[:hostname]      = @hostname
            attrs[:physical_host] = @hostname
            attrs[:ip_address]    = @ip_address
            attrs[:status]        = @status
            attrs[:action]        = @action
            attrs[:finished]      = true
            attrs[:succeed]       = true
            attrs[:progress]      = 100
            attrs[:created]       = @created
            attrs[:deleted]       = @deleted
            attrs[:rack]          = @rack
            attrs[:error_code]    = 0
            attrs[:error_msg]     = 'success'
            attrs[:ha]            = @ha

            attrs
         end

         def get_progress
            100
         end

         protected
         def load_chef_node name
           begin
             return Chef::Node.load(@name)
           rescue Net::HTTPServerException => e
             raise unless Array('404').include?(e.response.code)
             return nil
           end
         end
      end

      # IaaS mock
      class IaasTask
        class Result
          def initialize servers
            @servers = servers
          end

          def servers
            @servers
          end

          def succeed?
            true
          end

          def total
            @servers.length
          end

          def success
            @servers.length
          end

          def failure
            0
          end

          def running
            true
          end

          def error_msg
            'success'
          end
        end

        class Progress
          def initialize servers
            @servers = servers
          end
          def result
            Result.new @servers
          end

          def progress
            100
          end

          def finished?
            true
          end
        end

        def initialize servers
          @servers = servers
        end

        def get_result
          Result.new @servers
        end

        def get_progress
          Progress.new @servers
        end

        def finished?
          true
        end
           
        def succeed?
          true
        end
      end

      def set_log_level level
      end

      def create_cluster cluster_spec, options
        IaasTask.new load_servers(cluster_spec)
      end

      def delete_cluster cluster_spec, options
        IaasTask.new load_servers(cluster_spec, true)
      end

      def start_cluster cluster_spec, options
        IaasTask.new load_servers(cluster_spec)
      end

      def stop_cluster cluster_spec, options
        IaasTask.new load_servers(cluster_spec)
      end

      def list_vms_cluster cluster_spec, options
        IaasTask.new load_servers(cluster_spec)
      end
      
      # Load VMs from cluster defination file
      def load_servers_from_file cluster_def_file, deleted = false
        spec = JSON.parse File.read(cluster_def_file)
        load_servers spec deleted
      end

      def load_servers spec, deleted = false
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
    end
  end
end
