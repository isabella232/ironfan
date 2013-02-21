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

require 'cloud_manager'

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

    def initialize
      @connection_desc = @@connection_desc

      @servers = Servers.new(self)

      level = Chef::Log.level.to_s
      level = 'warning' if 'warn' == level
      Serengeti::CloudManager::Manager.set_log_level(level)
    end

    def create_cluster
      Serengeti::CloudManager::Manager.create_cluster(@connection_desc, :wait => false)
    end

    def delete_cluster
      Serengeti::CloudManager::Manager.delete_cluster(@connection_desc, :wait => false)
    end

    def stop_cluster
      Serengeti::CloudManager::Manager.stop_cluster(@connection_desc, :wait => false)
    end

    def start_cluster
      Serengeti::CloudManager::Manager.start_cluster(@connection_desc, :wait => false)
    end

    def config_cluster
      Serengeti::CloudManager::Manager.reconfig_cluster(@connection_desc, :wait => false)
    end

    def get_cluster
      Serengeti::CloudManager::Manager.list_vms_cluster(@connection_desc, :wait => true)
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
