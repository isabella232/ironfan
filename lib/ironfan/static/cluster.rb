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

require 'ironfan'
require 'ironfan/static/facet'
require 'ironfan/static/server'
require 'ironfan/static/server_slice'

module Ironfan
  module Static
    CLUSTER_DEF_KEY = 'cluster_definition'
    GROUPS_KEY = 'groups'
    CLUSTER_CONF_KEY = 'cluster_configuration'
    RACK_TOPOLOGY_POLICY_KEY = 'rack_topology_policy'
    HTTP_PROXY = 'http_proxy'

    class Cluster < Ironfan::Cluster

      def initialize(*args)
        super(:static, *args)
      end

      def new_facet(*args)
        Ironfan::Static::Facet.new(*args)
      end

      def sync_cluster_role
        super
        save_rack_topology
      end

      protected

      def create_cluster_role
        super
        save_cluster_configuration
        save_http_proxy_configuration
      end

      def new_slice(*args)
        Ironfan::Static::ServerSlice.new(*args)
      end

      # Save cluster configuration into cluster role
      def save_cluster_configuration
        conf = cluster_attributes(CLUSTER_CONF_KEY)
        conf ||= {}
        merge_to_cluster_role({ CLUSTER_CONF_KEY => conf })
      end

      # Save http_proxy setting
      def save_http_proxy_configuration
        conf = {}
        conf[:http_proxy] = cluster_attributes(HTTP_PROXY) || Chef::Config[:knife][:bootstrap_proxy]
        conf[:http_proxy] = nil if conf[:http_proxy].to_s.empty?
        merge_to_cluster_role(conf)
        Chef::Config[:knife][:bootstrap_proxy] = conf[:http_proxy] # http_proxy will be used in chef bootstrap script
      end

      # save rack topology used by Hadoop
      def save_rack_topology
        topology_policy = cluster_attributes(RACK_TOPOLOGY_POLICY_KEY)
        topology_policy.upcase! if topology_policy
        topology_enabled = (topology_policy and topology_policy != 'NONE')
        topology_hve_enabled = (topology_policy and topology_policy == 'HVE')
        topology = self.servers.collect do |svr|
          vm = svr.fog_server
          next if !vm or !vm.ipaddress or !vm.physical_host
          rack = vm.rack.to_s.empty? ? 'default-rack' : vm.rack
          case topology_policy
          when 'RACK_AS_RACK'
            "#{vm.ipaddress} /#{rack}"
          when 'HOST_AS_RACK'
            "#{vm.ipaddress} /#{vm.physical_host}"
          when 'HVE'
            "#{vm.ipaddress} /#{rack}/#{vm.physical_host}"
          else
            nil
          end
        end
        topology = topology.join("\n")

        conf = {
          :hadoop => {
            :rack_topology => {
              :enabled => topology_enabled,
              :hve_enabled => topology_hve_enabled,
              :data => topology
            }
          }
        }
        Chef::Log.debug('saving Rack Topology to cluster role: ' + conf.to_s)
        merge_to_cluster_role(conf)
      end

      def cluster_attributes(key)
        Ironfan::IaasProvider.cluster_spec[CLUSTER_DEF_KEY][key] rescue nil
      end
    end
  end
end
