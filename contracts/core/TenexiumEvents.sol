// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title TenexiumEvents
 * @notice Central contract for all Tenexium Protocol events
 */
contract TenexiumEvents {
    // ==================== PROTOCOL CONFIG & GOVERNANCE EVENTS ====================

    event ContractUpgraded(address indexed newImplementation, uint256 version);

    event EmergencyPauseToggled(bool isPaused, address indexed admin, uint256 blockNumber);

    event RiskParametersUpdated(uint256 maxLeverage, uint256 liquidationThreshold);

    event LiquidityGuardrailsUpdated(
        uint256 minLiquidityThreshold, uint256 maxUtilizationRate, uint256 liquidityBufferRatio
    );

    event ActionCooldownsUpdated(uint256 userCooldownBlocks, uint256 lpCooldownBlocks);

    event BuybackParametersUpdated(
        uint256 buybackRate, uint256 buybackIntervalBlocks, uint256 buybackExecutionThreshold
    );

    event VestingParametersUpdated(uint256 vestingDurationBlocks, uint256 cliffDurationBlocks);

    event FeesUpdated(uint256 tradingFeeRate, uint256 borrowingFeeRate, uint256 liquidationFeeRate);

    event FeeDistributionsUpdated();

    event TierParametersUpdated();

    event ProtocolValidatorHotkeyUpdated(bytes32 indexed oldHotkey, bytes32 indexed newHotkey, address indexed admin);

    event ProtocolSs58AddressUpdated(
        bytes32 indexed oldSs58Address, bytes32 indexed newSs58Address, address indexed admin
    );

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury, address indexed admin);

    event UtilizationRateUpdated(uint16 indexed alphaNetuid, uint256 utilizationRate, uint256 borrowingRate);

    event AlphaPairAdded(uint16 indexed netuid, uint256 maxLeverage);

    event AlphaPairRemoved(uint16 indexed netuid);

    event AlphaPairParametersUpdated(uint16 indexed netuid, uint256 oldMaxLeverage, uint256 newMaxLeverage);

    // ==================== LIQUIDITY PROVIDER EVENTS ====================

    event LiquidityAdded(address indexed provider, uint256 amount, uint256 shares, uint256 totalStakes);

    event LiquidityRemoved(address indexed provider, uint256 amount, uint256 shares, uint256 totalStakes);

    // ==================== POSITION EVENTS ====================

    event PositionOpened(
        address indexed user,
        uint16 indexed alphaNetuid,
        uint256 collateral,
        uint256 borrowed,
        uint256 alphaAmount,
        uint256 leverage,
        uint256 entryPrice
    );

    event PositionClosed(
        address indexed user,
        uint16 indexed alphaNetuid,
        uint256 collateralReturned,
        uint256 borrowedRepaid,
        uint256 alphaAmount,
        int256 pnl,
        uint256 fees
    );

    event CollateralAdded(address indexed user, uint16 indexed alphaNetuid, uint256 amount);

    // ==================== RISK MANAGEMENT & LIQUIDATION EVENTS ====================

    event PositionLiquidated(
        address indexed user,
        address indexed liquidator,
        uint16 indexed alphaNetuid,
        uint256 positionValue,
        uint256 liquidationFee,
        uint256 liquidatorBonus,
        string justificationUrl,
        bytes32 contentHash
    );

    // ==================== FEE EVENTS ====================

    event FeesDistributed(uint256 lpAmount, uint256 liquidatorAmount, uint256 epoch);

    event LpFeeRewardsClaimed(address indexed lp, uint256 amount);

    event LiquidatorFeeRewardsClaimed(address indexed liquidator, uint256 amount);

    event LiquidatorScoreUpdated(address indexed liquidator, uint256 newScore, uint256 totalScore);

    // ==================== BUYBACK & VESTING EVENTS ====================

    event BuybackExecuted(uint256 taoAmount, uint256 alphaReceived, uint256 blockNumber, uint256 slippage);

    event VestingScheduleCreated(
        address indexed beneficiary, uint256 amount, uint256 startBlock, uint256 durationBlocks
    );

    event TokensClaimed(address indexed beneficiary, bytes32 indexed ss58Address, uint256 amount);

    event FunctionPermissionsUpdated(bool[3] indexed functionPermissions, address indexed admin);

    // ==================== LIQUIDITY PROVIDER TRACKING EVENTS ====================
    event AddressAssociated(address indexed liquidityProvider, bytes32 indexed hotkey, uint256 timestamp);
}
