// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IBRLA {

    function burnFromWithPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function burnFrom(address account, uint256 amount) external;

    function transferFrom(address from, address to, uint256 amount) external;

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;

    function transferWithPermit(
        address owner,
        address spender,
        address destination,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

}