// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./BRLA.sol";

contract BRLAV1_1 is BRLA {
    
    function transferWithPermit(
        address owner,
        address spender,
        address destination,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyRole(OPERATOR_ROLE) {
        permit(owner, spender, value, deadline, v, r, s);
        transferFrom(owner, destination, value);
    }

}
