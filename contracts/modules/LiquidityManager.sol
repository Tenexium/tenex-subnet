// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/TenexiumErrors.sol";
import "./FeeManager.sol";

/**
 * @title LiquidityManager
 * @notice Functions for liquidity provider operations and pool management
 */
abstract contract LiquidityManager is FeeManager {
    using AlphaMath for uint256;

    // ==================== LIQUIDITY PROVIDER FUNCTIONS ====================

    /**
     * @notice Add liquidity to the protocol (TAO only)
     * @dev Users deposit TAO to become liquidity providers
     */
    function _addLiquidity() internal {
        if (msg.value < 1e17) revert TenexiumErrors.LpMinDeposit();

        LiquidityProvider storage lp = liquidityProviders[msg.sender];

        // Settle pending rewards before changing shares
        // update reward accounting using accumulators in FeeManager
        _updateLpFeeRewards(msg.sender);

        if (!lp.isActive) {
            // New LP
            lp.isActive = true;
        }

        lp.stake = lp.stake.safeAdd(msg.value);
        lp.shares = lp.shares.safeAdd(msg.value); // 1 share per 1 TAO
        // Update reward debt to include new shares
        lp.rewardDebt = lp.shares.safeMul(accLpFeesPerShare) / 1e12;

        // Update global state (LP liquidity only)
        totalLpStakes = totalLpStakes.safeAdd(msg.value);

        emit LiquidityAdded(msg.sender, msg.value, lp.stake, totalLpStakes);
    }

    /**
     * @notice Remove liquidity from the protocol (TAO only)
     * @param withdrawAmount Amount of TAO to withdraw
     */
    function _removeLiquidity(uint256 withdrawAmount) internal {
        LiquidityProvider storage lp = liquidityProviders[msg.sender];
        if (!lp.isActive) revert TenexiumErrors.NotLiquidityProvider();

        if (withdrawAmount == 0 || withdrawAmount > lp.stake) revert TenexiumErrors.InvalidWithdrawalAmount();

        // Calculate utilization rate after withdrawal using LP liquidity only
        uint256 newTotalLp = totalLpStakes.safeSub(withdrawAmount);
        uint256 newUtilizationRate = newTotalLp > 0 ? totalBorrowed.safeMul(PRECISION) / newTotalLp : 0;

        if (newUtilizationRate > maxUtilizationRate) revert TenexiumErrors.UtilizationExceeded();

        // Update rewards before changing stake
        _updateLpFeeRewards(msg.sender);

        // Update LP state
        lp.stake = lp.stake.safeSub(withdrawAmount);
        lp.shares = lp.shares.safeSub(withdrawAmount); // 1 share per 1 TAO
        if (lp.stake == 0) {
            // Deactivate and clear residuals to avoid dust shares/rewardDebt
            lp.isActive = false;
            lp.shares = 0;
            lp.rewardDebt = 0;
        } else {
            // Reset reward debt to new share amount
            lp.rewardDebt = lp.shares.safeMul(accLpFeesPerShare) / 1e12;
        }

        // Update global state (LP liquidity only)
        totalLpStakes = totalLpStakes.safeSub(withdrawAmount);

        // Transfer TAO to LP
        (bool success,) = msg.sender.call{value: withdrawAmount}("");
        if (!success) revert TenexiumErrors.TransferFailed();

        emit LiquidityRemoved(msg.sender, withdrawAmount, lp.stake, totalLpStakes);
    }
}
