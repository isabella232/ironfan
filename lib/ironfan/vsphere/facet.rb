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
  module Vsphere

    class Facet < Ironfan::Facet

      def initialize(*args)
        super(*args)
      end

      def new_server(*args)
        Ironfan::Vsphere::Server.new(*args)
      end

      protected

      def create_facet_role
        super
        save_cluster_configuration
      end

      # Save cluster configuration into facet role
      def save_cluster_configuration
        begin
          facets = Ironfan::IaasProvider.cluster_spec[CLUSTER_DEF_KEY][GROUPS_KEY]
          facet = facets.find { |f| f['name'] == facet_name.to_s }
          conf = facet[CLUSTER_CONF_KEY]
        rescue
          nil
        end

        conf ||= {}
        if conf
          @facet_role.default_attributes({ CLUSTER_CONF_KEY => conf })
        end
        conf
      end

    end

  end
end