require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

require IRONFAN_DIR("lib/ironfan")

describe Ironfan::Cluster do
  describe 'load_cluster' do

    before :all do
      @cluster = create_hadoop_cluster_test
    end

    it 'saves cluster configuration specified in cluster spec file' do
      @cluster.cluster_role.default_attributes['cluster_configuration'].should == get_cluster_configuration
      @cluster.cluster_role.override_attributes[:hadoop][:distro_name].should == 'apache'
    end
  end
end
