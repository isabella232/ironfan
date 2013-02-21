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


module Ironfan
  class IaasProvider
    attr_reader :servers
    attr_reader :connection_desc

    def self.init(description)
      @@connection_desc = description
    end

    def self.cluster_spec
      @@connection_desc
    end

    def initialize provider
      @connection_desc = @@connection_desc

      @servers = Servers.new(self)

      @cloud_manager = Ironfan.new_cloud_manager(provider)

      set_log_level
    end

    def set_log_level
      level = Chef::Log.level.to_s
      level = 'warning' if 'warn' == level
      @cloud_manager.set_log_level(level)
    end

    def create_cluster
      @cloud_manager.create_cluster(@connection_desc, :wait => false)
    end

    def delete_cluster
      @cloud_manager.delete_cluster(@connection_desc, :wait => false)
    end

    def stop_cluster
      @cloud_manager.stop_cluster(@connection_desc, :wait => false)
    end

    def start_cluster
      @cloud_manager.start_cluster(@connection_desc, :wait => false)
    end

    def config_cluster
      Serengeti::CloudManager::Manager.reconfig_cluster(@connection_desc, :wait => false)
    end

    def get_cluster
      @cloud_manager.list_vms_cluster(@connection_desc, :wait => true)
    end
  end

  class IaasCollection
  end

  class Servers < IaasCollection
    def initialize(provider)
      @provider = provider
    end

    def all
      @provider.get_cluster.get_result.servers
    end
  end
end
