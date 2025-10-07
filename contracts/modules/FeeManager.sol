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
        uint256 protocolFeeAmount = feeAmount.safeMul(tradingFeeProtocolShare) / PRECISION;
        uint256 lpFeeAmount = feeAmount.safeMul(tradingFeeLpShare) / PRECISION;
        lpFeeAmount = lpFeeAmount.safeMul(900000000) / PRECISION; // 90% - Reserve 10% for LP Recovery

        if (protocolFeeAmount > 0) {
            protocolFees += protocolFeeAmount;
        }

        // Accumulate per-share for LPs using total shares supply
        if (lpFeeAmount > 0 && totalLpStakes > 0) {
            accLpFeesPerShare += (lpFeeAmount * ACC_PRECISION) / totalLpStakes;
            totalLpFees += lpFeeAmount;
        }

        // Update distribution tracking
        totalFeesDistributed += feeAmount;

        emit FeesDistributed(protocolFeeAmount, lpFeeAmount);
    }

    /**
     * @notice Distribute borrowing fees according to borrowing shares
     * @param feeAmount Total borrowing fee amount to distribute
     */
    function _distributeBorrowingFees(uint256 feeAmount) internal {
        if (feeAmount == 0) return;

        uint256 protocolFeeAmount = feeAmount.safeMul(borrowingFeeProtocolShare) / PRECISION;
        uint256 lpFeeAmount = feeAmount.safeMul(borrowingFeeLpShare) / PRECISION;
        lpFeeAmount = lpFeeAmount.safeMul(900000000) / PRECISION; // 90% - Reserve 10% for LP Recovery

        if (protocolFeeAmount > 0) {
            protocolFees += protocolFeeAmount;
        }

        if (lpFeeAmount > 0 && totalLpStakes > 0) {
            accLpFeesPerShare += (lpFeeAmount * ACC_PRECISION) / totalLpStakes;
            totalLpFees += lpFeeAmount;
        }

        totalFeesDistributed += feeAmount;

        emit FeesDistributed(protocolFeeAmount, lpFeeAmount);
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

    // ==================== FEE CALCULATION FUNCTIONS ====================

    /**
     * @notice Calculate discounted fee based on user's tier
     * @param user User address
     * @param positionValue Position value in TAO
     * @return discountedFee Fee after applying tier discount
     */
    function _calculateTradingFeeWithDiscount(address user, uint256 positionValue)
        internal
        view
        returns (uint256 discountedFee)
    {
        uint256 baseFee = positionValue.safeMul(tradingFeeRate) / PRECISION;
        bytes32 user_ss58Pubkey = ADDRESS_CONVERSION_CONTRACT.addressToSS58Pub(user);
        uint256 balance = STAKING_PRECOMPILE.getStake(protocolValidatorHotkey, user_ss58Pubkey, TENEX_NETUID);
        uint256 discount;
        if (balance >= tier5Threshold) discount = tier5FeeDiscount;
        else if (balance >= tier4Threshold) discount = tier4FeeDiscount;
        else if (balance >= tier3Threshold) discount = tier3FeeDiscount;
        else if (balance >= tier2Threshold) discount = tier2FeeDiscount;
        else if (balance >= tier1Threshold) discount = tier1FeeDiscount;
        else discount = tier0FeeDiscount;

        discountedFee = baseFee.safeMul(PRECISION - discount) / PRECISION;

        return discountedFee;
    }

    /**
     * @notice Calculate accrued fees for a position using global accumulator
     * @param user User address
     * @param positionId User's position identifier
     * @return accruedFees Total accrued borrowing fees
     */
    function _calculatePositionFees(address user, uint256 positionId)
        internal
        view
        virtual
        returns (uint256 accruedFees)
    {
        Position storage position = positions[user][positionId];
        if (!position.isActive) return 0;

        // Calculate fees using global accumulator approach
        // Fee = (currentAccruedBorrowingFees - positionBorrowingFeeDebt) * positionBorrowedAmount
        uint256 feeAccumulator = accruedBorrowingFees - position.borrowingFeeDebt;
        return position.borrowed.safeMul(feeAccumulator) / PRECISION;
    }
}
