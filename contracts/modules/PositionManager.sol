// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/TenexiumErrors.sol";
import "./FeeManager.sol";
import "./PrecompileAdapter.sol";

/**
 * @title PositionManager
 * @notice Functions for position opening, closing, and collateral management
 */
abstract contract PositionManager is FeeManager, PrecompileAdapter {
    using AlphaMath for uint256;

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

        AlphaPair storage pair = alphaPairs[alphaNetuid];

        // Check tier-based leverage limit
        uint256 userMaxLeverage = _getUserMaxLeverage(msg.sender);
        if (!(leverage >= PRECISION && leverage <= userMaxLeverage && leverage <= pair.maxLeverage)) {
            revert TenexiumErrors.LeverageTooHigh();
        }

        uint256 collateralAmount = msg.value;
        uint256 borrowedAmount = collateralAmount.safeMul(leverage - PRECISION) / PRECISION;

        // Check sufficient liquidity before proceeding
        if (!_checkSufficientLiquidity(borrowedAmount)) revert TenexiumErrors.InsufficientLiquidity();

        // Gross notional and fee withholding before staking
        uint256 totalTaoToStakeGross = collateralAmount.safeAdd(borrowedAmount);

        // Calculate and distribute trading fee on gross notional BEFORE staking
        uint256 tradingFeeAmount = _calculateTradingFeeWithDiscount(msg.sender, totalTaoToStakeGross);
        // Distribute trading fees
        _distributeFees(tradingFeeAmount, true);

        // Net TAO to stake after fee withholding
        uint256 taoToStakeNet = totalTaoToStakeGross.safeSub(tradingFeeAmount);
        if (taoToStakeNet == 0) revert TenexiumErrors.AmountZero();

        // Use simulation to get expected alpha amount with accurate slippage (based on net amount)
        // simSwap expects TAO in RAO; convert wei→rao
        uint256 expectedAlphaAmount = ALPHA_PRECOMPILE.simSwapTaoForAlpha(alphaNetuid, uint64(taoToStakeNet.weiToRao()));
        if (expectedAlphaAmount == 0) revert TenexiumErrors.SwapSimInvalid();

        // Calculate minimum acceptable alpha with slippage tolerance
        uint256 minAcceptableAlpha = expectedAlphaAmount.safeMul(10000 - maxSlippage) / 10000;
        // Calculate limit price based on minimum acceptable alpha
        uint256 limitPrice = taoToStakeNet / minAcceptableAlpha;

        // Execute stake operation using net TAO
        bytes32 validatorHotkey = pair.validatorHotkey;
        uint256 actualAlphaReceived = _stakeTaoForAlpha(validatorHotkey, taoToStakeNet, limitPrice, false, alphaNetuid);

        // Verify slippage tolerance
        if (actualAlphaReceived < minAcceptableAlpha) revert TenexiumErrors.SlippageTooHigh();

        // Get current alpha price for entry tracking
        uint256 entryPrice = (taoToStakeNet / expectedAlphaAmount).raoToWei();

        // Create new position with a unique per-user positionId
        uint256 positionId = nextPositionId[msg.sender];
        nextPositionId[msg.sender] = positionId + 1;
        Position storage position = positions[msg.sender][positionId];
        position.alphaNetuid = alphaNetuid;
        position.initialCollateral = collateralAmount;
        position.addedCollateral = 0;
        position.borrowed = borrowedAmount;
        position.alphaAmount = actualAlphaReceived;
        position.leverage = leverage;
        position.entryPrice = entryPrice;
        position.lastUpdateBlock = block.number;
        position.borrowingFeeDebt = accruedBorrowingFees;
        position.isActive = true;
        position.validatorHotkey = validatorHotkey;

        // Update global state
        totalCollateral = totalCollateral.safeAdd(collateralAmount);
        totalBorrowed = totalBorrowed.safeAdd(borrowedAmount);
        userCollateral[msg.sender] = userCollateral[msg.sender].safeAdd(collateralAmount);
        userTotalBorrowed[msg.sender] = userTotalBorrowed[msg.sender].safeAdd(borrowedAmount);

        pair.totalCollateral = pair.totalCollateral.safeAdd(collateralAmount);
        pair.totalBorrowed = pair.totalBorrowed.safeAdd(borrowedAmount);
        pair.totalAlphaStaked = pair.totalAlphaStaked.safeAdd(actualAlphaReceived);

        // Update metrics
        totalTrades += 1;
        totalVolume = totalVolume.safeAdd(totalTaoToStakeGross);
        userWeeklyTradingVolume[msg.sender][currentWeek] =
            userWeeklyTradingVolume[msg.sender][currentWeek].safeAdd(totalTaoToStakeGross);

        emit PositionOpened(
            msg.sender,
            positionId,
            alphaNetuid,
            collateralAmount,
            borrowedAmount,
            taoToStakeNet,
            actualAlphaReceived,
            tradingFeeAmount
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

        uint256 alphaToClose = amountToClose == 0 ? position.alphaAmount : amountToClose;
        if (alphaToClose > position.alphaAmount) revert TenexiumErrors.InvalidValue();

        // Use simulation to get expected TAO amount from unstaking alpha
        uint256 expectedTaoAmount =
            AlphaMath.raoToWei(ALPHA_PRECOMPILE.simSwapAlphaForTao(alphaNetuid, uint64(alphaToClose)));
        if (expectedTaoAmount == 0) revert TenexiumErrors.SwapSimInvalid();

        // Calculate minimum acceptable TAO with slippage tolerance
        uint256 minAcceptableTao = expectedTaoAmount.safeMul(10000 - maxSlippage) / 10000;
        // Calculate limit price based on minimum acceptable TAO
        uint256 limitPrice = minAcceptableTao / alphaToClose;

        // Calculate position components to repay
        uint256 borrowedToRepay = position.borrowed.safeMul(alphaToClose) / position.alphaAmount;
        uint256 initialCollateralToReturn = position.initialCollateral.safeMul(alphaToClose) / position.alphaAmount;
        uint256 feesToPay = accruedFees.safeMul(alphaToClose) / position.alphaAmount;
        uint256 addedCollateralToReturn = position.addedCollateral.safeMul(alphaToClose) / position.alphaAmount;

        // Calculate trading fees using actual TAO value on close leg
        uint256 tradingFeeAmount = _calculateTradingFeeWithDiscount(msg.sender, expectedTaoAmount);

        // Execute unstake operation
        bytes32 validatorHotkey = position.validatorHotkey;
        uint256 actualTaoReceived = _unstakeAlphaForTao(validatorHotkey, alphaToClose, limitPrice, false, alphaNetuid);

        // Verify slippage tolerance
        if (actualTaoReceived < minAcceptableTao) revert TenexiumErrors.SlippageTooHigh();

        // Calculate net return after all costs
        uint256 totalCosts = borrowedToRepay.safeAdd(feesToPay).safeAdd(tradingFeeAmount);
        if (actualTaoReceived.safeAdd(addedCollateralToReturn) < totalCosts) {
            revert TenexiumErrors.InsufficientProceeds();
        }

        uint256 netReturn = actualTaoReceived.safeAdd(addedCollateralToReturn).safeSub(totalCosts);
        // If net return is greater than collateral to return, take a performance fee for insurance fund
        if (netReturn > initialCollateralToReturn) {
            uint256 perfFeeInsurance =
                (netReturn.safeSub(initialCollateralToReturn)).safeMul(perfFeeInsuranceShare) / PRECISION;
            netReturn = netReturn.safeSub(perfFeeInsurance);
            (bool success,) = payable(insuranceManager).call{value: perfFeeInsurance}("");
            if (!success) revert TenexiumErrors.TransferFailed();
        }

        // Update position (partial or full close)
        if (alphaToClose == position.alphaAmount) {
            // Full close
            position.isActive = false;
            position.alphaAmount = 0;
            position.borrowed = 0;
            position.initialCollateral = 0;
            position.addedCollateral = 0;
        } else {
            // Partial close
            position.alphaAmount = position.alphaAmount.safeSub(alphaToClose);
            position.borrowed = position.borrowed.safeSub(borrowedToRepay);
            position.initialCollateral = position.initialCollateral.safeSub(initialCollateralToReturn);
            position.addedCollateral = position.addedCollateral.safeSub(addedCollateralToReturn);
        }

        // Update global state
        totalBorrowed = totalBorrowed.safeSub(borrowedToRepay);
        totalCollateral = totalCollateral.safeSub(initialCollateralToReturn).safeSub(addedCollateralToReturn);
        userTotalBorrowed[msg.sender] = userTotalBorrowed[msg.sender].safeSub(borrowedToRepay);
        userCollateral[msg.sender] =
            userCollateral[msg.sender].safeSub(initialCollateralToReturn).safeSub(addedCollateralToReturn);

        AlphaPair storage pair = alphaPairs[alphaNetuid];
        pair.totalBorrowed = pair.totalBorrowed.safeSub(borrowedToRepay);
        pair.totalCollateral = pair.totalCollateral.safeSub(initialCollateralToReturn).safeSub(addedCollateralToReturn);
        pair.totalAlphaStaked = pair.totalAlphaStaked.safeSub(alphaToClose);

        // Distribute fees
        _distributeFees(tradingFeeAmount, true);
        _distributeFees(feesToPay, false);

        // Return net proceeds to user
        if (netReturn > 0) {
            (bool success,) = payable(msg.sender).call{value: netReturn}("");
            if (!success) revert TenexiumErrors.TransferFailed();
        }

        // Update metrics
        totalTrades += 1;
        totalVolume = totalVolume.safeAdd(actualTaoReceived);
        userWeeklyTradingVolume[msg.sender][currentWeek] =
            userWeeklyTradingVolume[msg.sender][currentWeek].safeAdd(actualTaoReceived);

        emit PositionClosed(
            msg.sender,
            positionId,
            alphaNetuid,
            initialCollateralToReturn + addedCollateralToReturn,
            borrowedToRepay,
            alphaToClose,
            actualTaoReceived,
            feesToPay
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
        position.addedCollateral = position.addedCollateral.safeAdd(msg.value);
        position.lastUpdateBlock = block.number;

        // Update global state
        totalCollateral = totalCollateral.safeAdd(msg.value);
        userCollateral[msg.sender] = userCollateral[msg.sender].safeAdd(msg.value);

        AlphaPair storage pair = alphaPairs[alphaNetuid];
        pair.totalCollateral = pair.totalCollateral.safeAdd(msg.value);

        emit CollateralAdded(msg.sender, positionId, alphaNetuid, msg.value);
    }

    // ==================== INTERNAL HELPER FUNCTIONS ====================

    /**
     * @notice Check if sufficient liquidity exists for borrowing
     * @param borrowAmount Amount of TAO to borrow
     * @return hasLiquidity Whether sufficient liquidity exists
     */
    function _checkSufficientLiquidity(uint256 borrowAmount) internal view returns (bool hasLiquidity) {
        uint256 availableLiquidity = totalLpStakes > totalBorrowed ? totalLpStakes.safeSub(totalBorrowed) : 0;

        // Ensure enough liquidity with buffer
        uint256 requiredLiquidity = borrowAmount.safeMul(PRECISION + liquidityBufferRatio) / PRECISION;

        return availableLiquidity >= requiredLiquidity;
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
}
