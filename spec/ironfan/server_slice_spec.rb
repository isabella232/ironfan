require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require IRONFAN_DIR("lib/ironfan")

describe Ironfan::ServerSlice do
  before do
    @cluster = get_example_cluster('webserver_demo')
    @slice = @cluster.slice(:webnode)
  end

  describe 'attributes' do
    it 'security groups' do
      @cluster.security_groups.keys.sort.should == [
        "nfs_client", "ssh", "webserver_demo"
      ]
      @slice.security_groups.keys.sort.should == [
        "nfs_client", "ssh", "webserver_demo",
        "webserver_demo-redis_client", "webserver_demo-webnode"
      ]
    end
  end
end
