#
#   Copyright (c) 2012-2014 VMware, Inc. All Rights Reserved.
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
  module Common
    class Server < Ironfan::Server

      def initialize(*args)
        super(*args)
      end

      #
      # Override VM attributes methods defined in base class
      #

      def running?
        has_cloud_state?('poweredOn') ||
        has_cloud_state?('VM Ready') ||
        has_cloud_state?('Service Ready') ||
        has_cloud_state?('Bootstrap Failed')
      end

      def startable?
        has_cloud_state?('poweredOff') ||
        has_cloud_state?('Powered Off')
      end

      def sync_ipconfig_attribute
        super
        return if fog_server.nil? or fog_server.ip_configs.nil?
        @chef_node.normal[:ip_configs] = fog_server.ip_configs
      end

      def sync_volume_attributes
        super
        return if fog_server.nil? or fog_server.volumes.nil? or fog_server.volumes.empty?
        mount_point_to_device = {}
        device_to_disk = {}
        swap_disk = nil
        i = 0
        fog_server.volumes.each do |disk|
          if disk.start_with?("DATA")
            # disk uuid fetch from WS is: DATA:6000C298-2b5d-f41a-2581-1b07e74971e8
            # disk uuid shown in OS is: scsi-36000c2982b5df41a25811b07e74971e8
            # the logic partion is: scsi-36000c2982b5df41a25811b07e74971e8-part1
            uuid_in_os = "scsi-3" + disk.split(":")[1].gsub("-", "").downcase
            raw_disk = "/dev/disk/by-id/" + uuid_in_os
            device = "/dev/disk/by-id/" + uuid_in_os + "-part1"
            mount_point = "/mnt/data#{i}"
            mount_point_to_device[mount_point] = device
            device_to_disk[device] = raw_disk
            i += 1
          else
            swap_disk = "/dev/disk/by-id/scsi-3" + disk.split(":")[1].gsub("-", "").downcase
          end
        end
        @chef_node.normal[:disk][:data_disks]  = mount_point_to_device
        @chef_node.normal[:disk][:disk_devices] = device_to_disk
        @chef_node.normal[:disk][:swap_disk] = swap_disk

        # cannot gurantee node[:disk][:data_disks].keys.last can always get the same 
        # disk considering cluster fix feature, so we need to save root log dir in Chef to make 
        # sure hadoop log is written to the same place after reboot.
        # Another issue is "cluster fix" may delete the disk where root log dir 
        # locates on.
        pre_log_root_dir = @chef_node.normal[:disk][:hadoop_log_root_dir]
        if pre_log_root_dir.nil? or !mount_point_to_device.has_key?(pre_log_root_dir)
          @chef_node.normal[:disk][:hadoop_log_root_dir] = mount_point_to_device.keys.last
        end
      end
    end
  end
end
