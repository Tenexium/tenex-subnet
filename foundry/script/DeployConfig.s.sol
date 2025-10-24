// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title DeployConfig
 * @notice Deployment configuration constants for TenexiumProtocol
 * @dev Mirrors the TypeScript deploy-config.ts file for consistency
 */
contract DeployConfig {
    // ============================================================================
    // CONSTANTS
    // ============================================================================

    // Precision for percentage calculations (1e9 = 100%)
    uint256 public constant PRECISION = 1e9;

    // ============================================================================
    // LIQUIDITY GUARDRAILS & RATE LIMITS
    // ============================================================================

    // Minimum liquidity threshold: 100 TAO
    uint256 public constant MIN_LIQUIDITY_THRESHOLD = 100 ether;

    // Maximum utilization rate: 90%
    uint256 public constant MAX_UTILIZATION_RATE = 900_000_000; // 90% * PRECISION

    // Liquidity buffer ratio: 20%
    uint256 public constant LIQUIDITY_BUFFER_RATIO = 200_000_000; // 20% * PRECISION

    // Cooldown blocks
    uint256 public constant USER_COOLDOWN_BLOCKS = 10;
    uint256 public constant LP_COOLDOWN_BLOCKS = 10;

    // ============================================================================
    // BUYBACK ECONOMICS
    // ============================================================================

    // Buyback execution threshold: 1 TAO minimum balance
    uint256 public constant BUYBACK_EXECUTION_THRESHOLD = 1 ether;

    // Buyback rate: 50% of pool per buyback
    uint256 public constant BUYBACK_RATE = 500_000_000; // 50% * PRECISION

    // Buyback interval: 7200 blocks (default cadence)
    uint256 public constant BUYBACK_INTERVAL_BLOCKS = 7200;

    // Vesting duration: ~12 months in blocks
    uint256 public constant VESTING_DURATION_BLOCKS = 2_628_000;

    // Cliff duration: ~3 months in blocks
    uint256 public constant CLIFF_DURATION_BLOCKS = 648_000;

    // ============================================================================
    // FEE PARAMETERS (GOVERNANCE)
    // ============================================================================

    // Base liquidation fee: 2%
    uint256 public constant BASE_LIQUIDATION_FEE = 20_000_000; // 2% * PRECISION

    // Borrowing fee rate: 0.005% per 360 blocks baseline
    uint256 public constant BORROWING_FEE_RATE = 50_000; // 0.005% * PRECISION

    // Base trading fee: 0.3%
    uint256 public constant BASE_TRADING_FEE = 3_000_000; // 0.3% * PRECISION

    // Maximum leverage: 10x
    uint256 public constant MAX_LEVERAGE = 10_000_000_000; // 10x * PRECISION

    // Liquidation threshold: 110%
    uint256 public constant LIQUIDATION_THRESHOLD = 1_100_000_000; // 110% * PRECISION

    // ============================================================================
    // FEE DISTRIBUTIONS (MUST SUM TO PRECISION = 1e9)
    // ============================================================================

    // Trading fee distribution
    uint256 public constant TRADING_FEE_LP_SHARE = 300_000_000; // 30% to LPs
    uint256 public constant TRADING_FEE_LIQUIDATOR_SHARE = 0; // 0% to Liquidators
    uint256 public constant TRADING_FEE_PROTOCOL_SHARE = 700_000_000; // 70% to Protocol

    // Borrowing fee distribution
    uint256 public constant BORROWING_FEE_LP_SHARE = 350_000_000; // 35% to LPs
    uint256 public constant BORROWING_FEE_LIQUIDATOR_SHARE = 0; // 0% to Liquidators
    uint256 public constant BORROWING_FEE_PROTOCOL_SHARE = 650_000_000; // 65% to Protocol

    // Liquidation fee distribution
    uint256 public constant LIQUIDATION_FEE_LP_SHARE = 0; // 0% to LPs
    uint256 public constant LIQUIDATION_FEE_LIQUIDATOR_SHARE = 400_000_000; // 40% to Liquidators
    uint256 public constant LIQUIDATION_FEE_PROTOCOL_SHARE = 600_000_000; // 60% to Protocol

    // ============================================================================
    // TIER THRESHOLDS (TOKEN AMOUNTS)
    // ============================================================================

    // Tier thresholds in wei (token amounts)
    uint256 public constant TIER_1_THRESHOLD = 100 ether; // 100 tokens
    uint256 public constant TIER_2_THRESHOLD = 1000 ether; // 1,000 tokens
    uint256 public constant TIER_3_THRESHOLD = 5000 ether; // 5,000 tokens
    uint256 public constant TIER_4_THRESHOLD = 20000 ether; // 20,000 tokens
    uint256 public constant TIER_5_THRESHOLD = 100000 ether; // 100,000 tokens

    // ============================================================================
    // TIER FEE DISCOUNTS (PRECISION = 1e9)
    // ============================================================================

    // Tier fee discounts
    uint256 public constant TIER_0_FEE_DISCOUNT = 0; // Tier 0: 0%
    uint256 public constant TIER_1_FEE_DISCOUNT = 100_000_000; // Tier 1: 10%
    uint256 public constant TIER_2_FEE_DISCOUNT = 200_000_000; // Tier 2: 20%
    uint256 public constant TIER_3_FEE_DISCOUNT = 300_000_000; // Tier 3: 30%
    uint256 public constant TIER_4_FEE_DISCOUNT = 400_000_000; // Tier 4: 40%
    uint256 public constant TIER_5_FEE_DISCOUNT = 500_000_000; // Tier 5: 50%

    // ============================================================================
    // TIER LEVERAGE LIMITS (SCALED BY PRECISION = 1e9)
    // ============================================================================

    // Tier maximum leverages
    uint256 public constant TIER_0_MAX_LEVERAGE = 2_000_000_000; // Tier 0: 2x
    uint256 public constant TIER_1_MAX_LEVERAGE = 3_000_000_000; // Tier 1: 3x
    uint256 public constant TIER_2_MAX_LEVERAGE = 4_000_000_000; // Tier 2: 4x
    uint256 public constant TIER_3_MAX_LEVERAGE = 5_000_000_000; // Tier 3: 5x
    uint256 public constant TIER_4_MAX_LEVERAGE = 7_000_000_000; // Tier 4: 7x
    uint256 public constant TIER_5_MAX_LEVERAGE = 10_000_000_000; // Tier 5: 10x

    // ============================================================================
    // PROTOCOL VALIDATOR HOTKEY
    // ============================================================================

    // Governed protocol validator hotkey (bytes32)
    bytes32 public constant PROTOCOL_VALIDATOR_HOTKEY =
        0x4492d90ca4f56368e7a06ceeaea3859d312f12280df357d790637674b928df67;

    // ============================================================================
    // ARRAY GETTERS FOR EASY ACCESS
    // ============================================================================

    /**
     * @notice Get all tier thresholds as an array
     * @return Array of tier thresholds in wei
     */
    function getTierThresholds() internal pure returns (uint256[] memory) {
        uint256[] memory thresholds = new uint256[](5);
        thresholds[0] = TIER_1_THRESHOLD;
        thresholds[1] = TIER_2_THRESHOLD;
        thresholds[2] = TIER_3_THRESHOLD;
        thresholds[3] = TIER_4_THRESHOLD;
        thresholds[4] = TIER_5_THRESHOLD;
        return thresholds;
    }

    /**
     * @notice Get all tier fee discounts as an array
     * @return Array of tier fee discounts (PRECISION = 1e9)
     */
    function getTierFeeDiscounts() internal pure returns (uint256[] memory) {
        uint256[] memory discounts = new uint256[](6);
        discounts[0] = TIER_0_FEE_DISCOUNT;
        discounts[1] = TIER_1_FEE_DISCOUNT;
        discounts[2] = TIER_2_FEE_DISCOUNT;
        discounts[3] = TIER_3_FEE_DISCOUNT;
        discounts[4] = TIER_4_FEE_DISCOUNT;
        discounts[5] = TIER_5_FEE_DISCOUNT;
        return discounts;
    }

    /**
     * @notice Get all tier leverage limits as an array
     * @return Array of tier leverage limits (PRECISION = 1e9)
     */
    function getTierMaxLeverages() internal pure returns (uint256[] memory) {
        uint256[] memory leverages = new uint256[](6);
        leverages[0] = TIER_0_MAX_LEVERAGE;
        leverages[1] = TIER_1_MAX_LEVERAGE;
        leverages[2] = TIER_2_MAX_LEVERAGE;
        leverages[3] = TIER_3_MAX_LEVERAGE;
        leverages[4] = TIER_4_MAX_LEVERAGE;
        leverages[5] = TIER_5_MAX_LEVERAGE;
        return leverages;
    }

    /**
     * @notice Get trading fee distribution as an array
     * @return Array of [lpShare, liquidatorShare, protocolShare] (PRECISION = 1e9)
     */
    function getTradingFeeDistribution() internal pure returns (uint256[] memory) {
        uint256[] memory distribution = new uint256[](3);
        distribution[0] = TRADING_FEE_LP_SHARE;
        distribution[1] = TRADING_FEE_LIQUIDATOR_SHARE;
        distribution[2] = TRADING_FEE_PROTOCOL_SHARE;
        return distribution;
    }

    /**
     * @notice Get borrowing fee distribution as an array
     * @return Array of [lpShare, liquidatorShare, protocolShare] (PRECISION = 1e9)
     */
    function getBorrowingFeeDistribution() internal pure returns (uint256[] memory) {
        uint256[] memory distribution = new uint256[](3);
        distribution[0] = BORROWING_FEE_LP_SHARE;
        distribution[1] = BORROWING_FEE_LIQUIDATOR_SHARE;
        distribution[2] = BORROWING_FEE_PROTOCOL_SHARE;
        return distribution;
    }

    /**
     * @notice Get liquidation fee distribution as an array
     * @return Array of [lpShare, liquidatorShare, protocolShare] (PRECISION = 1e9)
     */
    function getLiquidationFeeDistribution() internal pure returns (uint256[] memory) {
        uint256[] memory distribution = new uint256[](3);
        distribution[0] = LIQUIDATION_FEE_LP_SHARE;
        distribution[1] = LIQUIDATION_FEE_LIQUIDATOR_SHARE;
        distribution[2] = LIQUIDATION_FEE_PROTOCOL_SHARE;
        return distribution;
    }
}
