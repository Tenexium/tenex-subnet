// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
        uint256 taoAmountStaked,
        uint256 actualAlphaReceived,
        uint256 feesPaid
    );

    event PositionClosed(
        address indexed user,
        uint256 indexed positionId,
        uint16 alphaNetuid,
        uint256 collateralReturned,
        uint256 borrowedRepaid,
        uint256 alphaAmountClosed,
        uint256 actualTaoReceived,
        uint256 feesPaid
    );

    event CollateralAdded(address indexed user, uint256 indexed positionId, uint16 alphaNetuid, uint256 amount);

    // ==================== RISK MANAGEMENT & LIQUIDATION EVENTS ====================

    event PositionLiquidated(
        address indexed user,
        address indexed liquidator,
        uint256 indexed positionId,
        uint16 alphaNetuid,
        uint256 positionValue,
        uint256 borrowingFeesPaid,
        uint256 liquidationFeePaid,
        uint256 liquidatorBonusPaid
    );

    // ==================== FEE EVENTS ====================

    event FeesDistributed(uint256 protocolAmount, uint256 lpAmount);

    event LpFeeRewardsClaimed(address indexed lp, uint256 amount);

    // ==================== BUYBACK ====================

    event BuybackExecuted(uint256 taoAmount, uint256 alphaReceived, uint256 blockNumber);

    // ==================== REWARD EVENTS ====================
    event RewardsDistributed(uint256 totalRewardPool, uint256 selectedUsersLength, uint256 currentWeek);
}
