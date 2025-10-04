// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/RiskCalculator.sol";
import "../libraries/TenexiumErrors.sol";
import "./FeeManager.sol";
import "./PrecompileAdapter.sol";

/**
 * @title PositionManager
 * @notice Functions for position opening, closing, and collateral management
 */
abstract contract PositionManager is FeeManager, PrecompileAdapter {
    using AlphaMath for uint256;
    using RiskCalculator for RiskCalculator.PositionData;

    // ==================== POSITION MANAGEMENT FUNCTIONS ====================

    /**
     * @notice Open a leveraged position (TAO-only deposits)
     * @param alphaNetuid Alpha subnet ID
     * @param leverage Desired leverage (must be <= maxLeverage)
     * @param maxSlippage Maximum acceptable slippage (in basis points)
     */
    function _openPosition(uint16 alphaNetuid, uint256 leverage, uint256 maxSlippage) internal {
        if (maxSlippage > 1000) revert TenexiumErrors.SlippageTooHigh();
        if (msg.value < 1e17) revert TenexiumErrors.MinDeposit();

        // Check tier-based leverage limit
        uint256 userMaxLeverage = _getUserMaxLeverage(msg.sender);
        if (!(leverage >= PRECISION && leverage <= userMaxLeverage)) revert TenexiumErrors.LeverageTooHigh(leverage);

        uint256 collateralAmount = msg.value;
        uint256 borrowedAmount = collateralAmount.safeMul(leverage - PRECISION) / PRECISION;

        // Check sufficient liquidity before proceeding
        if (!_checkSufficientLiquidity(borrowedAmount)) revert TenexiumErrors.InsufficientLiquidity();

        // Gross notional and fee withholding before staking
        uint256 totalTaoToStakeGross = collateralAmount + borrowedAmount;

        // Calculate and distribute trading fee on gross notional BEFORE staking
        uint256 tradingFeeAmount = _calculateTradingFee(msg.sender, totalTaoToStakeGross);
        if (tradingFeeAmount > 0) {
            _distributeTradingFees(tradingFeeAmount);
            // Accumulate protocol's share of trading fees in protocolFees
            uint256 protocolShare = tradingFeeAmount.safeMul(tradingFeeProtocolShare) / PRECISION;
            if (protocolShare > 0) {
                protocolFees += protocolShare;
            }
        }

        // Net TAO to stake after fee withholding
        uint256 taoToStakeNet = totalTaoToStakeGross.safeSub(tradingFeeAmount);
        if (taoToStakeNet == 0) revert TenexiumErrors.AmountZero();

        // Use simulation to get expected alpha amount with accurate slippage (based on net amount)
        // simSwap expects TAO in RAO; convert wei→rao
        uint256 expectedAlphaAmount = ALPHA_PRECOMPILE.simSwapTaoForAlpha(alphaNetuid, uint64(taoToStakeNet.weiToRao()));
        if (expectedAlphaAmount == 0) revert TenexiumErrors.SwapSimInvalid();

        // Calculate minimum acceptable alpha with slippage tolerance
        uint256 minAcceptableAlpha = expectedAlphaAmount.safeMul(10000 - maxSlippage) / 10000;

        // Execute stake operation using net TAO
        bytes32 validatorHotkey = _getAlphaValidatorHotkey(alphaNetuid);
        uint256 actualAlphaReceived = _stakeTaoForAlpha(validatorHotkey, taoToStakeNet, alphaNetuid);

        // Verify slippage tolerance
        if (actualAlphaReceived < minAcceptableAlpha) revert TenexiumErrors.SlippageTooHigh();

        // Get current alpha price for entry tracking
        uint256 entryPrice = (taoToStakeNet / expectedAlphaAmount).raoToWei();

        // Create new position with a unique per-user positionId
        uint256 positionId = nextPositionId[msg.sender];
        nextPositionId[msg.sender] = positionId + 1;
        Position storage position = positions[msg.sender][positionId];
        position.alphaNetuid = alphaNetuid;
        position.collateral = collateralAmount;
        position.borrowed = borrowedAmount;
        position.alphaAmount = actualAlphaReceived;
        position.leverage = leverage;
        position.entryPrice = entryPrice;
        position.lastUpdateBlock = block.number;
        position.accruedFees = 0;
        position.isActive = true;
        position.validatorHotkey = validatorHotkey;

        // Update global state
        totalCollateral += collateralAmount;
        totalBorrowed += borrowedAmount;
        userCollateral[msg.sender] += collateralAmount;
        userTotalBorrowed[msg.sender] += borrowedAmount;

        AlphaPair storage pair = alphaPairs[alphaNetuid];
        pair.totalCollateral += collateralAmount;
        pair.totalBorrowed += borrowedAmount;

        _updateUtilizationRate(alphaNetuid);

        // Update metrics
        totalVolume += totalTaoToStakeGross;
        totalTrades += 1;
        userTotalVolume[msg.sender] += totalTaoToStakeGross;

        emit PositionOpened(
            msg.sender,
            positionId,
            alphaNetuid,
            collateralAmount,
            borrowedAmount,
            actualAlphaReceived,
            leverage,
            entryPrice
        );
    }

    /**
     * @notice Close a position and return collateral (TAO-only withdrawals)
     * @param positionId User's position identifier
     * @param amountToClose Amount of alpha to close (0 for full close)
     * @param maxSlippage Maximum acceptable slippage (in basis points)
     */
    function _closePosition(uint256 positionId, uint256 amountToClose, uint256 maxSlippage) internal {
        if (maxSlippage > 1000) revert TenexiumErrors.SlippageTooHigh();
        Position storage position = positions[msg.sender][positionId];
        uint16 alphaNetuid = position.alphaNetuid;

        // Calculate accrued borrowing fees
        uint256 accruedFees = _calculatePositionFees(msg.sender, positionId);
        position.accruedFees += accruedFees;

        uint256 alphaToClose = amountToClose == 0 ? position.alphaAmount : amountToClose;
        if (alphaToClose > position.alphaAmount) revert TenexiumErrors.InvalidValue();

        // Use simulation to get expected TAO amount from unstaking alpha
        uint256 expectedTaoAmount =
            AlphaMath.raoToWei(ALPHA_PRECOMPILE.simSwapAlphaForTao(alphaNetuid, uint64(alphaToClose)));
        if (expectedTaoAmount == 0) revert TenexiumErrors.UnstakeSimInvalid();

        // Calculate minimum acceptable TAO with slippage tolerance
        uint256 minAcceptableTao = expectedTaoAmount.safeMul(10000 - maxSlippage) / 10000;

        // Calculate position components to repay
        uint256 borrowedToRepay = position.borrowed.safeMul(alphaToClose) / position.alphaAmount;
        uint256 collateralToReturn = position.collateral.safeMul(alphaToClose) / position.alphaAmount;
        uint256 feesToPay = position.accruedFees.safeMul(alphaToClose) / position.alphaAmount;

        // Calculate trading fees using actual TAO value on close leg
        uint256 tradingFeeAmount = _calculateTradingFee(msg.sender, expectedTaoAmount);

        // Execute unstake operation
        bytes32 validatorHotkey = position.validatorHotkey;
        uint256 actualTaoReceived = _unstakeAlphaForTao(validatorHotkey, alphaToClose, alphaNetuid);

        // Verify slippage tolerance
        if (actualTaoReceived < minAcceptableTao) revert TenexiumErrors.UnstakeSlippage();

        // Calculate net return after all costs
        uint256 totalCosts = borrowedToRepay + feesToPay + tradingFeeAmount;
        if (actualTaoReceived < totalCosts) revert TenexiumErrors.InsufficientProceeds();

        uint256 netReturn = actualTaoReceived - totalCosts;

        // Update position (partial or full close)
        if (alphaToClose == position.alphaAmount) {
            // Full close
            position.isActive = false;
            position.alphaAmount = 0;
            position.borrowed = 0;
            position.collateral = 0;
            position.accruedFees = 0;
        } else {
            // Partial close
            position.alphaAmount -= alphaToClose;
            position.borrowed -= borrowedToRepay;
            position.collateral -= collateralToReturn;
            position.accruedFees -= feesToPay;
        }

        // Update global state
        totalBorrowed -= borrowedToRepay;
        totalCollateral -= collateralToReturn;
        userTotalBorrowed[msg.sender] -= borrowedToRepay;
        userCollateral[msg.sender] -= collateralToReturn;

        AlphaPair storage pair = alphaPairs[alphaNetuid];
        pair.totalBorrowed -= borrowedToRepay;
        pair.totalCollateral -= collateralToReturn;

        _updateUtilizationRate(alphaNetuid);

        // Distribute fees
        _distributeTradingFees(tradingFeeAmount);
        _distributeBorrowingFees(feesToPay);

        // Accumulate protocol shares in protocolFees
        if (tradingFeeAmount > 0) {
            uint256 protocolTradingShare = tradingFeeAmount.safeMul(tradingFeeProtocolShare) / PRECISION;
            if (protocolTradingShare > 0) {
                protocolFees += protocolTradingShare;
            }
        }
        if (feesToPay > 0) {
            uint256 protocolBorrowShare = feesToPay.safeMul(borrowingFeeProtocolShare) / PRECISION;
            if (protocolBorrowShare > 0) {
                protocolFees += protocolBorrowShare;
            }
        }

        // Return net proceeds to user
        if (netReturn > 0) {
            (bool success,) = payable(msg.sender).call{value: netReturn}("");
            if (!success) revert TenexiumErrors.TransferFailed();
        }

        // Calculate realized PnL (profit and loss)
        int256 pnl = int256(actualTaoReceived) - int256(borrowedToRepay + feesToPay) - int256(collateralToReturn);

        emit PositionClosed(
            msg.sender,
            positionId,
            alphaNetuid,
            collateralToReturn,
            borrowedToRepay,
            alphaToClose,
            pnl,
            tradingFeeAmount
        );
    }

    /**
     * @notice Add collateral to an existing position (TAO only)
     * @param positionId User's position identifier
     */
    function _addCollateral(uint256 positionId) internal {
        if (msg.value == 0) revert TenexiumErrors.AmountZero();

        Position storage position = positions[msg.sender][positionId];
        uint16 alphaNetuid = position.alphaNetuid;

        // Add TAO to collateral
        position.collateral += msg.value;
        position.lastUpdateBlock = block.number;

        // Update global state
        totalCollateral += msg.value;
        userCollateral[msg.sender] += msg.value;

        AlphaPair storage pair = alphaPairs[alphaNetuid];
        pair.totalCollateral += msg.value;

        emit CollateralAdded(msg.sender, positionId, alphaNetuid, msg.value);
    }

    // ==================== INTERNAL HELPER FUNCTIONS ====================

    /**
     * @notice Check if sufficient liquidity exists for borrowing
     * @param borrowAmount Amount of TAO to borrow
     * @return hasLiquidity Whether sufficient liquidity exists
     */
    function _checkSufficientLiquidity(uint256 borrowAmount) internal view returns (bool hasLiquidity) {
        uint256 availableLiquidity = _internalAvailableLiquidity();

        // Ensure enough liquidity with buffer
        uint256 requiredLiquidity = borrowAmount.safeMul(PRECISION + liquidityBufferRatio) / PRECISION;

        return availableLiquidity >= requiredLiquidity;
    }

    /**
     * @notice Get available liquidity in the pool
     * @return availableLiquidity Amount of TAO available for borrowing
     */
    function _internalAvailableLiquidity() internal view returns (uint256 availableLiquidity) {
        return totalLpStakes > totalBorrowed ? totalLpStakes - totalBorrowed : 0;
    }

    /**
     * @notice Get user's maximum leverage based on tier thresholds
     */
    function _getUserMaxLeverage(address user) internal view returns (uint256 maxLeverageOut) {
        bytes32 user_ss58Pubkey = ADDRESS_CONVERSION_CONTRACT.addressToSS58Pub(user);
        uint256 balance = STAKING_PRECOMPILE.getStake(protocolValidatorHotkey, user_ss58Pubkey, TENEX_NETUID);
        if (balance >= tier5Threshold) return tier5MaxLeverage;
        if (balance >= tier4Threshold) return tier4MaxLeverage;
        if (balance >= tier3Threshold) return tier3MaxLeverage;
        if (balance >= tier2Threshold) return tier2MaxLeverage;
        if (balance >= tier1Threshold) return tier1MaxLeverage;
        return tier0MaxLeverage;
    }

    /**
     * @notice Calculate trading fees for a position
     * @param user User address
     * @param positionValue Position value in TAO
     * @return tradingFee Trading fee amount
     */
    function _calculateTradingFee(address user, uint256 positionValue) internal view returns (uint256 tradingFee) {
        uint256 baseFee = positionValue.safeMul(tradingFeeRate) / PRECISION;
        // Apply tier-based discount
        return _calculateDiscountedFee(user, baseFee);
    }

    /**
     * @notice Calculate accrued fees for a position
     * @param user User address
     * @param positionId User's position identifier
     * @return accruedFees Total accrued borrowing fees
     */
    function _calculatePositionFees(address user, uint256 positionId) internal view returns (uint256 accruedFees) {
        Position storage position = positions[user][positionId];
        if (!position.isActive) return 0;

        uint256 blocksElapsed = block.number - position.lastUpdateBlock;
        AlphaPair storage pair = alphaPairs[position.alphaNetuid];
        uint256 utilization =
            pair.totalCollateral == 0 ? 0 : pair.totalBorrowed.safeMul(PRECISION) / pair.totalCollateral;
        uint256 ratePer360 = RiskCalculator.dynamicBorrowRatePer360(utilization);
        uint256 borrowingFeeAmount = position.borrowed.safeMul(ratePer360).safeMul(blocksElapsed) / (PRECISION * 360);

        return borrowingFeeAmount;
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
            pair.borrowingRate =
                RiskCalculator.dynamicBorrowRatePer360(totalBorrowed.safeMul(PRECISION) / totalLpStakes);
        }

        emit UtilizationRateUpdated(alphaNetuid, pair.utilizationRate, pair.borrowingRate);
    }
}
