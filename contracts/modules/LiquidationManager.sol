// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/RiskCalculator.sol";
import "../libraries/TenexiumErrors.sol";
import "./PrecompileAdapter.sol";

/**
 * @title LiquidationManager
 * @notice Functions for position liquidation using single threshold approach
 */
abstract contract LiquidationManager is TenexiumStorage, TenexiumEvents, PrecompileAdapter {
    using AlphaMath for uint256;
    using RiskCalculator for RiskCalculator.PositionData;

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
        if (position.alphaAmount == 0) revert TenexiumErrors.NoAlpha();

        // Verify liquidation is justified using single threshold
        if (!_isPositionLiquidatable(user, positionId)) revert TenexiumErrors.NotLiquidatable();

        // Calculate liquidation details using accurate simulation
        uint256 simulatedTaoValueRao = ALPHA_PRECOMPILE.simSwapAlphaForTao(alphaNetuid, uint64(position.alphaAmount));
        if (simulatedTaoValueRao == 0) revert TenexiumErrors.InvalidValue();
        uint256 simulatedTaoValue = AlphaMath.raoToWei(simulatedTaoValueRao);

        // Calculate total debt (borrowed + accrued fees)
        uint256 accruedFees = _calculatePositionFees(user, positionId);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);

        // Unstake alpha to get TAO using the validator hotkey used at open (fallback to protocolValidatorHotkey)
        bytes32 vHotkey = position.validatorHotkey == bytes32(0) ? protocolValidatorHotkey : position.validatorHotkey;
        uint256 taoReceived = _unstakeAlphaForTao(vHotkey, position.alphaAmount, alphaNetuid);
        if (taoReceived == 0) revert TenexiumErrors.UnstakeFailed();

        // Payment waterfall: Debt > Liquidation fee (split) > User
        uint256 remaining = taoReceived;

        // 1. Repay debt first
        uint256 debtRepayment = remaining < totalDebt ? remaining : totalDebt;
        remaining = remaining.safeSub(debtRepayment);

        // 2. Distribute liquidation fee on actual proceeds (post-debt)
        uint256 liquidationFeeAmount = remaining.safeMul(liquidationFeeRate) / PRECISION;
        if (liquidationFeeAmount > 0 && remaining > 0) {
            uint256 feeToDistribute = liquidationFeeAmount > remaining ? remaining : liquidationFeeAmount;
            // Liquidator gets 100% of the liquidator share directly
            uint256 liquidatorFeeShare = feeToDistribute.safeMul(liquidationFeeLiquidatorShare) / PRECISION;
            if (liquidatorFeeShare > 0) {
                (bool success,) = msg.sender.call{value: liquidatorFeeShare}("");
                if (!success) revert TenexiumErrors.LiquiFeeTransferFailed();
            }
            // Protocol share of liquidation fees (accounted into protocolFees; buybacks funded via withdrawal)
            uint256 protocolFeeShare = feeToDistribute.safeMul(liquidationFeeProtocolShare) / PRECISION;
            protocolFees = protocolFees.safeAdd(protocolFeeShare);
            remaining = remaining.safeSub(feeToDistribute);
        }

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

        // Calculate liquidator bonus (share of liquidation fee)
        uint256 liquidatorFeeShareTotal = liquidationFeeAmount.safeMul(liquidationFeeLiquidatorShare) / PRECISION;

        // Update liquidation statistics
        totalLiquidations = totalLiquidations + 1;
        totalLiquidationValue = totalLiquidationValue.safeAdd(simulatedTaoValue);
        liquidatorLiquidations[msg.sender] = liquidatorLiquidations[msg.sender] + 1;
        liquidatorLiquidationValue[msg.sender] = liquidatorLiquidationValue[msg.sender].safeAdd(simulatedTaoValue);

        emit PositionLiquidated(
            user, msg.sender, positionId, alphaNetuid, simulatedTaoValue, liquidationFeeAmount, liquidatorFeeShareTotal
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
        if (!position.isActive || position.alphaAmount == 0) return false;

        // Get current value using accurate simulation
        uint256 simulatedTaoValueRao =
            ALPHA_PRECOMPILE.simSwapAlphaForTao(position.alphaNetuid, uint64(position.alphaAmount));

        // Calculate total debt including accrued fees
        uint256 accruedFees = _calculatePositionFees(user, positionId);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);

        if (totalDebt == 0) return false; // No debt means not liquidatable

        // Single threshold check: currentValue / totalDebt < threshold
        uint256 simulatedTaoWei = simulatedTaoValueRao.raoToWei();
        uint256 healthRatio = simulatedTaoWei.safeMul(PRECISION) / totalDebt;
        return healthRatio < liquidationThreshold; // Use single threshold only
    }

    // ==================== PUBLIC THIN WRAPPERS ====================

    function isPositionLiquidatable(address user, uint256 positionId) public view returns (bool) {
        return _isPositionLiquidatable(user, positionId);
    }

    // ==================== UTILIZATION MANAGEMENT ====================

    /**
     * @notice Update utilization rates for alpha pairs
     * @param alphaNetuid Alpha subnet ID
     */
    function _updateUtilizationRate(uint16 alphaNetuid) internal virtual;

    // ==================== ACCRUED BORROWING FEES CALCULATION FUNCTIONS ====================

    /**
     * @notice Calculate accrued borrowing fees for a position
     * @param user Position owner
     * @param positionId User's position identifier
     * @return accruedFees Total accrued fees
     */
    function _calculatePositionFees(address user, uint256 positionId)
        internal
        view
        virtual
        returns (uint256 accruedFees);
}
