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
require 'ironfan/vsphere/facet'
require 'ironfan/vsphere/server'
require 'ironfan/vsphere/server_slice'

module Ironfan
  module Vsphere
    CLUSTER_DEF_KEY = 'cluster_definition'
    GROUPS_KEY = 'groups'
    CLUSTER_CONF_KEY = 'cluster_configuration'

    class Cluster < Ironfan::Cluster

      def initialize(*args)
        super(:vsphere, *args)
      end

      def new_facet(*args)
        Ironfan::Vsphere::Facet.new(*args)
      end

      def servers
        svrs = @facets.map{ |name, facet| facet.servers.to_a }
        Ironfan::Vsphere::ServerSlice.new(self, svrs.flatten)
      end

      protected

      def create_cluster_role
        super
        save_cluster_configuration
      end

      # Save cluster configuration into cluster role
      def save_cluster_configuration
        conf = Ironfan::IaasProvider.cluster_spec[CLUSTER_DEF_KEY][CLUSTER_CONF_KEY]
        conf ||= {}
        if conf
          @cluster_role.default_attributes({ CLUSTER_CONF_KEY => conf })
        end
        conf
      end
    end
  end
end