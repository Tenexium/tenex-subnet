// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/TenexiumErrors.sol";
import "./FeeManager.sol";
import "./PrecompileAdapter.sol";
import "../interfaces/IInsuranceManager.sol";

/**
 * @title LiquidationManager
 * @notice Functions for position liquidation using single threshold approach
 */
abstract contract LiquidationManager is FeeManager, PrecompileAdapter {
    using AlphaMath for uint256;

    // ==================== LIQUIDATION FUNCTIONS ====================

    /**
     * @notice Liquidate an undercollateralized position
     * @param user Address of the position owner
     * @param positionId User's position identifier
     * @dev Uses single threshold approach - liquidate immediately when threshold hit
     */
    function _liquidatePosition(address user, uint256 positionId) internal {
        Position storage position = positions[user][positionId];
        uint16 alphaNetuid = position.alphaNetuid;

        // Calculate liquidation details using accurate simulation
        uint256 simulatedTaoValueRao = ALPHA_PRECOMPILE.simSwapAlphaForTao(alphaNetuid, uint64(position.alphaAmount));
        if (simulatedTaoValueRao == 0) revert TenexiumErrors.InvalidValue();
        uint256 simulatedTaoValue = AlphaMath.raoToWei(simulatedTaoValueRao);

        // Calculate total debt (borrowed + accrued fees)
        uint256 accruedFees = _calculatePositionFees(user, positionId);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);

        // Unstake alpha to get TAO using the validator hotkey used at open (fallback to protocolValidatorHotkey)
        bytes32 vHotkey = position.validatorHotkey == bytes32(0) ? protocolValidatorHotkey : position.validatorHotkey;

        // Try to unstake alpha increasing the limit price gradually until successful
        uint256 slippage = 100;
        uint256 taoReceived = 0;
        while (slippage <= 1000) {
            uint256 minAcceptableTao = simulatedTaoValue.safeMul(10000 - slippage) / 10000;
            uint256 limitPrice = minAcceptableTao / position.alphaAmount;
            taoReceived = _unstakeAlphaForTao(vHotkey, position.alphaAmount, limitPrice, false, alphaNetuid);
            if (taoReceived > 0) break;
            slippage += 100;
        }

        if (taoReceived == 0) revert TenexiumErrors.UnstakeFailed();

        // Payment waterfall: Debt > Liquidation fee (split) > User
        uint256 remaining = taoReceived;

        // 1. Repay debt first
        uint256 debtRepayment = remaining < totalDebt ? remaining : totalDebt;
        uint256 availableBorrowingFees =
            debtRepayment > position.borrowed ? debtRepayment.safeSub(position.borrowed) : 0;
        _distributeBorrowingFees(availableBorrowingFees);
        remaining = remaining.safeSub(debtRepayment);

        // 2. Distribute liquidation fee on actual proceeds (post-debt)
        uint256 liquidationFeeAmount = remaining.safeMul(liquidationFeeRate) / PRECISION;
        uint256 liquidatorFeeShare = liquidationFeeAmount.safeMul(liquidationFeeLiquidatorShare) / PRECISION;
        // Liquidator gets 100% of the liquidator share directly
        if (liquidatorFeeShare > 0) {
            (bool success,) = msg.sender.call{value: liquidatorFeeShare}("");
            if (!success) revert TenexiumErrors.LiquiFeeTransferFailed();
        }
        uint256 protocolFeeShare = liquidationFeeAmount.safeMul(liquidationFeeProtocolShare) / PRECISION;
        if (protocolFeeShare > 0) {
            // Protocol share of liquidation fees (accounted into protocolFees; buybacks funded via withdrawal)
            protocolFees = protocolFees.safeAdd(protocolFeeShare);
        }

        totalLiquidationFees = totalLiquidationFees.safeAdd(liquidationFeeAmount);
        remaining = remaining.safeSub(liquidationFeeAmount);
        // 3. Return any remaining collateral to user
        if (remaining > 0) {
            (bool success,) = user.call{value: remaining}("");
            if (!success) revert TenexiumErrors.CollateralReturnFailed();
        }

        // Update global statistics before clearing position fields
        totalBorrowed = totalBorrowed.safeSub(position.borrowed);
        totalCollateral = totalCollateral.safeSub(position.collateral);

        AlphaPair storage pair = alphaPairs[alphaNetuid];
        pair.totalBorrowed = pair.totalBorrowed.safeSub(position.borrowed);
        pair.totalCollateral = pair.totalCollateral.safeSub(position.collateral);
        _updateUtilizationRate(alphaNetuid);

        // Clear the liquidated position
        position.alphaAmount = 0;
        position.borrowed = 0;
        position.collateral = 0;
        position.accruedFees = 0;
        position.isActive = false;

        // Update liquidation statistics
        totalLiquidations = totalLiquidations + 1;
        totalLiquidationValue = totalLiquidationValue.safeAdd(simulatedTaoValue);
        totalLiquidatorLiquidations[msg.sender] = totalLiquidatorLiquidations[msg.sender] + 1;
        totalLiquidatorLiquidationValue[msg.sender] =
            totalLiquidatorLiquidationValue[msg.sender].safeAdd(simulatedTaoValue);
        dailyLiquidatorLiquidations[msg.sender][block.number / 7200] =
            dailyLiquidatorLiquidations[msg.sender][block.number / 7200] + 1;
        dailyLiquidatorLiquidationValue[msg.sender][block.number / 7200] =
            dailyLiquidatorLiquidationValue[msg.sender][block.number / 7200].safeAdd(simulatedTaoValue);

        uint256 insuranceAmountRequired = totalLpStakes.safeSub(totalBorrowed).safeAdd(totalPendingLpFees).safeAdd(
            protocolFees
        ).safeAdd(buybackPool).safeSub(address(this).balance);
        uint256 availableInsurance = IInsuranceManager(insuranceManager).getNetBalance();
        if (insuranceAmountRequired < availableInsurance && insuranceAmountRequired > 0) {
            IInsuranceManager(insuranceManager).fund(insuranceAmountRequired);
        }

        emit PositionLiquidated(
            user, msg.sender, positionId, alphaNetuid, simulatedTaoValue, liquidationFeeAmount, liquidatorFeeShare
        );
    }

    // ==================== RISK ASSESSMENT FUNCTIONS ====================

    /**
     * @notice Check if a position is liquidatable using single threshold
     * @param user Position owner
     * @param positionId User's position identifier
     * @return liquidatable True if position can be liquidated
     */
    function _isPositionLiquidatable(address user, uint256 positionId) internal view returns (bool liquidatable) {
        Position storage position = positions[user][positionId];

        // Get current value using accurate simulation
        uint256 simulatedTaoValueRao =
            ALPHA_PRECOMPILE.simSwapAlphaForTao(position.alphaNetuid, uint64(position.alphaAmount));

        // Calculate total debt including accrued fees
        uint256 accruedFees = _calculatePositionFees(user, positionId);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);

        if (totalDebt == 0) return false; // No debt means not liquidatable

        //health ratio check: currentValue / totalDebt < threshold
        uint256 simulatedTaoWei = simulatedTaoValueRao.raoToWei();
        uint256 healthRatio = simulatedTaoWei.safeMul(PRECISION) / totalDebt;
        return healthRatio < alphaPairs[position.alphaNetuid].liquidationThreshold;
    }
}
