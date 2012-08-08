#
#   Portions Copyright (c) 2012 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

module Ironfan
  #
  # A server group is a set of actual or implied servers.
  #
  # The idea is we want to be able to smoothly roll up settings
  #
  #
  class ServerSlice < Ironfan::DslObject
    attr_reader :name, :servers, :cluster, :cloud

    def initialize cluster, servers, slice_name
      super()
      @name    = slice_name || cluster.name.to_s
      @cluster = cluster
      @cloud   = cluster.cloud
      @servers = servers
    end

    #
    # Enumerable
    #
    include Enumerable
    def each(&block)
      @servers.each(&block)
    end
    def length
      @servers.length
    end
    def empty?
      length == 0
    end
    [:select, :find_all, :reject, :detect, :find, :drop_while].each do |method|
      define_method(method) do |*args, &block|
        self.class.new cluster, @servers.send(method, *args, &block), self.name
      end
    end
    # true if slice contains a server with the given fullname (if arg is a
    # string) or same fullname as the given server (if a Server)
    #
    # @overload include?(server_fullname)
    #   @param [String] server_fullname checks for a server with that fullname
    # @overload include?(server)
    #   @param [Ironfan::Server] server checks for server with same fullname
    def include?(server)
      fullname = server.is_a?(String) ? server : server.fullname
      @servers.any?{|svr| svr.fullname == fullname }
    end

    # Return the collection of servers that are not yet 'created'
    def uncreated_servers
      select{|svr| not svr.created? }
    end

    def bogus_servers
      select(&:bogus?)
    end

    #
    # Info!
    #

    def cluster_name
      @cluster.cluster_name
    end

    def chef_nodes
      servers.map(&:chef_node).compact
    end

    def fog_servers
      servers.map(&:fog_server).compact
    end

    def facets
      servers.map(&:facet)
    end

    def chef_roles
      [ cluster.chef_roles, facets.map(&:chef_roles) ].flatten.compact.uniq
    end

    # hack -- take the ssh_identity_file from the first server.
    def ssh_identity_file
      return if servers.empty?
      servers.first.cloud.ssh_identity_file
    end

    #
    # Actions!
    #

    def start(bootstrap = false)
      delegate_to_fog_servers( :start  )
      delegate_to_fog_servers( :reload  )
    end

    def stop
      delegate_to_fog_servers( :stop )
      delegate_to_fog_servers( :reload  )
    end

    def destroy
      delegate_to_fog_servers( :destroy )
      delegate_to_fog_servers( :reload  )
    end

    def reload
      delegate_to_fog_servers( :reload  )
    end

    def create_servers( threaded = true )
      delegate_to_servers( :create_server, threaded )
    end

    def delete_chef
      delegate_to_servers( :delete_chef, true )
    end

    def sync_to_cloud
      delegate_to_servers( :sync_to_cloud )
    end

    def sync_to_chef
      sync_roles
      delegate_to_servers( :sync_to_chef )
      ensure_all_chef_nodes
    end

    #
    # Display Servers in console!
    #

    # FIXME: this is a jumble. we need to pass it in some other way.
    MINIMAL_HEADINGS  = ["Name", "Chef?", "State", "InstanceID", "Public IP", "Private IP", "Created At"].to_set.freeze
    DEFAULT_HEADINGS  = (MINIMAL_HEADINGS + ['Flavor', 'Image']).freeze
    EXPANDED_HEADINGS = DEFAULT_HEADINGS + ['Volumes', 'Env'].freeze

    #
    # This is a generic display routine for cluster-like sets of nodes. If you
    # call it with no args, you get the basic table that knife cluster show
    # draws.  If you give it an array of strings, you can override the order and
    # headings displayed. If you also give it a block you can add your own logic
    # for generating content. The block is given a Ironfan::Server instance
    # for each item in the collection and should return a hash of Name,Value
    # pairs to merge into the minimal fields.
    #
    def display hh = :default
      headings =
        case hh
        when :minimal  then MINIMAL_HEADINGS
        when :default  then DEFAULT_HEADINGS
        when :expanded then EXPANDED_HEADINGS
        else hh.to_set
        end
      headings += ["Bogus"] if servers.any?(&:bogus?)
      defined_data = servers.map do |svr|
        hsh = {
          "Name"   => svr.fullname,
          "Facet"  => svr.facet_name,
          "Index"  => svr.facet_index,
          "Chef?"  => (svr.chef_node? ? "yes" : "[red]no[reset]"),
          "Bogus"  => (svr.bogus? ? "[red]#{svr.bogosity}[reset]" : ''),
          "Env"    => svr.environment,
        }

        if (fs = svr.fog_server)
          hsh.merge!(
              "InstanceID" => (fs.id && fs.id.length > 0) ? fs.id : nil,
              "Flavor"     => fs.flavor_id,
              "Image"      => fs.image_id,
              "State"      => "[#{svr.running? ? 'green' : 'blue'}]#{fs.state}[reset]",
              "Public IP"  => fs.public_ip_address,
              "Private IP" => fs.private_ip_address,
              "Created At" => fs.created_at ? fs.created_at.strftime("%Y%m%d-%H%M%S") : nil
            )
        else
          hsh["State"] = "Not Exist"
        end

        if block_given?
          extra_info = yield(svr)
          hsh.merge!(extra_info)
          headings += extra_info.keys
        end
        hsh
      end

      if !defined_data.empty?
        Formatador.display_compact_table(defined_data, headings.to_a)
      end
    end

    def to_s
      str = super
      str[0..-2] + " #{@servers.map(&:fullname)}>"
    end

    def joined_names
      map(&:name).join(", ").gsub(/, ([^,]*)$/, ' and \1')
    end

    # Calls block on each server in parallel, each in its own thread
    #
    # @example
    #   target = Ironfan::Cluster.slice('web_server')
    #   target.parallelize{|svr| svr.launch }
    #
    # @yield each server, in turn
    #
    # @return [Array] array (in same order as servers) of each block's result
    def parallelize
      servers.map do |svr|
        sleep(0.1) # avoid hammering with simultaneous requests
        Thread.new(svr){|svr| yield(svr) }
      end
    end

  protected

    # Helper methods for iterating through the servers to do things
    #
    # @param [Symbol]  method   -- method to call on each server
    # @param [Boolean] threaded -- execute each call in own thread
    #
    # @return [Array] array (in same order as servers) of results for that method
    def delegate_to_servers method, threaded = true
      if threaded  # Call in threads
        threads = parallelize{|svr| svr.send(method) }
        threads.map{|t| t.join.value } # Wait, returning array of results
      else         # Call the method for each server sequentially
        servers.map{|svr| svr.send(method) }
      end
    end

    def delegate_to_fog_servers method
      fog_servers.compact.map do |fs|
        fs.send(method)
      end
    end

  end
end
