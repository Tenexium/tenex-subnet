// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library TenexiumErrors {
    // Generic / governance
    error InvalidValue();
    error FunctionNotFound();
    error DirectTaoTransferProhibited();

    // Pairs / params
    error PairExists();
    error PairMissing();
    error LeverageTooHigh();
    error FeeTooHigh();
    error DistributionInvalid();
    error ThresholdTooLow();

    // Liquidity / LP
    error NotLiquidityProvider();
    error NoFees();
    error LpMinDeposit();
    error InvalidWithdrawalAmount();
    error UtilizationExceeded();
    error UserCooldownActive();
    error LpCooldownActive();
    error BorrowingFeesCooldownActive();

    // Positions
    error SlippageTooHigh();
    error MinDeposit();
    error InsufficientLiquidity();
    error SwapSimInvalid();
    error InsufficientProceeds();

    // Transfer / TransferStake / Stake / Unstake
    error TransferFailed();
    error TransferStakeFailed();
    error StakeFailed();
    error UnstakeFailed();

    // Liquidation
    error NoAlpha();
    error NotLiquidatable();
    error LiquiFeeTransferFailed();
    error CollateralReturnFailed();
    error PositionNotFound();

    // Rewards
    error NoRewards();

    // Buyback
    error AmountZero();
    error PercentageTooHigh();
    error BuybackConditionsNotMet();

    // Permission controls
    error FunctionNotPermitted();

    // Liquidity provider tracking
    error AddressAlreadyAssociated();
    error MaxLiquidityProvidersPerHotkeyReached();

    // Manager
    error NotManager();
}
