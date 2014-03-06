require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

require IRONFAN_DIR("lib/ironfan")

describe Ironfan do
  describe 'manage cluster using knife' do

    before :all do
      initialize_ironfan

      @cluster_name = "hadoop_cluster_test"
      @cluster_filename = File.join(Ironfan.cluster_path.first, "#{@cluster_name}.rb")
      File.delete(@cluster_filename) if File.exists?(@cluster_filename)
      @cluster = Ironfan::create_cluster(IRONFAN_DIR('spec/data/cluster_definition.json'), true)
    end

    it 'create and bootstap a new cluster' do
      knife_create = get_knife_create
      begin
        knife_create.run
      rescue SystemExit => e
        e.success?.should be_true
      end
    end

  end
end

