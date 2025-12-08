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
    error TransferFailed();
    error StakeFailed();
    error UnstakeFailed();
    error BurnAlphaFailed();
    error FunctionNotFound();

    // ==================== CONSTANTS ====================

    // Bittensor EVM precompiles
    IStaking public constant STAKING_PRECOMPILE = IStaking(0x0000000000000000000000000000000000000805);
    IAlpha public constant ALPHA_PRECOMPILE = IAlpha(0x0000000000000000000000000000000000000808);

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
     */
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    // ==================== STAKING FUNCTIONS ====================

    /**
     * @notice Stake TAO for Alpha tokens with limit price protection
     * @dev Uses delegatecall to preserve msg.sender context in precompile
     * @param validatorHotkey Validator hotkey to stake with
     * @param stakeAmount Amount of TAO to stake (in wei)
     * @param limitPrice Maximum price willing to pay (in rao per alpha)
     * @param alphaNetuid Alpha subnet ID
     */
    function stakeTaoForAlpha(bytes32 validatorHotkey, uint256 stakeAmount, uint256 limitPrice, uint16 alphaNetuid)
        external
        payable
        nonReentrant
    {
        if (stakeAmount == 0) revert AmountZero();
        if (validatorHotkey == bytes32(0)) revert InvalidValue();

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
    }

    /**
     * @notice Unstake Alpha tokens for TAO with limit price protection
     * @dev Uses delegatecall to preserve msg.sender context in precompile
     * @param validatorHotkey Validator hotkey to unstake from
     * @param alphaAmount Amount of Alpha tokens to unstake
     * @param limitPrice Minimum price willing to accept (in rao per alpha)
     * @param alphaNetuid Alpha subnet ID
     */
    function unstakeAlphaForTao(bytes32 validatorHotkey, uint256 alphaAmount, uint256 limitPrice, uint16 alphaNetuid)
        external
        nonReentrant
    {
        if (alphaAmount == 0) revert AmountZero();
        if (validatorHotkey == bytes32(0)) revert InvalidValue();

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
    }

    // ==================== ADMIN FUNCTIONS ====================

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
