// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/RiskCalculator.sol";
import "../libraries/TenexiumErrors.sol";

/**
 * @title FeeManager
 * @notice Functions for fee collection, distribution, and tier-based discounts
 */
abstract contract FeeManager is TenexiumStorage, TenexiumEvents {
    using AlphaMath for uint256;

    uint256 internal constant ACC_PRECISION = 1e12;

    // ==================== FEE DISTRIBUTION FUNCTIONS ====================

    /**
     * @notice Distribute trading fees according to trading shares
     * @param feeAmount Total trading fee amount to distribute
     */
    function _distributeTradingFees(uint256 feeAmount) internal {
        if (feeAmount == 0) return;

        // Calculate distribution amounts using trading fee shares
        uint256 lpFeeAmount = feeAmount.safeMul(tradingFeeLpShare) / PRECISION;
        uint256 liquidatorFeeAmount = feeAmount.safeMul(tradingFeeLiquidatorShare) / PRECISION;

        // Accumulate per-share for LPs
        if (lpFeeAmount > 0 && totalLpStakes > 0) {
            accLpFeesPerShare += (lpFeeAmount * ACC_PRECISION) / totalLpStakes;
            totalLpFees += lpFeeAmount;
        }

        // Accumulate per-score for liquidators
        if (liquidatorFeeAmount > 0 && totalLiquidatorScore > 0) {
            accLiquidatorFeesPerScore += (liquidatorFeeAmount * ACC_PRECISION) / totalLiquidatorScore;
            totalLiquidatorFees += liquidatorFeeAmount;
        }

        // Update distribution tracking
        totalFeesDistributed += feeAmount;
        lastFeeDistributionBlock = block.number;
        currentEpoch++;

        emit FeesDistributed(lpFeeAmount, liquidatorFeeAmount, currentEpoch);
    }

    /**
     * @notice Distribute borrowing fees according to borrowing shares
     * @param feeAmount Total borrowing fee amount to distribute
     */
    function _distributeBorrowingFees(uint256 feeAmount) internal {
        if (feeAmount == 0) return;

        uint256 lpFeeAmount = feeAmount.safeMul(borrowingFeeLpShare) / PRECISION;
        uint256 liquidatorFeeAmount = feeAmount.safeMul(borrowingFeeLiquidatorShare) / PRECISION;

        if (lpFeeAmount > 0 && totalLpStakes > 0) {
            accLpFeesPerShare += (lpFeeAmount * ACC_PRECISION) / totalLpStakes;
            totalLpFees += lpFeeAmount;
        }
        if (liquidatorFeeAmount > 0 && totalLiquidatorScore > 0) {
            accLiquidatorFeesPerScore += (liquidatorFeeAmount * ACC_PRECISION) / totalLiquidatorScore;
            totalLiquidatorFees += liquidatorFeeAmount;
        }
        totalFeesDistributed += feeAmount;
        lastFeeDistributionBlock = block.number;
        currentEpoch++;

        emit FeesDistributed(lpFeeAmount, liquidatorFeeAmount, currentEpoch);
    }

    // ==================== REWARD ACCOUNTING AND CLAIMS ====================

    /**
     * @notice Update LP fee rewards based on their liquidity contribution
     * @param lp Address of the liquidity provider
     */
    function _updateLpFeeRewards(address lp) internal virtual {
        LiquidityProvider storage provider = liquidityProviders[lp];
        if (!provider.isActive) return;
        uint256 accumulated = (provider.shares * accLpFeesPerShare) / ACC_PRECISION;
        if (accumulated > provider.rewardDebt) {
            uint256 pending = accumulated - provider.rewardDebt;
            lpFeeRewards[lp] += pending;
        }
        provider.rewardDebt = (provider.shares * accLpFeesPerShare) / ACC_PRECISION;
    }

    /**
     * @notice Claim accrued LP fee rewards
     * @param lp Address of the liquidity provider
     * @return rewards Amount of TAO claimed
     */
    function _claimLpFeeRewards(address lp) internal returns (uint256 rewards) {
        _updateLpFeeRewards(lp);
        rewards = lpFeeRewards[lp];
        if (rewards == 0) revert TenexiumErrors.NoRewards();
        lpFeeRewards[lp] = 0;
        (bool success,) = payable(lp).call{value: rewards}("");
        if (!success) revert TenexiumErrors.TransferFailed();
        emit LpFeeRewardsClaimed(lp, rewards);
    }

    /**
     * @notice Update liquidator score and fee rewards
     * @param liquidator Address of the liquidator
     * @param liquidationValue Value of the liquidation performed
     */
    function _updateLiquidatorFeeRewards(address liquidator, uint256 liquidationValue) internal {
        // settle pending before updating score
        uint256 prevScore = liquidatorScores[liquidator];
        if (prevScore > 0) {
            uint256 accumulated = (prevScore * accLiquidatorFeesPerScore) / ACC_PRECISION;
            if (accumulated > liquidatorRewardDebt[liquidator]) {
                uint256 pending = accumulated - liquidatorRewardDebt[liquidator];
                liquidatorFeeRewards[liquidator] += pending;
            }
        }
        // Score unit: use TAO scale-neutral units (wei -> TAO approximation)
        uint256 scoreIncrease = liquidationValue / 1e18;
        liquidatorScores[liquidator] = prevScore + scoreIncrease;
        totalLiquidatorScore += scoreIncrease;
        // update reward debt to new score
        liquidatorRewardDebt[liquidator] = (liquidatorScores[liquidator] * accLiquidatorFeesPerScore) / ACC_PRECISION;
        emit LiquidatorScoreUpdated(liquidator, liquidatorScores[liquidator], totalLiquidatorScore);
    }

    /**
     * @notice Claim accrued liquidator fee rewards
     * @param liquidator Address of the liquidator
     * @return rewards Amount of TAO claimed
     */
    function _claimLiquidatorFeeRewards(address liquidator) internal returns (uint256 rewards) {
        // settle pending
        uint256 score = liquidatorScores[liquidator];
        if (score > 0) {
            uint256 accumulated = (score * accLiquidatorFeesPerScore) / ACC_PRECISION;
            if (accumulated > liquidatorRewardDebt[liquidator]) {
                uint256 pending = accumulated - liquidatorRewardDebt[liquidator];
                liquidatorFeeRewards[liquidator] += pending;
                liquidatorRewardDebt[liquidator] = accumulated;
            }
        }
        rewards = liquidatorFeeRewards[liquidator];
        if (rewards == 0) revert TenexiumErrors.NoRewards();
        liquidatorFeeRewards[liquidator] = 0;
        (bool success,) = payable(liquidator).call{value: rewards}("");
        if (!success) revert TenexiumErrors.TransferFailed();
        emit LiquidatorFeeRewardsClaimed(liquidator, rewards);
    }

    // ==================== FEE CALCULATION FUNCTIONS ====================

    /**
     * @notice Calculate discounted fee based on user's tier
     * @param user User address
     * @param originalFee Original fee amount
     * @return discountedFee Fee after applying tier discount
     */
    function _calculateDiscountedFee(address user, uint256 originalFee) internal view returns (uint256 discountedFee) {
        bytes32 user_ss58Pubkey = ADDRESS_CONVERSION_CONTRACT.addressToSS58Pub(user);
        uint256 balance =
            STAKING_PRECOMPILE.getStake(protocolValidatorHotkey, user_ss58Pubkey, TENEX_NETUID);
        uint256 discount;
        if (balance >= tier5Threshold) discount = tier5FeeDiscount;
        else if (balance >= tier4Threshold) discount = tier4FeeDiscount;
        else if (balance >= tier3Threshold) discount = tier3FeeDiscount;
        else if (balance >= tier2Threshold) discount = tier2FeeDiscount;
        else if (balance >= tier1Threshold) discount = tier1FeeDiscount;
        else discount = tier0FeeDiscount;

        discountedFee = originalFee.safeMul(PRECISION - discount) / PRECISION;

        return discountedFee;
    }
}
