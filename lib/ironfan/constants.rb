module Ironfan
  module Error

    IRONFAN_ERRORS = {
      :ERROR_BOOTSTRAP_FAILURE => {
        :code => 3,
        :msg => "Cannot bootstrap node %s. SSH to this node and run the command 'sudo chef-client' to view error messages."
      },
      :ERROR_IP_NOT_AVAILABLE => {
        :code => 31,
        :msg => "Cannot bootstrap node %s because it does not have an IP address."
      },
      :ERROR_CAN_NOT_SSH_TO_NODE => {
        :code => 32,
        :msg => "Unable to SSH to node %s with the IP address %s, so cannot bootstrap the node."
      },
    }

  end
end

