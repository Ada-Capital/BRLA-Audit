// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IyBRLA {

    function mint(uint256 brlaAmount) external;

    function unstake(address from, address to, uint256 yBrlaAmount) external;

    function _currentPrice() external view returns (int128);

    function _currentPriceInv() external view returns (int128);

}