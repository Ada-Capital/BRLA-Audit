// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//import "hardhat/console.sol";
import "./libs/StakePermitUpgradeable.sol";
import "./interfaces/IBRLA.sol";
import "./interfaces/IyBRLA.sol";
import "./libs/ABDKMath64x64.sol";

contract yBRLANFT is Initializable, ERC721Upgradeable, ERC721PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable, StakePermitUpgradeable {
    using Strings for uint256;
    using SafeERC20 for IERC20;
    
    error CanRedeemAlready();
    error CannotRedeemYet();
    error TokenNotYours();
    error SharesSurpassBalance();

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 private _nextTokenId;
    address public brla;
    address public yBRLA;

    struct StakeData {
        uint256 initialLockedValueBrla;
        uint256 totalyBRLAShares;
        uint256 currentyBRLAShares;
        uint256 stakedAt;
    }

    mapping(uint256 tokenId => StakeData) public stakedData;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin, 
        address _brla,
        address _yBRLA)
        initializer public
    {
        __ERC721_init("yBRLA NFT", "yBRLA NFT");

        __EIP712_init("yBRLA NFT", "1");
        __ERC721Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, defaultAdmin);

        brla = _brla;
        yBRLA = _yBRLA;
        IERC20(brla).approve(_yBRLA, type(uint256).max);
    }

    function pause() public onlyRole(ADMIN_ROLE) { _pause(); }

    function unpause() public onlyRole(ADMIN_ROLE) { _unpause(); }

    function stake(uint256 brlaAmount, address to) public whenNotPaused() {
        IERC20(brla).safeTransferFrom(_msgSender(), address(this), brlaAmount);
        uint256 initialyBRLABal = IERC20(yBRLA).balanceOf(address(this));
        IyBRLA(yBRLA).mint(brlaAmount);
        uint256 finalyBRLABal = IERC20(yBRLA).balanceOf(address(this));

        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        stakedData[tokenId] = StakeData({
            initialLockedValueBrla: brlaAmount,
            totalyBRLAShares: finalyBRLABal-initialyBRLABal,
            currentyBRLAShares: finalyBRLABal-initialyBRLABal,
            stakedAt: block.timestamp
        });
    }

    function unstakeEarlier(uint256 tokenId, uint256 shares, address to) public whenNotPaused() {
        if (!_isAuthorized(ownerOf(tokenId), _msgSender(), tokenId)) { revert TokenNotYours(); }
        StakeData memory data = stakedData[tokenId];
        if (block.timestamp >= data.stakedAt + 2592000) { revert CanRedeemAlready(); }
        if (shares > data.currentyBRLAShares) { revert SharesSurpassBalance(); }

        data.currentyBRLAShares -= shares;
        uint256 brlaAmount = ABDKMath64x64.mulu(ABDKMath64x64.divu(shares, data.totalyBRLAShares), data.initialLockedValueBrla);
        stakedData[tokenId] = data;
        uint256 initialBrlaBalance = IERC20(brla).balanceOf(address(this));
        IyBRLA(yBRLA).unstake(address(this), address(this), shares);
        uint256 finalBrlaBalance = IERC20(brla).balanceOf(address(this));
        IERC20(brla).safeTransfer(to, brlaAmount);
        IBRLA(brla).burn(finalBrlaBalance-initialBrlaBalance-brlaAmount);
    }

    function convertToLiquidTokens(uint256 tokenId, address to) public whenNotPaused() {
        if (!_isAuthorized(ownerOf(tokenId), _msgSender(), tokenId)) { revert TokenNotYours(); }
        StakeData memory data = stakedData[tokenId];
        if (block.timestamp < data.stakedAt + 2592000) { revert CannotRedeemYet(); }

        uint256 sharesToGive = data.currentyBRLAShares;
        data.currentyBRLAShares = 0;
        stakedData[tokenId] = data;

        IERC20(yBRLA).safeTransfer(to, sharesToGive);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable)
        returns (string memory)
    {
        _requireOwned(tokenId);

        StakeData memory data = stakedData[tokenId];
        
        string memory json = string(abi.encodePacked(
            '{',
                '"name": "yBRLA BRLA NFT #', Strings.toString(tokenId), '",',
                '"description": "Can be redeemed for liquid tokens after 30 days.",',
                '"attributes": [',
                    '{',
                        '"trait_type": "Initial Locked Value Brla",',
                        '"value": "', Strings.toString(data.initialLockedValueBrla), '"',
                    '},',
                    '{',
                        '"trait_type": "Current yBRLA Shares",',
                        '"value": "', Strings.toString(data.currentyBRLAShares), '"',
                    '},',
                    '{',
                        '"trait_type": "Staked At",',
                        '"value": "', Strings.toString(data.stakedAt), '"',
                    '}',
                ']',
            '}'
        ));
        
        string memory encodedJson = Base64.encode(bytes(json));
        return string(abi.encodePacked("data:application/json;base64,", encodedJson));
    }

    // The following functions are overrides required by Solidity.

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(ADMIN_ROLE)
        override
    {}

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721PausableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
