// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable@4.8.0/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/access/AccessControlUpgradeable.sol";

contract BRLA is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PermitUpgradeable, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public ownerWallet;
    address public operatorWallet;
    address public pauserWallet;
    address public complianceWallet;
    
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// Granted to blacklisted addresses
    bytes32 public constant BLACKLISTED = keccak256("BLACKLISTED");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address operator,
        address pauser,
        address compliance
    ) initializer public {

        __ERC20_init("BRLA Token", "BRLA");
        __ERC20Permit_init("BRLA Token");
        __ERC20Burnable_init();
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        ownerWallet = msg.sender;
        operatorWallet = operator;
        pauserWallet = pauser;
        complianceWallet = compliance;

        _grantRole(OWNER_ROLE, msg.sender);
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);

        _grantRole(OPERATOR_ROLE, operator);
        _setRoleAdmin(OPERATOR_ROLE, OPERATOR_ROLE);

        _grantRole(PAUSER_ROLE, pauser);
        _setRoleAdmin(PAUSER_ROLE, PAUSER_ROLE);
        
        _grantRole(COMPLIANCE_ROLE, compliance);
        _setRoleAdmin(COMPLIANCE_ROLE, COMPLIANCE_ROLE);
        _setRoleAdmin(BLACKLISTED, COMPLIANCE_ROLE);

    }

    function mint(address to, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        _mint(to, amount);
    }

    function burnFromWithPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyRole(OPERATOR_ROLE) {
        require(msg.sender == spender);
        permit(owner, spender, value, deadline, v, r, s);
        burnFrom(owner, value);
    }

    function rescueERC20(
        IERC20Upgradeable token,
        address to,
        uint256 amount
    ) external onlyRole(OWNER_ROLE) {
        token.safeTransfer(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function blockAddress(address addr) external onlyRole(COMPLIANCE_ROLE) {
        _grantRole(BLACKLISTED, addr);
    }

    function unblockAddress(address addr) external onlyRole(COMPLIANCE_ROLE) {
        _revokeRole(BLACKLISTED, addr);
    }

    function updateOwner(address newOwner) external onlyRole(OWNER_ROLE) {
        _grantRole(OWNER_ROLE, newOwner);
        renounceRole(OWNER_ROLE, ownerWallet);
        ownerWallet = newOwner;
    }

    function updatePauser(address newPauser) external onlyRole(PAUSER_ROLE) {
        _grantRole(PAUSER_ROLE, newPauser);
        renounceRole(PAUSER_ROLE, pauserWallet);
        pauserWallet = newPauser;
    }

    function updateOperator(address newOperator) external onlyRole(OPERATOR_ROLE) {
        _grantRole(OPERATOR_ROLE, newOperator);
        renounceRole(OPERATOR_ROLE, operatorWallet);
        operatorWallet = newOperator;
    }

    function updateCompliance(address newCompliance) external onlyRole(COMPLIANCE_ROLE) {
        _grantRole(COMPLIANCE_ROLE, newCompliance);
        renounceRole(COMPLIANCE_ROLE, complianceWallet);
        complianceWallet = newCompliance;
    }

    function isWhiteListed(address addr) internal view {
        require(!hasRole(BLACKLISTED, addr));
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        isWhiteListed(from);
        isWhiteListed(to);
        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(OWNER_ROLE)
        override
    {}

}
