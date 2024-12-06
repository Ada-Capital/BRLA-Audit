// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "./interfaces/IBRLA.sol";
import "./interfaces/IMetaTransaction.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";


contract CentralizedBRLAUSDSwapV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable, EIP712Upgradeable, AccessControlUpgradeable {
    
    event Swap(address indexed owner, address indexed receiver, address indexed usdToken, uint256 brlaAmount, uint256 usdAmount, bool usdToBrla);
    event PartialBrlaSwap(address indexed owner, uint256 brlaAmount);
    event PartialUsdSwap(address indexed owner, address indexed usdToken, uint256 usdAmount);
    event PixIn(address indexed elbowWallet, address indexed destinationWallet, uint256 brlaAmount);
    event PixOut(address indexed sourceWallet, address indexed elbowWallet, uint256 brlaAmount);

    using SafeERC20 for IERC20;

    address public brla;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _brla) initializer public {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        brla = _brla;
    }

    event AuthorizedSwap(address indexed inputWallet, address indexed outputWallet, address indexed operator, uint256 brlaAmount, uint256 usdAmount, uint256 markupFee, address usdToken, bool usdToBrla, bytes32 nonce, uint256 deadline);

    enum AuthorizationState { Unused, Used, Canceled }
    mapping(address => mapping(bytes32 => AuthorizationState)) private _authorizationStates;

    function initializeV1_1() reinitializer(2) public {
        __EIP712_init("CentralizedBRLAUSDSwap", "1");
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    ISwapRouter public swapRouter;

    function initializeV2(address admin, ISwapRouter _swapRouter) reinitializer(4) public {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        swapRouter = _swapRouter;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    error SwapAuthorizationExpiredDeadline();
    error SwapAuthorizationOperatorNotSender();
    error SwapAuthorizationNotUnused();
    error SwapAuthorizationInvalidSignature();

    struct AuthorizedSwapParams {
        address inputWallet;
        address outputWallet;
        address operator;
        uint256 brlaAmount;
        uint256 usdAmount;
        uint256 markupFee;
        address usdToken;
        bool usdToBrla;
        bytes32 nonce;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function checkSwapAuthorization(
        AuthorizedSwapParams memory params) internal {
        if (block.timestamp > params.deadline) { revert SwapAuthorizationExpiredDeadline(); }
        if (params.operator != _msgSender()) { revert SwapAuthorizationOperatorNotSender(); }
        if (_authorizationStates[params.operator][params.nonce] != AuthorizationState.Unused) { revert SwapAuthorizationNotUnused(); }

        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            keccak256("AuthorizedSwap(address inputWallet,address outputWallet,address operator,uint256 brlaAmount,uint256 usdAmount,uint256 markupFee,address usdToken,bool usdToBrla,bytes32 nonce,uint256 deadline)"),
            params.inputWallet,
            params.outputWallet,
            params.operator,
            params.brlaAmount,
            params.usdAmount,
            params.markupFee,
            params.usdToken,
            params.usdToBrla,
            params.nonce,
            params.deadline
        )));

        if (ECDSAUpgradeable.recover(digest, params.v, params.r, params.s) != owner()) { revert SwapAuthorizationInvalidSignature(); }

        _authorizationStates[params.operator][params.nonce] = AuthorizationState.Used;
        emit AuthorizedSwap(
            params.inputWallet,
            params.outputWallet,
            params.operator,
            params.brlaAmount,
            params.usdAmount,
            params.markupFee,
            params.usdToken,
            params.usdToBrla,
            params.nonce,
            params.deadline
        );

    }

    function brlaToUsdWithAuthorization(
        AuthorizedSwapParams memory params
        ) public {
        if (params.usdToBrla != false) { revert SwapAuthorizationInvalidSignature(); }

        checkSwapAuthorization(params);

        IBRLA(brla).burnFrom(params.inputWallet, params.brlaAmount);
        IERC20(params.usdToken).safeTransfer(params.outputWallet, params.usdAmount);
        if (params.markupFee > 0) {
            IERC20(params.usdToken).safeTransfer(params.operator, params.markupFee);
        }
        emit Swap(params.inputWallet, params.outputWallet, params.usdToken, params.brlaAmount, params.usdAmount, false);
    }

    function brlaToUsdWithPermitWithAuthorization(
        AuthorizedSwapParams memory params,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) public {
        if (params.usdToBrla != false) { revert SwapAuthorizationInvalidSignature(); }

        checkSwapAuthorization(params);

        IBRLA(brla).burnFromWithPermit(params.inputWallet, address(this), params.brlaAmount, deadline, v, r, s);
        IERC20(params.usdToken).safeTransfer(params.outputWallet, params.usdAmount);
        if (params.markupFee > 0) {
            IERC20(params.usdToken).safeTransfer(params.operator, params.markupFee);
        }
        emit Swap(params.inputWallet, params.outputWallet, params.usdToken, params.brlaAmount, params.usdAmount, false);
    }

    function usdToBrlaWithPermitWithAuthorization(
        AuthorizedSwapParams memory params,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) public {
        if (params.usdToBrla != true) { revert SwapAuthorizationInvalidSignature(); }

        checkSwapAuthorization(params);

        IERC20Permit(params.usdToken).permit(params.inputWallet, address(this), params.usdAmount, deadline, v, r, s);
        IERC20(params.usdToken).safeTransferFrom(params.inputWallet, address(this), params.usdAmount);
        IBRLA(brla).mint(params.outputWallet, params.brlaAmount);
        if (params.markupFee > 0) {
            IBRLA(brla).mint(params.operator, params.markupFee);
        }
        emit Swap(params.inputWallet, params.outputWallet, params.usdToken, params.brlaAmount, params.usdAmount, true);
    }

    function usdToBrlaWithMetaTxWithAuthorization(
        AuthorizedSwapParams memory params,
        bytes memory functionSignature,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV) public {
        if (params.usdToBrla != true) { revert SwapAuthorizationInvalidSignature(); }

        checkSwapAuthorization(params);

        IMetaTransaction(params.usdToken).executeMetaTransaction(params.inputWallet, functionSignature, sigR, sigS, sigV);
        IERC20(params.usdToken).safeTransferFrom(params.inputWallet, address(this), params.usdAmount);
        IBRLA(brla).mint(params.outputWallet, params.brlaAmount);
        if (params.markupFee > 0) {
            IBRLA(brla).mint(params.operator, params.markupFee);
        }
        emit Swap(params.inputWallet, params.outputWallet, params.usdToken, params.brlaAmount, params.usdAmount, true);
    }

    function usdToBrlaWithAuthorization(
        AuthorizedSwapParams memory params
        ) public {
        if (params.usdToBrla != true) { revert SwapAuthorizationInvalidSignature(); }

        checkSwapAuthorization(params);

        IERC20(params.usdToken).safeTransferFrom(params.inputWallet, address(this), params.usdAmount);
        IBRLA(brla).mint(params.outputWallet, params.brlaAmount);
        if (params.markupFee > 0) {
            IBRLA(brla).mint(params.operator, params.markupFee);
        }
        emit Swap(params.inputWallet, params.outputWallet, params.usdToken, params.brlaAmount, params.usdAmount, true);
    }

    function brlaToUsd(
        address usdToken,
        uint256 brlaAmount, 
        uint256 usdAmount, 
        uint256 markupFee, 
        address _owner,
        address receiver,
        address markupReceiver) public onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).burnFrom(_owner, brlaAmount);
        IERC20(usdToken).safeTransfer(receiver, usdAmount);
        if (markupFee > 0) {
            IERC20(usdToken).safeTransfer(markupReceiver, markupFee);
        }
        emit Swap(_owner, receiver, usdToken, brlaAmount, usdAmount, false);
    }

    function brlaToUsdWithPermit(
        address usdToken,
        uint256 brlaAmount, 
        uint256 usdAmount, 
        uint256 markupFee, 
        address _owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address receiver,
        address markupReceiver) public onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).burnFromWithPermit(_owner, address(this), brlaAmount, deadline, v, r, s);
        IERC20(usdToken).safeTransfer(receiver, usdAmount);
        if (markupFee > 0) {
            IERC20(usdToken).safeTransfer(markupReceiver, markupFee);
        }
        emit Swap(_owner, receiver, usdToken, brlaAmount, usdAmount, false);
    }

    struct UsdToBrlaWithPermitParams {
        address usdToken;
        uint256 brlaAmount; 
        uint256 usdAmount;
        uint256 markupFee;
        address _owner;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
        address receiver;
        address markupReceiver;
    }

    function usdToBrlaWithPermit(UsdToBrlaWithPermitParams memory params) public onlyRole(OPERATOR_ROLE) {
        IERC20Permit(params.usdToken).permit(params._owner, address(this), params.usdAmount, params.deadline, params.v, params.r, params.s);
        IERC20(params.usdToken).safeTransferFrom(params._owner, address(this), params.usdAmount);
        IBRLA(brla).mint(params.receiver, params.brlaAmount);
        if (params.markupFee > 0) {
            IBRLA(brla).mint(params.markupReceiver, params.markupFee);
        }
        emit Swap(params._owner, params.receiver, params.usdToken, params.brlaAmount, params.usdAmount, true);
    }

    struct UsdToBrlaWithMetaTxParams {
        address usdToken;
        uint256 brlaAmount; 
        uint256 usdAmount;
        uint256 markupFee;
        address userAddress;
        bytes functionSignature;
        bytes32 sigR;
        bytes32 sigS;
        uint8 sigV;
        address receiver;
        address markupReceiver;
    }

    function usdToBrlaWithMetaTx(UsdToBrlaWithMetaTxParams memory params) public onlyRole(OPERATOR_ROLE) {
        IMetaTransaction(params.usdToken).executeMetaTransaction(params.userAddress, params.functionSignature, params.sigR, params.sigS, params.sigV);
        IERC20(params.usdToken).safeTransferFrom(params.userAddress, address(this), params.usdAmount);
        IBRLA(brla).mint(params.receiver, params.brlaAmount);
        if (params.markupFee > 0) {
            IBRLA(brla).mint(params.markupReceiver, params.markupFee);
        }
        emit Swap(params.userAddress, params.receiver, params.usdToken, params.brlaAmount, params.usdAmount, true);
    }

    function usdToBrla(
        address usdToken,
        uint256 brlaAmount,
        uint256 usdAmount, 
        uint256 markupFee,
        address _owner,
        address receiver,
        address markupReceiver
        ) public onlyRole(OPERATOR_ROLE) {
        IERC20(usdToken).safeTransferFrom(_owner, address(this), usdAmount);
        IBRLA(brla).mint(receiver, brlaAmount);
        if (markupFee > 0) {
            IBRLA(brla).mint(markupReceiver, markupFee);
        }
        emit Swap(_owner, receiver, usdToken, brlaAmount, usdAmount, true);
    }

    function partialBrlaSwap(
        uint256 brlaAmount, 
        address _owner) public onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).burnFrom(_owner, brlaAmount);
        emit PartialBrlaSwap(_owner, brlaAmount);
    }

    function partialBrlaSwapWithPermit(
        uint256 brlaAmount, 
        address _owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) public onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).burnFromWithPermit(_owner, address(this), brlaAmount, deadline, v, r, s);
        emit PartialBrlaSwap(_owner, brlaAmount);
    }

    function partialUsdSwap(
        address usdToken,
        address _owner,
        address markupReceiver,
        uint256 usdAmount,
        uint256 markupFee) public onlyRole(OPERATOR_ROLE) {
        IERC20(usdToken).safeTransfer(_owner, usdAmount);
        if (markupFee > 0) {
            IERC20(usdToken).safeTransfer(markupReceiver, markupFee);
        }
        emit PartialUsdSwap(_owner, usdToken, usdAmount);
    }

    function mintToUsd(
        address usdToken,
        uint256 brlaAmount, 
        uint256 usdAmount, 
        uint256 markupFee,
        address _owner,
        address receiver,
        address markupReceiver) public onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).mint(_owner, brlaAmount);
        brlaToUsd(usdToken, brlaAmount, usdAmount, markupFee, _owner, receiver, markupReceiver);
    }

    function mintToUsdWithPermit(
        address usdToken,
        uint256 brlaAmount, 
        uint256 usdAmount, 
        uint256 markupFee,
        address _owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address receiver,
        address markupReceiver) public onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).mint(_owner, brlaAmount);
        brlaToUsdWithPermit(usdToken, brlaAmount, usdAmount, markupFee, _owner, deadline, v, r, s, receiver, markupReceiver);
    }

    function partialMintToUsd(
        uint256 brlaAmount, 
        address _owner) public onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).mint(_owner, brlaAmount);
        partialBrlaSwap(brlaAmount, _owner);
    }

    function partialMintToUsdWithPermit(
        uint256 brlaAmount, 
        address _owner,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) public onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).mint(_owner, brlaAmount);
        partialBrlaSwapWithPermit(brlaAmount, _owner, deadline, v, r, s);
    }

    function burnFromWithPermit(
        address owner,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) external onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).burnFromWithPermit(owner, address(this), value, deadline, v, r, s);
    }

    function burnFromWithPermitCoveringFees(
        address owner,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address coverAddress, uint256 fee) external onlyRole(OPERATOR_ROLE) {
        if (IERC20(brla).balanceOf(coverAddress) >= fee) {
            IBRLA(brla).burnFrom(coverAddress, fee);
        }
        IBRLA(brla).burnFromWithPermit(owner, address(this), value, deadline, v, r, s);
    }

    function burnFrom(
        address owner,
        uint256 value) external onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).burnFrom(owner, value);
    }

    function burnFromCoveringFees(
        address owner,
        uint256 value,
        address coverAddress, uint256 fee) external onlyRole(OPERATOR_ROLE) {
        if (IERC20(brla).balanceOf(coverAddress) >= fee) {
            IBRLA(brla).burnFrom(coverAddress, fee);
        }
        IBRLA(brla).burnFrom(owner, value);
    }

    function transferFromWithPermit(
        address token,
        address owner,
        address destination,
        uint256 value,
        uint256 fee,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) external onlyRole(OPERATOR_ROLE) {
        IERC20Permit(token).permit(owner, address(this), value, deadline, v, r, s);
        IERC20(token).safeTransferFrom(owner, address(this), value);
        IERC20(token).safeTransfer(destination, value - fee);
    }

    function transferFromWithMetaTx(
        address token,
        address owner,
        address destination,
        uint256 value,
        uint256 fee,
        bytes memory functionSignature,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV) external onlyRole(OPERATOR_ROLE) {
        // Meta tx (should be an approve)
        IMetaTransaction(token).executeMetaTransaction(owner, functionSignature, sigR, sigS, sigV);
        IERC20(token).safeTransferFrom(owner, address(this), value);
        IERC20(token).safeTransfer(destination, value - fee);
    }

    function transferFrom(
        address token,
        address from,
        address to,
        uint256 value,
        uint256 fee) external onlyRole(OPERATOR_ROLE) {
        IERC20(token).safeTransferFrom(from, address(this), value);
        IERC20(token).safeTransfer(to, value - fee);
    }

    struct SwapExactInputSinglePermitParams {
        address inputToken;
        address outputToken;
        uint24 poolFee;
        uint256 inputAmount;
        uint256 minimumOutputAmount;
        address _owner;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
        address receiver;
    }

    struct SwapExactInputSingleMetaTxParams {
        address inputToken;
        address outputToken;
        uint24 poolFee;
        uint256 inputAmount;
        uint256 minimumOutputAmount;
        address userAddress;
        bytes functionSignature;
        bytes32 sigR;
        bytes32 sigS;
        uint8 sigV;
        address receiver;
    }

    struct SwapExactOutputSinglePermitParams {
        address inputToken;
        address outputToken;
        uint24 poolFee;
        uint256 maximumInputAmount;
        uint256 outputAmount;
        address _owner;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
        address receiver;
    }

    struct SwapExactOutputSingleMetaTxParams {
        address inputToken;
        address outputToken;
        uint24 poolFee;
        uint256 maximumInputAmount;
        uint256 outputAmount;
        address userAddress;
        bytes functionSignature;
        bytes32 sigR;
        bytes32 sigS;
        uint8 sigV;
        address receiver;
    }

    function swapExactInputSingleWithPermit(SwapExactInputSinglePermitParams memory params) external onlyRole(OPERATOR_ROLE) returns (uint256 amountOut) {

        // Permit
        IERC20Permit(params.inputToken).permit(params._owner, address(this), params.inputAmount, params.deadline, params.v, params.r, params.s);
        // Transfer the specified amount of token to this contract.
        IERC20(params.inputToken).safeTransferFrom(params._owner, address(this), params.inputAmount);
        // Enable SwapRouter to get tokens from this smartcontract
        IERC20(params.inputToken).safeIncreaseAllowance(address(swapRouter), params.inputAmount);
        
        // Swap for output token
        ISwapRouter.ExactInputSingleParams memory routerParams =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: params.inputToken,
                tokenOut: params.outputToken,
                fee: params.poolFee,
                recipient: params.receiver,
                deadline: block.timestamp,
                amountIn: params.inputAmount,
                amountOutMinimum: params.minimumOutputAmount,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(routerParams);
    }

    function swapExactInputSingleWithMetaTx(SwapExactInputSingleMetaTxParams memory params) external onlyRole(OPERATOR_ROLE) returns (uint256 amountOut) {

        // Meta tx (should be an approve)
        IMetaTransaction(params.inputToken).executeMetaTransaction(params.userAddress, params.functionSignature, params.sigR, params.sigS, params.sigV);
        // Transfer the specified amount of token to this contract.
        IERC20(params.inputToken).safeTransferFrom(params.userAddress, address(this), params.inputAmount);
        // Enable SwapRouter to get tokens from this smartcontract
        IERC20(params.inputToken).safeIncreaseAllowance(address(swapRouter), params.inputAmount);

        //Swap for output token
        ISwapRouter.ExactInputSingleParams memory routerParams =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: params.inputToken,
                tokenOut: params.outputToken,
                fee: params.poolFee,
                recipient: params.receiver,
                deadline: block.timestamp,
                amountIn: params.inputAmount,
                amountOutMinimum: params.minimumOutputAmount,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(routerParams);

    }

    function swapExactOutputSingleWithPermit(SwapExactOutputSinglePermitParams memory params) external onlyRole(OPERATOR_ROLE) returns (uint256 amountIn) {

        // Permit
        IERC20Permit(params.inputToken).permit(params._owner, address(this), params.maximumInputAmount, params.deadline, params.v, params.r, params.s);
        // Transfer the specified amount of token to this contract.
        IERC20(params.inputToken).safeTransferFrom(params._owner, address(this), params.maximumInputAmount);
        // Enable SwapRouter to get tokens from this smartcontract
        IERC20(params.inputToken).safeIncreaseAllowance(address(swapRouter), params.maximumInputAmount);
        
        // Swap for output token
        ISwapRouter.ExactOutputSingleParams memory routerParams =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: params.inputToken,
                tokenOut: params.outputToken,
                fee: params.poolFee,
                recipient: params.receiver,
                deadline: block.timestamp,
                amountInMaximum: params.maximumInputAmount,
                amountOut: params.outputAmount,
                sqrtPriceLimitX96: 0
            });

        amountIn = swapRouter.exactOutputSingle(routerParams);

        if (amountIn < params.maximumInputAmount) {
            IERC20(params.inputToken).safeTransfer(params._owner, params.maximumInputAmount - amountIn);
        }
    }

    function swapExactOutputSingleWithMetaTx(SwapExactOutputSingleMetaTxParams memory params) external onlyRole(OPERATOR_ROLE) returns (uint256 amountIn) {

        // Meta tx (should be an approve)
        IMetaTransaction(params.inputToken).executeMetaTransaction(params.userAddress, params.functionSignature, params.sigR, params.sigS, params.sigV);
        // Transfer the specified amount of token to this contract.
        IERC20(params.inputToken).safeTransferFrom(params.userAddress, address(this), params.maximumInputAmount);
        // Enable SwapRouter to get tokens from this smartcontract
        IERC20(params.inputToken).safeIncreaseAllowance(address(swapRouter), params.maximumInputAmount);

        //Swap for output token
        ISwapRouter.ExactOutputSingleParams memory routerParams =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: params.inputToken,
                tokenOut: params.outputToken,
                fee: params.poolFee,
                recipient: params.receiver,
                deadline: block.timestamp,
                amountInMaximum: params.maximumInputAmount,
                amountOut: params.outputAmount,
                sqrtPriceLimitX96: 0
            });

        amountIn = swapRouter.exactOutputSingle(routerParams);

        if (amountIn < params.maximumInputAmount) {
            IERC20(params.inputToken).safeTransfer(params.userAddress, params.maximumInputAmount - amountIn);
        }

    }

    function swapExactInputSingle(
        address inputToken,
        address outputToken,
        uint24 poolFee,
        uint256 inputAmount,
        uint256 minimumOutputAmount,
        address inputAddress,
        address outputAddress) external onlyRole(OPERATOR_ROLE) returns (uint256 amountOut) {

        // Transfer the specified amount of token to this contract.
        if (inputAddress != address(this)) {
            IERC20(inputToken).safeTransferFrom(inputAddress, address(this), inputAmount);
        }
        // Enable SwapRouter to get tokens from this smartcontract
        IERC20(inputToken).safeIncreaseAllowance(address(swapRouter), inputAmount);
        
        // Swap for output token
        ISwapRouter.ExactInputSingleParams memory routerParams =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: inputToken,
                tokenOut: outputToken,
                fee: poolFee,
                recipient: outputAddress,
                deadline: block.timestamp,
                amountIn: inputAmount,
                amountOutMinimum: minimumOutputAmount,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(routerParams);
    }

    function swapExactOutputSingle(
        address inputToken,
        address outputToken,
        uint24 poolFee,
        uint256 maximumInputAmount,
        uint256 outputAmount,
        address inputAddress,
        address outputAddress,
        bool coverDifference) external onlyRole(OPERATOR_ROLE) returns (uint256 amountIn) {
    
        // Transfer the specified amount of token to this contract.
        if (inputAddress != address(this)) {
            if (coverDifference) {
                IERC20(inputToken).safeTransferFrom(inputAddress, address(this), outputAmount);
            } else {
                IERC20(inputToken).safeTransferFrom(inputAddress, address(this), maximumInputAmount);
            }
        }
        // Enable SwapRouter to get tokens from this smartcontract
        IERC20(inputToken).safeIncreaseAllowance(address(swapRouter), maximumInputAmount);
        
        // Swap for output token
        ISwapRouter.ExactOutputSingleParams memory routerParams =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: inputToken,
                tokenOut: outputToken,
                fee: poolFee,
                recipient: outputAddress,
                deadline: block.timestamp,
                amountInMaximum: maximumInputAmount,
                amountOut: outputAmount,
                sqrtPriceLimitX96: 0
            });

        amountIn = swapRouter.exactOutputSingle(routerParams);

        if (amountIn < maximumInputAmount && inputAddress != address(this) && !coverDifference) {
            IERC20(inputToken).safeTransfer(inputAddress, maximumInputAmount - amountIn);
        }
    }

    function setSmartcontractAllowance(address inputToken, address spender, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        IERC20(inputToken).safeIncreaseAllowance(spender, amount);
    }

    function mintBrla(address receiver, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).mint(receiver, amount);
    }

    function mintBrlaCoveringFees(address receiver, uint256 amount, address coverAddress, uint256 fee) external onlyRole(OPERATOR_ROLE) {
        if (IERC20(brla).balanceOf(coverAddress) >= fee) {
            IBRLA(brla).burnFrom(coverAddress, fee);
        }
        IBRLA(brla).mint(receiver, amount);
    }

    function withdrawToken(address token, address receiver, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        IERC20(token).safeTransfer(receiver, amount);
    }

    struct PermitParams {
        address token;
        address owner;
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct MetaTxParams {
        address token;
        address owner;
        bytes functionSignature;
        bytes32 sigR;
        bytes32 sigS;
        uint8 sigV;
    }

    function batchPermit(PermitParams[] memory permits, MetaTxParams[] memory metaTxs) external onlyRole(OPERATOR_ROLE) {
        for (uint i=0; i<permits.length; i++) {
            IERC20Permit(permits[i].token).permit(permits[i].owner, address(this), permits[i].amount, permits[i].deadline, permits[i].v, permits[i].r, permits[i].s);
        }

        for (uint i=0; i<metaTxs.length; i++) {
            IMetaTransaction(metaTxs[i].token).executeMetaTransaction(metaTxs[i].owner, metaTxs[i].functionSignature, metaTxs[i].sigR, metaTxs[i].sigS, metaTxs[i].sigV);
        }
    }

    function pixIn(
        uint256 brlaAmount, 
        address elbowWallet,
        address destinationWallet) public onlyRole(OPERATOR_ROLE) {
        IBRLA(brla).mint(elbowWallet, brlaAmount);
        IERC20(brla).safeTransferFrom(elbowWallet, destinationWallet, brlaAmount);
        emit PixIn(elbowWallet, destinationWallet, brlaAmount);
    }

    function pixOut(
        uint256 brlaAmount, 
        address elbowWallet,
        address sourceWallet) public onlyRole(OPERATOR_ROLE) {
        IERC20(brla).safeTransferFrom(sourceWallet, elbowWallet, brlaAmount);
        IBRLA(brla).burnFrom(elbowWallet, brlaAmount);
        emit PixOut(sourceWallet, elbowWallet, brlaAmount);
    }

}
