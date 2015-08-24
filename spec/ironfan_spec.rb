require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

require IRONFAN_DIR("lib/ironfan")

describe "ironfan" do
  describe 'successfuly runs example' do

    describe 'cluster with ec2 provider:' do
      before :all do
        @cluster = get_example_cluster(:webserver_demo)
        @cluster.resolve!
      end

      it 'loads successfuly' do
        @cluster.should be_a(Ironfan::Cluster)
        @cluster.name.should == :webserver_demo
      end

      it 'cluster is right' do
        @cluster.to_hash.should == {
          "name"            => :webserver_demo,
          "chef_attributes" => { "webnode_count" => 6 },
          "environment" => :_default,
        }
      end

      it 'cluster cloud is right' do
        cloud_hash = @cluster.cloud.to_hash
        ["security_groups", "user_data"].each{|k| cloud_hash.delete k }
        cloud_hash.should == {
          "availability_zones" => ['us-east-1a'],
          "name"               => :ec2,
          "flavor"             => "t1.micro",
          "image_name"         => "maverick",
          "backing"            => "instance",
        }
      end

      it 'facet cloud is right' do
        cloud_hash = @cluster.facet(:webnode).cloud.to_hash
        ["security_groups", "user_data"].each{|k| cloud_hash.delete k }
        cloud_hash.should == {
          "name"               => :ec2,
          "backing"            => "ebs",
        }
      end

      it 'webnode facet are right' do
        @cluster.facets.length.should == 3
        fct = @cluster.facet(:webnode)
        fct.to_hash.should == {
          "name"            => :webnode,
          "chef_attributes" => {"split_testing" => {"group" => "A"}},
          "instances"       => 6,
        }
        fct.facet_role.name.should == "webserver_demo-webnode-facet"
        fct.run_list.should == ["role[nginx]", "role[redis_client]", "role[mysql_client]", "role[elasticsearch_client]", "role[awesome_website]"]
      end

      it 'dbnode facet are right' do
        fct = @cluster.facet(:dbnode)
        fct.to_hash.should == {
          "name"            => :dbnode,
          "chef_attributes" => {},
          "instances"      => 2
        }
        fct.facet_role.name.should == "webserver_demo-dbnode-facet"
        fct.run_list.should == ["role[mysql_server]", "role[redis_client]"]
        fct.cloud.flavor.should == 'c1.xlarge'
        fct.server(0).cloud.flavor.should == 'm1.large'
      end

      it 'esnode facets are right' do
        fct = @cluster.facet(:esnode)
        fct.to_hash.should == {
          "name"            => :esnode,
          "chef_attributes" => {},
          "instances"       => 1,
        }
        fct.facet_role.name.should == "webserver_demo-esnode-facet"
        fct.run_list.should == ["role[nginx]", "role[redis_server]", "role[elasticsearch_data_esnode]", "role[elasticsearch_http_esnode]"]
        fct.cloud.flavor.should == 'm1.large'
      end

      it 'cluster security groups are right' do
        gg = @cluster.security_groups
        gg.keys.should == ['ssh', 'webserver_demo', 'nfs_client']
      end

      it 'facet webnode security groups are right' do
        gg = @cluster.facet(:webnode).security_groups
        gg.keys.sort.should == ["nfs_client", "ssh", "webserver_demo", "webserver_demo-redis_client", "webserver_demo-webnode"]
      end

      it 'facet dbnode security groups are right' do
        gg = @cluster.facet(:dbnode).security_groups
        gg.keys.sort.should == ["nfs_client", "ssh", "webserver_demo", "webserver_demo-dbnode", "webserver_demo-redis_client"]
      end

      it 'facet esnode security groups are right' do
        gg = @cluster.facet(:esnode).security_groups
        gg.keys.sort.should == ["nfs_client", "ssh", "webserver_demo", "webserver_demo-esnode", "webserver_demo-redis_server"]
        gg['webserver_demo-redis_server'].name.should == "webserver_demo-redis_server"
        gg['webserver_demo-redis_server'].description.should == "ironfan generated group webserver_demo-redis_server"
        gg['webserver_demo-redis_server'].group_authorizations.should == [['webserver_demo-redis_client', nil]]
      end

      it 'has servers' do
        @cluster.servers.map(&:fullname).should == [
          "webserver_demo-webnode-0", "webserver_demo-webnode-1", "webserver_demo-webnode-2", "webserver_demo-webnode-3", "webserver_demo-webnode-4", "webserver_demo-webnode-5",
          "webserver_demo-dbnode-0", "webserver_demo-dbnode-1",
          "webserver_demo-esnode-0",
        ]
      end

      describe 'resolving servers gets right' do
        before do
          @server = @cluster.slice(:webnode, 5).first
          @server.resolve!
        end

        it 'node attributes' do
          @server.to_hash.should == {
            "name"            => 'webserver_demo-webnode-5',
            "run_list"        => ["role[ssh]", "role[nfs_client]", "role[big_package]", "role[nginx]", "role[redis_client]", "role[mysql_client]", "role[elasticsearch_client]", "role[awesome_website]", "role[webserver_demo-cluster]", "role[webserver_demo-webnode-facet]"],
            "instances" => 6,
            "environment" => :_default,
            "chef_attributes" => {
              "split_testing"  => {"group"=>"B"},
              # TODO the below means we have to include chef_attributes of the node's facet and cluster
              #"webnode_count"  => 6,
              #"node_name"      => "webserver_demo-webnode-5",
              #"cluster_name" => :webserver_demo, "facet_name" => :webnode, "facet_index" => 5,
            },
          }
        end

        it 'security groups' do
          @server.security_groups.keys.sort.should == ["nfs_client", "ssh", "webserver_demo", "webserver_demo-redis_client", "webserver_demo-webnode"]
        end

        it 'run list' do
          @server.combined_run_list.should == ["role[ssh]", "role[nfs_client]", "role[big_package]", "role[nginx]", "role[redis_client]", "role[mysql_client]", "role[elasticsearch_client]", "role[awesome_website]", "role[webserver_demo-cluster]", "role[webserver_demo-webnode-facet]"]
        end

        it 'user data' do
          @server.cloud.user_data.should == {
            "chef_server" => ENV['CHEF_SERVER_URL'],
            "cluster_name" => :webserver_demo,
            "facet_index" => 5,
            "facet_name" => :webnode,
            "node_name" => "webserver_demo-webnode-5",
            "organization" => nil,
            "run_list" => ["role[ssh]", "role[nfs_client]", "role[big_package]", "role[nginx]", "role[redis_client]", "role[mysql_client]", "role[elasticsearch_client]", "role[awesome_website]", "role[webserver_demo-cluster]", "role[webserver_demo-webnode-facet]"],
            "validation_client_name" => "chef-validator"
          }
        end

        it 'server cloud' do
          hsh = @server.cloud.to_hash
          ["security_groups", "user_data"].each{|k| hsh.delete k }
          hsh.should == {
            "name"               => :ec2,
            "availability_zones" => ["us-east-1c"],
            "flavor"             => "t1.micro",
            "image_name"         => "maverick",
            "backing"            => "ebs",
            "keypair" => :webserver_demo,
          }
        end
      end
    end

    describe 'cluster with vsphere provider:' do
      before :all do
        @cluster = get_example_cluster(:hadoopcluster)
        @cluster.resolve!
      end

      it 'loads successfuly' do
        @cluster.should be_a(Ironfan::Cluster)
        @cluster.name.should == :hadoopcluster
      end
    end
  end

  describe 'core module:' do

    before :all do
      require 'ironfan'
      Ironfan.ui = Chef::Knife.ui
    end

    it 'clean up clusters' do
      Ironfan.cluster_filenames.length.should > 0 # files in :cluster_path
      Ironfan.clusters.length.should > 0
      Ironfan.clear_clusters
      Ironfan.clusters.should == {}
    end

    it 'load a cluster after clean up' do
      c = Ironfan.load_cluster('webserver_demo')
      c.should be_a(Ironfan::Cluster)
      c.name.should == :webserver_demo
    end

    it 'call Ironfan.die will exit with the specified status code' do
      begin
        Ironfan.die('exit with code 3', 3)
      rescue SystemExit => e
        e.status.should == 3
      end
    end

    it 'call Ironfan.safely will catch any exception' do
      expect {
        Ironfan.safely do
          raise 'raise exception in safely block'
        end
      }.to_not raise_error
    end

  end
end
