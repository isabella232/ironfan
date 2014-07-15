require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

require IRONFAN_DIR("lib/ironfan")

describe Ironfan do
  describe 'use knife to' do

    before :all do
      initialize_ironfan
    end

    it 'create a new cluster' do
      knife_create = get_knife(:create)
      run_knife(knife_create).should be_true
      # clear loaded clusters then newly created chef_clients and chef_nodes can be reloaded
      Ironfan.clear_clusters
    end

    it 'bootstap a cluster' do
      knife = get_knife(:bootstrap)
      run_knife(knife).should be_true
    end

    it 'stop a cluster' do
      knife = get_knife(:stop)
      run_knife(knife).should be_true
    end

    it 'start a cluster' do
      # mock startable?
      module Ironfan
        module Common
          class Server
            def startable?
              true
            end
          end
        end
      end

      get_knife(:bootstrap) # Load knife bootstrap which is depended on by knife start
      knife = get_knife(:start)
      #stop_cluster(knife_cluster_name)
      run_knife(knife).should be_true
    end

    it 'delete a cluster' do
      # delete the cluster and its chef nodes/clients, otherwise cluster create  will fail next time.
      knife = get_knife(:kill)
      run_knife(knife).should be_true
    end
  end
end
