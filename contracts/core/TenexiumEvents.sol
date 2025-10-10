// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title TenexiumEvents
 * @notice Central contract for all Tenexium Protocol events
 */
contract TenexiumEvents {
    // ==================== LIQUIDITY PROVIDER EVENTS ====================

    event LiquidityAdded(address indexed provider, uint256 amount, uint256 amountAfter, uint256 totalStakes);

    event LiquidityRemoved(address indexed provider, uint256 amount, uint256 amountAfter, uint256 totalStakes);

    // ==================== POSITION EVENTS ====================

    event PositionOpened(
        address indexed user,
        uint256 indexed positionId,
        uint16 alphaNetuid,
        uint256 collateral,
        uint256 borrowed,
        uint256 alphaAmount,
        uint256 leverage,
        uint256 entryPrice
    );

    event PositionClosed(
        address indexed user,
        uint256 indexed positionId,
        uint16 alphaNetuid,
        uint256 initialCollateralReturned,
        uint256 addedCollateralReturned,
        uint256 borrowedRepaid,
        uint256 alphaAmount,
        int256 pnl,
        uint256 fees
    );

    event CollateralAdded(address indexed user, uint256 indexed positionId, uint16 alphaNetuid, uint256 amount);

    // ==================== RISK MANAGEMENT & LIQUIDATION EVENTS ====================

    event PositionLiquidated(
        address indexed user,
        address indexed liquidator,
        uint256 indexed positionId,
        uint16 alphaNetuid,
        uint256 positionValue,
        uint256 liquidationFee,
        uint256 liquidatorBonus
    );

    // ==================== FEE EVENTS ====================

    event FeesDistributed(uint256 protocolAmount, uint256 lpAmount);

    event LpFeeRewardsClaimed(address indexed lp, uint256 amount);

    // ==================== BUYBACK & VESTING EVENTS ====================

    event BuybackExecuted(uint256 taoAmount, uint256 alphaReceived, uint256 blockNumber);
}
