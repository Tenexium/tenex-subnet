// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IAlpha.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IAddressConversion.sol";
import "./libraries/AlphaMath.sol";

/**
 * @title StakingWrapper
 * @notice Upgradeable wrapper contract for simplified staking/unstaking with slippage protection
 * @dev Uses delegatecall to preserve msg.sender context in precompile calls
 */
contract StakingWrapper is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using AlphaMath for uint256;

    // ==================== ERRORS ====================

    error AmountZero();
    error InvalidValue();
    error SlippageTooHigh();
    error SwapSimInvalid();
    error TransferFailed();
    error StakeFailed();
    error UnstakeFailed();
    error BurnAlphaFailed();
    error FunctionNotFound();

    // ==================== CONSTANTS ====================

    // Bittensor EVM precompiles
    IStaking public constant STAKING_PRECOMPILE = IStaking(0x0000000000000000000000000000000000000805);
    IAlpha public constant ALPHA_PRECOMPILE = IAlpha(0x0000000000000000000000000000000000000808);

    // ==================== EVENTS ====================

    event Staked(
        address indexed user,
        bytes32 indexed validatorHotkey,
        uint16 indexed alphaNetuid,
        uint256 taoAmount,
        uint256 alphaReceived,
        uint256 maxSlippage
    );

    event Unstaked(
        address indexed user,
        bytes32 indexed validatorHotkey,
        uint16 indexed alphaNetuid,
        uint256 alphaAmount,
        uint256 taoReceived,
        uint256 maxSlippage
    );

    event Burned(address indexed user, bytes32 indexed hotkey, uint16 indexed alphaNetuid, uint256 alphaAmount);

    event MoveStaked(
        address indexed user,
        bytes32 indexed originHotkey,
        bytes32 indexed destinationHotkey,
        uint16 originNetuid,
        uint16 destinationNetuid,
        uint256 amount
    );

    // ==================== STATE VARIABLES ====================

    // Maximum allowed slippage in basis points (e.g., 1000 = 10%)
    uint256 public maxSlippage;

    // Address conversion contract
    IAddressConversion public addressConversionContract;

    // ==================== CONSTRUCTOR ====================

    /**
     * @notice Constructor for UUPS proxy pattern
     */
    constructor() {
        _disableInitializers();
    }

    // ==================== INITIALIZATION ====================

    /**
     * @notice Initialize the contract
     * @param _addressConversionContract Address of the address conversion contract
     * @param _maxSlippage Maximum allowed slippage in basis points
     */
    function initialize(address _addressConversionContract, uint256 _maxSlippage) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        if (_addressConversionContract == address(0)) revert InvalidValue();
        if (_maxSlippage > 10000) revert SlippageTooHigh();

        addressConversionContract = IAddressConversion(_addressConversionContract);
        maxSlippage = _maxSlippage;
    }

    // ==================== STAKING FUNCTIONS ====================

    /**
     * @notice Stake TAO for Alpha tokens with slippage protection
     * @dev Uses delegatecall to preserve msg.sender context in precompile
     * @param validatorHotkey Validator hotkey to stake with
     * @param stakeAmount Amount of TAO to stake (in wei)
     * @param slippage Maximum acceptable slippage in basis points (e.g., 500 = 5%)
     * @param alphaNetuid Alpha subnet ID
     * @return alphaReceived Amount of Alpha tokens received
     */
    function stakeTaoForAlpha(bytes32 validatorHotkey, uint256 stakeAmount, uint256 slippage, uint16 alphaNetuid)
        external
        payable
        nonReentrant
        returns (uint256 alphaReceived)
    {
        if (stakeAmount == 0) revert AmountZero();
        if (validatorHotkey == bytes32(0)) revert InvalidValue();
        if (slippage > maxSlippage) revert SlippageTooHigh();

        // Get initial stake to calculate how much alpha was received
        bytes32 userSs58Address = addressConversionContract.addressToSS58Pub(msg.sender);
        uint256 initialStake = STAKING_PRECOMPILE.getStake(validatorHotkey, userSs58Address, uint256(alphaNetuid));

        // Simulate the swap to get expected alpha amount
        uint256 expectedAlphaAmount = ALPHA_PRECOMPILE.simSwapTaoForAlpha(alphaNetuid, uint64(stakeAmount.weiToRao()));
        if (expectedAlphaAmount == 0) revert SwapSimInvalid();

        // Calculate minimum acceptable alpha with slippage tolerance
        uint256 minAcceptableAlpha = expectedAlphaAmount.safeMul(10000 - slippage) / 10000;

        // Calculate limit price based on minimum acceptable alpha
        // limitPrice is in rao per alpha
        uint256 limitPrice = stakeAmount / minAcceptableAlpha;

        // Encode the addStakeLimit call
        uint256 amountRao = stakeAmount.weiToRao();
        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.addStakeLimit.selector,
            validatorHotkey,
            amountRao,
            limitPrice,
            false, // Don't allow partial execution
            uint256(alphaNetuid)
        );

        // Execute stake operation using delegatecall to preserve msg.sender
        (bool success,) = address(STAKING_PRECOMPILE).delegatecall{gas: gasleft()}(data);
        if (!success) revert StakeFailed();

        // Get final stake to calculate how much alpha was received
        uint256 finalStake = STAKING_PRECOMPILE.getStake(validatorHotkey, userSs58Address, uint256(alphaNetuid));
        alphaReceived = finalStake - initialStake;

        // Verify slippage tolerance was met
        if (alphaReceived < minAcceptableAlpha) revert SlippageTooHigh();

        emit Staked(msg.sender, validatorHotkey, alphaNetuid, stakeAmount, alphaReceived, slippage);

        return alphaReceived;
    }

    /**
     * @notice Unstake Alpha tokens for TAO with slippage protection
     * @dev Uses delegatecall to preserve msg.sender context in precompile
     * @param validatorHotkey Validator hotkey to unstake from
     * @param alphaAmount Amount of Alpha tokens to unstake
     * @param slippage Maximum acceptable slippage in basis points (e.g., 500 = 5%)
     * @param alphaNetuid Alpha subnet ID
     * @return taoReceived Amount of TAO received
     */
    function unstakeAlphaForTao(bytes32 validatorHotkey, uint256 alphaAmount, uint256 slippage, uint16 alphaNetuid)
        external
        nonReentrant
        returns (uint256 taoReceived)
    {
        if (alphaAmount == 0) revert AmountZero();
        if (validatorHotkey == bytes32(0)) revert InvalidValue();
        if (slippage > maxSlippage) revert SlippageTooHigh();

        // Get initial balance to calculate how much TAO was received
        uint256 initialBalance = msg.sender.balance;

        // Simulate the swap to get expected TAO amount
        uint256 expectedTaoAmountRao = ALPHA_PRECOMPILE.simSwapAlphaForTao(alphaNetuid, uint64(alphaAmount));
        if (expectedTaoAmountRao == 0) revert SwapSimInvalid();

        uint256 expectedTaoAmount = expectedTaoAmountRao.raoToWei();

        // Calculate minimum acceptable TAO with slippage tolerance
        uint256 minAcceptableTao = expectedTaoAmount.safeMul(10000 - slippage) / 10000;

        // Calculate limit price based on minimum acceptable TAO
        // limitPrice is in rao per alpha
        uint256 limitPrice = minAcceptableTao / alphaAmount;

        // Encode the removeStakeLimit call
        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.removeStakeLimit.selector,
            validatorHotkey,
            alphaAmount,
            limitPrice,
            false, // Don't allow partial execution
            uint256(alphaNetuid)
        );

        // Execute unstake operation using delegatecall to preserve msg.sender
        (bool success,) = address(STAKING_PRECOMPILE).delegatecall{gas: gasleft()}(data);
        if (!success) revert UnstakeFailed();

        // Get final balance to calculate how much TAO was received
        uint256 finalBalance = msg.sender.balance;
        taoReceived = finalBalance - initialBalance;

        // Verify slippage tolerance was met
        if (taoReceived < minAcceptableTao) revert SlippageTooHigh();

        emit Unstaked(msg.sender, validatorHotkey, alphaNetuid, alphaAmount, taoReceived, slippage);

        return taoReceived;
    }

    /**
     * @notice Burn Alpha tokens staked to a hotkey
     * @dev Uses delegatecall to preserve msg.sender context in precompile
     * @param hotkey Hotkey associated with the stake
     * @param alphaAmount Amount of Alpha tokens to burn
     * @param alphaNetuid Alpha subnet ID
     */
    function burnAlpha(bytes32 hotkey, uint256 alphaAmount, uint16 alphaNetuid) external nonReentrant {
        if (alphaAmount == 0) revert AmountZero();
        if (hotkey == bytes32(0)) revert InvalidValue();

        // Encode the burnAlpha call
        bytes memory data =
            abi.encodeWithSelector(STAKING_PRECOMPILE.burnAlpha.selector, hotkey, alphaAmount, uint256(alphaNetuid));

        // Execute burn operation using delegatecall to preserve msg.sender
        (bool success,) = address(STAKING_PRECOMPILE).delegatecall{gas: gasleft()}(data);
        if (!success) revert BurnAlphaFailed();

        emit Burned(msg.sender, hotkey, alphaNetuid, alphaAmount);
    }

    /**
     * @notice Move stake from one hotkey to another (potentially across netuids)
     * @dev Uses delegatecall to preserve msg.sender context in precompile
     * @param originHotkey Origin validator hotkey to move stake from
     * @param destinationHotkey Destination validator hotkey to move stake to
     * @param originNetuid Origin subnet ID
     * @param destinationNetuid Destination subnet ID
     * @param amount Amount of stake to move
     */
    function moveStake(
        bytes32 originHotkey,
        bytes32 destinationHotkey,
        uint16 originNetuid,
        uint16 destinationNetuid,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) revert AmountZero();
        if (originHotkey == bytes32(0)) revert InvalidValue();
        if (destinationHotkey == bytes32(0)) revert InvalidValue();

        // Encode the moveStake call
        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.moveStake.selector,
            originHotkey,
            destinationHotkey,
            uint256(originNetuid),
            uint256(destinationNetuid),
            amount
        );

        // Execute move stake operation using delegatecall to preserve msg.sender
        (bool success,) = address(STAKING_PRECOMPILE).delegatecall{gas: gasleft()}(data);
        if (!success) revert StakeFailed();

        emit MoveStaked(msg.sender, originHotkey, destinationHotkey, originNetuid, destinationNetuid, amount);
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Update maximum allowed slippage (owner only)
     * @param _maxSlippage New maximum slippage in basis points
     */
    function updateMaxSlippage(uint256 _maxSlippage) external onlyOwner {
        if (_maxSlippage > 10000) revert SlippageTooHigh();
        maxSlippage = _maxSlippage;
    }

    /**
     * @notice Update address conversion contract (owner only)
     * @param _addressConversionContract New address conversion contract
     */
    function updateAddressConversionContract(address _addressConversionContract) external onlyOwner {
        if (_addressConversionContract == address(0)) revert InvalidValue();
        addressConversionContract = IAddressConversion(_addressConversionContract);
    }

    /**
     * @notice Emergency withdraw function (owner only)
     * @dev Allows owner to withdraw any TAO stuck in the contract
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert AmountZero();

        (bool success,) = payable(owner()).call{value: balance}("");
        if (!success) revert TransferFailed();
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get current stake for a specific staker address
     * @param validatorHotkey Validator hotkey
     * @param staker Staker address
     * @param alphaNetuid Alpha subnet ID
     * @return Current stake amount
     */
    function getStake(bytes32 validatorHotkey, address staker, uint16 alphaNetuid) external view returns (uint256) {
        bytes32 stakerSs58 = addressConversionContract.addressToSS58Pub(staker);
        return STAKING_PRECOMPILE.getStake(validatorHotkey, stakerSs58, uint256(alphaNetuid));
    }

    /**
     * @notice Simulate staking TAO for Alpha
     * @param taoAmount Amount of TAO to stake
     * @param alphaNetuid Alpha subnet ID
     * @return Expected Alpha amount
     */
    function simulateStake(uint256 taoAmount, uint16 alphaNetuid) external view returns (uint256) {
        return ALPHA_PRECOMPILE.simSwapTaoForAlpha(alphaNetuid, uint64(taoAmount.weiToRao()));
    }

    /**
     * @notice Simulate unstaking Alpha for TAO
     * @param alphaAmount Amount of Alpha to unstake
     * @param alphaNetuid Alpha subnet ID
     * @return Expected TAO amount in wei
     */
    function simulateUnstake(uint256 alphaAmount, uint16 alphaNetuid) external view returns (uint256) {
        uint256 taoRao = ALPHA_PRECOMPILE.simSwapAlphaForTao(alphaNetuid, uint64(alphaAmount));
        return taoRao.raoToWei();
    }

    // ==================== UPGRADES (UUPS) ====================

    /**
     * @notice Authorize upgrade (owner only)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ==================== FALLBACK ====================

    /**
     * @notice Allow contract to receive TAO
     */
    receive() external payable {}

    /**
     * @notice Prohibit fallback calls
     */
    fallback() external payable {
        revert FunctionNotFound();
    }
}
