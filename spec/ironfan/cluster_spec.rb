require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

require IRONFAN_DIR("lib/ironfan")

describe Ironfan::Cluster do
  describe 'load_cluster' do

    before :all do
      @cluster = create_hadoop_cluster_test
      @facet_master = @cluster.facets[:master]
      @facet_client = @cluster.facets[:client]
    end

    it 'saves cluster level configuration specified in cluster spec file' do
      @cluster.cluster_role.default_attributes['cluster_configuration'].should == get_cluster_configuration
      @cluster.cluster_role.override_attributes[:hadoop][:distro_name].should == 'apache'
    end

    it 'saves empty facet level configuration specified in cluster spec file' do
      @facet_master.facet_role.default_attributes['cluster_configuration'].should == get_facet_configuration(:master)
    end

    it 'saves non-empty facet level configuration specified in cluster spec file' do
      @facet_client.facet_role.default_attributes['cluster_configuration'].should == get_facet_configuration(:client)
    end
  end
end
