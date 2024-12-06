// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "hardhat/console.sol";
import "./interfaces/IBRLA.sol";
import "./libs/ABDKMath64x64.sol";

contract StakedBRLA is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PausableUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant BLACKLISTED = keccak256("BLACKLISTED");

    address public brla;

    error TooHighProfitability();
    error NothingIsStaked();

    event RewardsDistributed(uint256 rewards, uint256 brlaBalanceAtTime);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address compliance, address distributor, address upgrader, address _brla)
        initializer public
    {
        __ERC20_init("Staked BRLA", "stBRLA");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __ERC20Permit_init("Staked BRLA");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(COMPLIANCE_ROLE, compliance);
        _setRoleAdmin(COMPLIANCE_ROLE, COMPLIANCE_ROLE);
        _setRoleAdmin(BLACKLISTED, COMPLIANCE_ROLE);

        _grantRole(DISTRIBUTOR_ROLE, distributor);
        _setRoleAdmin(DISTRIBUTOR_ROLE, DISTRIBUTOR_ROLE);

        _grantRole(UPGRADER_ROLE, upgrader);
        _setRoleAdmin(UPGRADER_ROLE, UPGRADER_ROLE);
        

        brla = _brla;
    }

    function pause() public onlyRole(COMPLIANCE_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(COMPLIANCE_ROLE) {
        _unpause();
    }

    function stake(address to, uint256 brlaAmount) public {
        int128 currentPriceInv = _currentPriceInv();
        IERC20(brla).safeTransferFrom(_msgSender(), address(this), brlaAmount);
        uint256 stBrlaAmount = ABDKMath64x64.mulu(currentPriceInv, brlaAmount);
        _mint(to, stBrlaAmount);
    }

    function unstake(address from, address to, uint256 stBrlaAmount) public {
        int128 currentPrice = _currentPrice();
        if (_msgSender() == from) {
            burn(stBrlaAmount);
        } else {
            burnFrom(from, stBrlaAmount);
        }
        uint256 brlaAmount = ABDKMath64x64.mulu(currentPrice, stBrlaAmount);
        IERC20(brla).safeTransfer(to, brlaAmount);
    }

    function unstakeWithPermit(address from, address to, uint256 stBrlaAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) public {
        int128 currentPrice = _currentPrice();
        if (_msgSender() == from) {
            burn(stBrlaAmount);
        } else {
            permit(from, _msgSender(), stBrlaAmount, deadline, v, r, s);
            burnFrom(from, stBrlaAmount);
        }
        uint256 brlaAmount = ABDKMath64x64.mulu(currentPrice, stBrlaAmount);
        IERC20(brla).safeTransfer(to, brlaAmount);
    }

    function _currentPrice() public view returns (int128) {
        if (totalSupply() == 0) { return ABDKMath64x64.fromUInt(1); }
        return ABDKMath64x64.divu(
            IERC20(brla).balanceOf(address(this)),
            totalSupply()
            );
    }

    function _currentPriceInv() public view returns (int128) {
        if (totalSupply() == 0) { return ABDKMath64x64.fromUInt(1); }
        return ABDKMath64x64.divu(
            totalSupply(),
            IERC20(brla).balanceOf(address(this))
            );
    }

    function blockAddress(address addr) external onlyRole(COMPLIANCE_ROLE) {
        _grantRole(BLACKLISTED, addr);
    }

    function unblockAddress(address addr) external onlyRole(COMPLIANCE_ROLE) {
        _revokeRole(BLACKLISTED, addr);
    }

    function distributeRewards(uint256 numerator, uint256 denominator) public onlyRole(DISTRIBUTOR_ROLE) {
        if (100*numerator > denominator) {
            revert TooHighProfitability();
        }
        if (IERC20(brla).balanceOf(address(this)) == 0) {
            revert NothingIsStaked();
        }

        int128 profitability = ABDKMath64x64.divu(numerator, denominator);
        uint256 brlaBal = IERC20(brla).balanceOf(address(this));
        uint256 rewards = ABDKMath64x64.mulu(profitability, brlaBal);

        IBRLA(brla).mint(address(this), rewards);

        emit RewardsDistributed(rewards, brlaBal);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {   
        require(!hasRole(BLACKLISTED, from));
        require(!hasRole(BLACKLISTED, to));
        super._update(from, to, value);
    }
}
