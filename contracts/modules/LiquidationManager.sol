// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/RiskCalculator.sol";
import "../libraries/TenexiumErrors.sol";

/**
 * @title LiquidationManager
 * @notice Functions for position liquidation using single threshold approach
 */
abstract contract LiquidationManager is TenexiumStorage, TenexiumEvents {
    using AlphaMath for uint256;
    using RiskCalculator for RiskCalculator.PositionData;

    // ==================== LIQUIDATION FUNCTIONS ====================

    /**
     * @notice Liquidate an undercollateralized position
     * @param user Address of the position owner
     * @param alphaNetuid Alpha subnet ID
     * @param justificationUrl URL with liquidation justification
     * @param contentHash Hash of justification content
     * @dev Uses single threshold approach - liquidate immediately when threshold hit
     */
    function _liquidatePosition(
        address user,
        uint16 alphaNetuid,
        string calldata justificationUrl,
        bytes32 contentHash
    ) internal {
        Position storage position = positions[user][alphaNetuid];
        if (!position.isActive) revert TenexiumErrors.PositionInactive();
        if (position.alphaAmount == 0) revert TenexiumErrors.NoAlpha();
        
        // Verify liquidation is justified using single threshold
        if (!_isPositionLiquidatable(user, alphaNetuid)) revert TenexiumErrors.NotLiquidatable();
        
        // Calculate liquidation details using accurate simulation
        uint256 alphaAmountRao = position.alphaAmount.safeMul(PRECISION);
        uint256 simulatedTaoValueRao = ALPHA_PRECOMPILE.simSwapAlphaForTao(
            alphaNetuid,
            uint64(alphaAmountRao)
        );
        if (simulatedTaoValueRao == 0) revert TenexiumErrors.InvalidValue();
        uint256 simulatedTaoValue = AlphaMath.raoToWei(simulatedTaoValueRao);
        
        // Calculate total debt (borrowed + accrued fees)
        uint256 accruedFees = _calculateTotalAccruedFees(user, alphaNetuid);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);
        
        // Unstake alpha to get TAO using the validator hotkey used at open (fallback to protocolValidatorHotkey)
        bytes32 vHotkey = position.validatorHotkey == bytes32(0) ? protocolValidatorHotkey : position.validatorHotkey;
        uint256 taoReceived = _unstakeAlphaForTaoLiq(vHotkey, position.alphaAmount, alphaNetuid);
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
                (bool success, ) = msg.sender.call{value: liquidatorFeeShare}("");
                if (!success) revert TenexiumErrors.LiquiFeeTransferFailed();
            }
            // Protocol share of liquidation fees (→ buybacks)
            uint256 protocolFeeShare = feeToDistribute.safeMul(liquidationFeeProtocolShare) / PRECISION;
            protocolFees = protocolFees.safeAdd(protocolFeeShare);
            // fund buyback pool with protocol share
            if (protocolFeeShare > 0) {
                buybackPool = buybackPool.safeAdd(protocolFeeShare);
            }
            remaining = remaining.safeSub(feeToDistribute);
        }
        
        // 3. Return any remaining collateral to user
        if (remaining > 0) {
            (bool success, ) = user.call{value: remaining}("");
            if (!success) revert TenexiumErrors.CollateralReturnFailed();
        }
        
        // Update global statistics before clearing position fields
        totalBorrowed = totalBorrowed.safeSub(position.borrowed);
        totalCollateral = totalCollateral.safeSub(position.collateral);

        // Clear the liquidated position
        position.alphaAmount = 0;
        position.borrowed = 0;
        position.collateral = 0;
        position.accruedFees = 0;
        position.isActive = false;
        
        // Calculate liquidator bonus (share of liquidation fee)
        uint256 liquidatorFeeShareTotal = liquidationFeeAmount.safeMul(liquidationFeeLiquidatorShare) / PRECISION;
        
        emit PositionLiquidated(
            user,
            msg.sender,
            alphaNetuid,
            simulatedTaoValue,
            liquidationFeeAmount,
            liquidatorFeeShareTotal,
            justificationUrl,
            contentHash
        );
    }

    /**
     * @notice Create a liquidation request for review
     * @param params Liquidation parameters
     * @return requestId Unique request identifier
     */
    function _createLiquidationRequest(LiquidateParams calldata params)
        internal
        returns (bytes32 requestId)
    {
        if (!positions[params.user][params.alphaNetuid].isActive) revert TenexiumErrors.PositionNotFound(params.user, params.alphaNetuid);
        
        // Generate unique request ID
        requestId = keccak256(abi.encodePacked(
            params.user,
            params.alphaNetuid,
            block.number,
            msg.sender
        ));
        
        // Create liquidation request
        LiquidationRequest storage request = liquidationRequests[requestId];
        request.user = params.user;
        request.alphaNetuid = params.alphaNetuid;
        request.requestTime = block.number;
        request.deadline = block.number + 360;
        request.justificationUrl = params.justificationUrl;
        request.contentHash = params.contentHash;
        request.isProcessed = false;
        
        // Calculate liquidation amounts
        Position storage position = positions[params.user][params.alphaNetuid];
        request.collateralToLiquidate = position.collateral;
        request.alphaToLiquidate = position.alphaAmount;
        
        emit LiquidationRequestCreated(
            requestId,
            params.user,
            params.alphaNetuid,
            request.deadline
        );
        
        return requestId;
    }

    // ==================== RISK ASSESSMENT FUNCTIONS ====================

    /**
     * @notice Assess risk for a position with automated thresholds
     * @param user Address of position holder
     * @param alphaNetuid Alpha subnet ID
     * @return assessment Comprehensive risk assessment
     */
    function _assessPositionRisk(
        address user,
        uint16 alphaNetuid
    ) internal view returns (RiskCalculator.RiskAssessment memory assessment) {
        Position storage position = positions[user][alphaNetuid];
        if (!position.isActive) {
            return assessment;
        }
        
        // Convert position to RiskCalculator format
        RiskCalculator.PositionData memory positionData = RiskCalculator.PositionData({
            alphaAmount: position.alphaAmount,
            borrowed: position.borrowed,
            collateral: position.collateral,
            accruedFees: position.accruedFees,
            lastUpdateBlock: position.lastUpdateBlock,
            isActive: position.isActive
        });
        
        // Get current alpha price
        uint256 currentPrice = _getValidatedAlphaPrice(alphaNetuid);
        
        // Assess risk using library
        assessment = RiskCalculator.assessPositionRisk(
            positionData,
            currentPrice,
            liquidationThreshold
        );
        
        return assessment;
    }

    /**
     * @notice Check if a position is liquidatable using single threshold
     * @param user Position owner
     * @param alphaNetuid Alpha subnet ID
     * @return liquidatable True if position can be liquidated
     */
    function _isPositionLiquidatable(address user, uint16 alphaNetuid) 
        internal 
        view 
        returns (bool liquidatable) 
    {
        Position storage position = positions[user][alphaNetuid];
        if (!position.isActive || position.alphaAmount == 0) return false;
        
        // Get current value using accurate simulation
        uint256 simulatedAlphaRao2 = position.alphaAmount.safeMul(PRECISION);
        uint256 simulatedTaoValueRao2 = ALPHA_PRECOMPILE.simSwapAlphaForTao(
            alphaNetuid,
            uint64(simulatedAlphaRao2)
        );
        
        if (simulatedTaoValueRao2 == 0) return true;
        
        // Calculate total debt including accrued fees
        uint256 accruedFees = _calculateTotalAccruedFees(user, alphaNetuid);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);
        
        if (totalDebt == 0) return false; // No debt means not liquidatable
        
        // Single threshold check: currentValue / totalDebt < threshold
        uint256 simulatedTaoWei2 = AlphaMath.raoToWei(simulatedTaoValueRao2);
        uint256 healthRatio = simulatedTaoWei2.safeMul(PRECISION) / totalDebt;
        return healthRatio < liquidationThreshold; // Use single threshold only
    }

    /**
     * @notice Get position health ratio using single threshold system
     * @param user Position owner
     * @param alphaNetuid Alpha subnet ID
     * @return healthRatio Current health ratio (PRECISION = 100%)
     */
    function _getPositionHealthRatio(address user, uint16 alphaNetuid) 
        internal 
        view 
        returns (uint256 healthRatio) 
    {
        Position storage position = positions[user][alphaNetuid];
        if (!position.isActive || position.alphaAmount == 0) return 0;
        
        // Get current value using accurate simulation
        uint256 simulatedAlphaRao = position.alphaAmount.safeMul(PRECISION);
        if (simulatedAlphaRao == 0) return 0;
        uint256 simulatedTaoValueRao = ALPHA_PRECOMPILE.simSwapAlphaForTao(
            alphaNetuid,
            uint64(simulatedAlphaRao)
        );
        
        if (simulatedTaoValueRao == 0) return 0;
        uint256 simulatedTaoValue = AlphaMath.raoToWei(simulatedTaoValueRao);
        
        // Calculate total debt including accrued fees
        uint256 accruedFees = _calculateTotalAccruedFees(user, alphaNetuid);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);
        
        if (totalDebt == 0) return type(uint256).max; // Infinite health ratio
        
        return simulatedTaoValue.safeMul(PRECISION) / totalDebt;
    }

    /**
     * @notice Batch check multiple positions for liquidation opportunities
     * @param users Array of user addresses
     * @param alphaNetuids Array of Alpha subnet IDs
     * @return liquidatablePositions Array of liquidatable position indices
     */
    function _batchCheckLiquidatable(
        address[] memory users,
        uint16[] memory alphaNetuids
    ) internal view returns (uint256[] memory liquidatablePositions) {
        if (users.length != alphaNetuids.length) revert TenexiumErrors.ArrayLengthMismatch();
        
        uint256[] memory tempResults = new uint256[](users.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < users.length; i++) {
            if (_isPositionLiquidatable(users[i], alphaNetuids[i])) {
                tempResults[count] = i;
                count++;
            }
        }
        
        // Create result array with exact size
        liquidatablePositions = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            liquidatablePositions[i] = tempResults[i];
        }
        
        return liquidatablePositions;
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get liquidation statistics for an address
     * @param liquidator Liquidator address
     * @return totalLiquidations Number of liquidations performed
     * @return totalValue Total value liquidated
     * @return rewardsEarned Total rewards earned
     * @return currentScore Current liquidation score
     */
    function getLiquidatorStats(address liquidator) external view returns (
        uint256 totalLiquidations,
        uint256 totalValue,
        uint256 rewardsEarned,
        uint256 currentScore
    ) {
        currentScore = liquidatorScores[liquidator];
        rewardsEarned = liquidatorFeeRewards[liquidator];
        
        // Simplified calculations
        totalLiquidations = currentScore;
        totalValue = currentScore * 1e18;
    }

    /**
     * @notice Get liquidation request details
     * @param requestId Request identifier
     * @return request Liquidation request details
     */
    function getLiquidationRequest(bytes32 requestId) external view returns (LiquidationRequest memory request) {
        return liquidationRequests[requestId];
    }

    // ==================== INTERNAL HELPER FUNCTIONS ====================
    
    /**
     * @notice Get validated alpha price with safety checks
     * @param alphaNetuid Alpha subnet ID
     * @return price Current alpha price
     */
    function _getValidatedAlphaPrice(uint16 alphaNetuid) internal view returns (uint256 price) {
        uint256 priceRao = ALPHA_PRECOMPILE.getAlphaPrice(alphaNetuid);
        if (priceRao == 0) revert TenexiumErrors.InvalidAlphaPrice();
        return AlphaMath.priceRaoToWei(priceRao);
    }

    /**
     * @notice Calculate accrued borrowing fees for a position
     * @param user Position owner
     * @param alphaNetuid Alpha subnet ID
     * @return accruedFees Total accrued fees
     */
    function _calculateTotalAccruedFees(address user, uint16 alphaNetuid) 
        internal 
        view 
        returns (uint256 accruedFees) 
    {
        Position storage position = positions[user][alphaNetuid];
        if (!position.isActive) return 0;
        
        uint256 blocksElapsed = block.number - position.lastUpdateBlock;
        AlphaPair storage pair = alphaPairs[alphaNetuid];
        uint256 utilization = pair.totalCollateral == 0 ? 0 : pair.totalBorrowed.safeMul(PRECISION) / pair.totalCollateral;
        uint256 ratePer360 = RiskCalculator.dynamicBorrowRatePer360(utilization);
        uint256 borrowingFeeAmount = position.borrowed
            .safeMul(ratePer360)
            .safeMul(blocksElapsed) / (PRECISION * 360);
        
        return position.accruedFees + borrowingFeeAmount;
    }

    // ==================== PRECOMPILE INTERACTION FUNCTIONS ====================

    /**
     * @notice Unstake Alpha tokens for TAO using correct precompile
     * @param alphaNetuid Alpha subnet ID
     * @param alphaAmount Alpha amount to unstake
     * @return taoReceived TAO received from unstaking
     */
    function _unstakeAlphaForTaoLiq(
        bytes32 validatorHotkey,
        uint256 alphaAmount,
        uint16 alphaNetuid
    ) internal returns (uint256 taoReceived) {
        // Get initial TAO balance
        uint256 initialBalance = address(this).balance;

        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.removeStake.selector,
            validatorHotkey,
            alphaAmount,
            uint256(alphaNetuid)
        );
        (bool success, ) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) revert TenexiumErrors.UnstakeFailed();

        // Calculate TAO received
        uint256 finalBalance = address(this).balance;
        taoReceived = finalBalance - initialBalance;

        return taoReceived;
    }

    // ==================== PUBLIC THIN WRAPPERS ====================
    
    function isPositionLiquidatable(address user, uint16 alphaNetuid) public view returns (bool) {
        return _isPositionLiquidatable(user, alphaNetuid);
    }

    function getPositionHealthRatio(address user, uint16 alphaNetuid) public view returns (uint256) {
        return _getPositionHealthRatio(user, alphaNetuid);
    }

    function batchCheckLiquidatable(address[] calldata users, uint16[] calldata alphaNetuids)
        external
        view
        returns (uint256[] memory)
    {
        return _batchCheckLiquidatable(users, alphaNetuids);
    }
} 
