#
#   Copyright (c) 2014 VMware, Inc. All Rights Reserved.
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

