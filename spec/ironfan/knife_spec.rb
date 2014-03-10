require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

require IRONFAN_DIR("lib/ironfan")

describe Ironfan do
  describe 'manage cluster using knife' do

    before :all do
      initialize_ironfan
    end

    it 'create and bootstap a new cluster' do
      knife_create = get_knife_create
      run_knife(knife_create).should be_true

      # delete the cluster and its chef nodes/clients, otherwise cluster create  will fail next time.
      knife_kill = get_knife_kill
      run_knife(knife_kill).should be_true
    end

  end
end

