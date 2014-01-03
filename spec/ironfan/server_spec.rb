require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require IRONFAN_DIR("lib/ironfan")

describe Ironfan::Server do

  Ironfan::DryRunnable.class_eval do
    def unless_dry_run
      puts "Not doing that"
    end
  end

  before do
    @cluster = get_example_cluster('webserver_demo')
    @cluster.resolve!
    @facet   = @cluster.facet(:dbnode)
    @server  = @facet.server(0)
  end

  describe 'volumes' do
    describe '#composite_volumes' do
      it 'assembles cluster, facet and server volumes' do
        @cluster.volumes.length.should == 0
        @facet.volumes.length.should   == 1
        @server.volumes.length.should  == 1
        @server.composite_volumes.length.should == 1
      end

      it 'composites server attributes onto a volume defined in the facet' do
        vol = @server.composite_volumes['data'].to_mash.symbolize_keys
        vol.should == {
          :name              => :data,
          :tags              => {},
          :snapshot_id       => "snap-d9c1edb1",
          :size              => 50,
          :keep              => true,
          :create_at_launch  => true,
          :device            => "/dev/sdi",
          :mount_point       => "/data/db",
          :mount_options     => "defaults,nouuid,noatime",
          :availability_zone => "us-east-1a"
        }
      end

      it 'makes block_device_mapping for non-ephemeral storage' do
        vol = @server.composite_volumes['data']
        vol.block_device_mapping.should == {
          "DeviceName"              => "/dev/sdi",
          "Ebs.SnapshotId"          => "snap-d9c1edb1",
          "Ebs.VolumeSize"          => "50",
          "Ebs.DeleteOnTermination" => "false"
        }
      end

      it 'skips block_device_mapping for non-ephemeral storage if volume id is present' do
        vol = @facet.server(1).composite_volumes['data']
        vol.block_device_mapping.should be_nil
      end

    end
  end

  describe 'launch' do
    describe '#fog_launch_description' do
      it 'has right attributes' do

        hsh = @server.fog_launch_description
        hsh.delete(:user_data)
        hsh.should == {
          :image_id             => "ami-08f40561",
          :flavor_id            => "m1.large",
          :groups               => ["webserver_demo-dbnode", "webserver_demo-redis_client", "ssh", "webserver_demo", "nfs_client"],
          :key_name             => "webserver_demo",
          :tags                 => {:cluster=>:webserver_demo, :facet=>:dbnode, :index=>0},
          :block_device_mapping => [
            {"DeviceName"=>"/dev/sdi", "Ebs.SnapshotId"=>"snap-d9c1edb1", "Ebs.VolumeSize"=>"50", "Ebs.DeleteOnTermination"=>"false"}
          ],
          :availability_zone    => "us-east-1a",
          :monitoring           => nil
        }
      end

      it 'has right user_data' do
        hsh = @server.fog_launch_description
        user_data_hsh = JSON.parse( hsh[:user_data] )
        user_data_hsh.keys.should == [
          "chef_server", "validation_client_name", "node_name",
          "organization", "cluster_name", "facet_name", "facet_index",
          "run_list", "validation_key"
        ]
        user_data_hsh["attributes"].should == nil
      end
    end

  end
end
