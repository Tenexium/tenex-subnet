// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
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

        // Reserve insurance fee for LP Recover
        uint256 insuranceFeeAmount = lpFeeAmount.safeMul(lpFeeInsuranceShare) / PRECISION;
        (bool _success,) = payable(insuranceFund).call{value: insuranceFeeAmount}("");
        if (!_success) revert TenexiumErrors.TransferFailed();
        lpFeeAmount = lpFeeAmount.safeSub(insuranceFeeAmount);

        if (protocolFeeAmount > 0) {
            protocolFees = protocolFees.safeAdd(protocolFeeAmount);
        }

        // Accumulate per-share for LPs using total shares supply
        if (lpFeeAmount > 0 && totalLpStakes > 0) {
            accLpFeesPerShare = accLpFeesPerShare.safeAdd((lpFeeAmount * ACC_PRECISION) / totalLpStakes);
            totalPendingLpFees = totalPendingLpFees.safeAdd(lpFeeAmount);
        }

        // Update distribution tracking
        totalTradingFees = totalTradingFees.safeAdd(feeAmount);

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

        // Reserve insurance fee for LP Recover
        uint256 insuranceFeeAmount = lpFeeAmount.safeMul(lpFeeInsuranceShare) / PRECISION;
        (bool _success,) = payable(insuranceFund).call{value: insuranceFeeAmount}("");
        if (!_success) revert TenexiumErrors.TransferFailed();
        lpFeeAmount = lpFeeAmount.safeSub(insuranceFeeAmount);

        if (protocolFeeAmount > 0) {
            protocolFees = protocolFees.safeAdd(protocolFeeAmount);
        }

        if (lpFeeAmount > 0 && totalLpStakes > 0) {
            accLpFeesPerShare = accLpFeesPerShare.safeAdd((lpFeeAmount * ACC_PRECISION) / totalLpStakes);
            totalPendingLpFees = totalPendingLpFees.safeAdd(lpFeeAmount);
        }

        totalBorrowingFees = totalBorrowingFees.safeAdd(feeAmount);

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
        uint256 accumulated = provider.shares.safeMul(accLpFeesPerShare) / ACC_PRECISION;
        if (accumulated > provider.rewardDebt) {
            uint256 pending = accumulated.safeSub(provider.rewardDebt);
            lpFeeRewards[lp] = lpFeeRewards[lp].safeAdd(pending);
        }
        provider.rewardDebt = provider.shares.safeMul(accLpFeesPerShare) / ACC_PRECISION;
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
        totalPendingLpFees = totalPendingLpFees.safeSub(rewards);
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
        uint256 feeAccumulator = accruedBorrowingFees.safeSub(position.borrowingFeeDebt);
        return position.borrowed.safeMul(feeAccumulator) / PRECISION;
    }

    /**
     * @notice Update utilization rates for alpha pairs
     * @param alphaNetuid Alpha subnet ID
     */
    function _updateUtilizationRate(uint16 alphaNetuid) internal virtual validAlphaPair(alphaNetuid) {
        AlphaPair storage pair = alphaPairs[alphaNetuid];

        if (totalBorrowed == 0) {
            pair.utilizationRate = 0;
            pair.borrowingRate = 0;
        } else {
            pair.utilizationRate = pair.totalBorrowed.safeMul(PRECISION) / totalBorrowed;
            pair.borrowingRate = _dynamicBorrowRatePer360(totalBorrowed.safeMul(PRECISION) / totalLpStakes);
        }
    }

    /**
     * @notice Unified dynamic borrow rate model per 360 blocks (utilization-kinked)
     * @param utilization Utilization in PRECISION (PRECISION = 100%)
     * @return ratePer360 Borrow rate accrued over 360 blocks
     */
    function _dynamicBorrowRatePer360(uint256 utilization) internal pure virtual returns (uint256 ratePer360) {
        // Baseline aligned to spec: 0.005% per 360 blocks at zero utilization.
        // Kink at 80%; steeper slope beyond kink.
        uint256 baseRate = 50_000; // 0.005% per 360 blocks (0.00005 * 1e9)
        uint256 kink = 800_000_000; // 80% of PRECISION (0.8 * 1e9)
        uint256 slope1 = 150_000; // 0.015% per 360 blocks below kink (0.00015 * 1e9)
        uint256 slope2 = 800_000; // 0.08% per 360 blocks above kink (0.0008 * 1e9)
        if (utilization <= kink) {
            return baseRate + (utilization * slope1) / kink;
        } else {
            return baseRate + slope1 + ((utilization - kink) * slope2) / (1_000_000_000 - kink);
        }
    }
}
