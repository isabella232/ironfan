module Ironfan
  module Error

    IRONFAN_ERRORS = {
      :ERROR_BOOTSTRAP_FAILURE => {
        :code => 3,
        :msg => "Bootstrapping node %s failed. Please ssh to this node and run 'sudo chef-client' to get error details."
      },
      :ERROR_IP_NOT_AVAILABLE => {
        :code => 31,
        :msg => "node %s doesn't have an IP, will not bootstrap it."
      },
      :ERROR_CAN_NOT_SSH_TO_NODE => {
        :code => 32,
        :msg => "node %s has IP %s, but not able to ssh to this IP, so will not bootstrap it."
      },
    }

  end
end

