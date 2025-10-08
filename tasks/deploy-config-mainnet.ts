// Types for deployment configuration
export interface FeeDistribution {
    lpShare: string;      // LP share (PRECISION=1e9)
    liquidatorShare: string; // Liquidator share (PRECISION=1e9)
    protocolShare: string;   // Protocol share (PRECISION=1e9)
}

export interface DeployConfig {
    // Liquidity guardrails & rate limits
    minLiquidityThreshold: string;   // 100 TAO
    maxUtilizationRate: string;      // 90% (PRECISION=1e9)
    liquidityBufferRatio: string;    // 20% (PRECISION=1e9)
    userCooldownBlocks: string;      // 10 blocks
    lpCooldownBlocks: string;        // 10 blocks
    
    // Buyback economics
    buybackExecutionThreshold: string; // min balance to execute buyback (wei)
    buybackRate: string;              // 60% of pool per buyback (PRECISION=1e9)
    buybackIntervalBlocks: string;    // cadence blocks (default)
    
    // Governance Fee
    protocolFeeGoveranceShare: string; // 1% of protocol fees (PRECISION=1e9)

    // Insurance Rates
    protocolFeeInsuranceShare: string; // 10% of protocol fees (PRECISION=1e9)
    lpFeeInsuranceShare: string; // 10% of lp fees (PRECISION=1e9)
    perfFeeInsuranceShare: string; // 10% of positive position profits (PRECISION=1e9)

    // Fee parameters (governable)
    baseLiquidationFee: string;       // 2% = 0.02 * 1e9 (PRECISION)
    borrowingFeeRate: string;         // baseline 0.005% per 360 blocks (PRECISION)
    baseTradingFee: string;           // 0.3% = 0.003 * 1e9 (PRECISION)
    maxLeverage: string;              // 10x (10 * PRECISION)
    liquidationThreshold: string;     // 110% = 1.10 * PRECISION

    // Fee distributions (must each sum to PRECISION=1e9)
    tradingFeeDistribution: FeeDistribution;
    borrowingFeeDistribution: FeeDistribution;
    liquidationFeeDistribution: FeeDistribution;

    // Tier thresholds (token amounts)
    tierThresholds: string[];

    // Tier fee discounts (PRECISION=1e9)
    tierFeeDiscounts: string[];

    // Tier leverage limits (scaled by PRECISION=1e9)
    tierMaxLeverages: string[];

    // Governed protocol validator hotkey (bytes32)
    protocolValidatorHotkey: string;

    // Function permissions (default)
    functionPermissions: boolean[];

    // Max liquidity providers per hotkey
    maxLiquidityProvidersPerHotkey: string;

    // Subnet manager
    versionKey: string;
}

const deployConfig: DeployConfig = {
    // Liquidity guardrails & rate limits
    minLiquidityThreshold: "1000000000000000000000",   // 1000 TAO
    maxUtilizationRate: "900000000",                  // 90% (PRECISION=1e9)
    liquidityBufferRatio: "200000000",                // 20% (PRECISION=1e9)
    userCooldownBlocks: "1",                         // 1 blocks
    lpCooldownBlocks: "360",                           // 360 blocks
    
    // Buyback economics
    buybackExecutionThreshold: "1000000000000000000", // min balance to execute buyback (wei)
    buybackRate: "600000000",                         // 60% of pool per buyback (PRECISION=1e9)
    buybackIntervalBlocks: "7200",                    // cadence blocks (default)

    // Governance Fee
    protocolFeeGoveranceShare: "10000000",            // 1% of protocol fees (PRECISION=1e9)

    // Insurance Rates
    protocolFeeInsuranceShare: "100000000",           // 10% of protocol fees (PRECISION=1e9)
    lpFeeInsuranceShare: "100000000",                 // 10% of lp fees (PRECISION=1e9)
    perfFeeInsuranceShare: "100000000",               // 10% of positive position profits (PRECISION=1e9)

    // Fee parameters (governable)
    baseLiquidationFee: "20000000",                   // 2% = 0.02 * 1e9 (PRECISION)
    borrowingFeeRate: "50000",                        // baseline 0.005% per 360 blocks (PRECISION)
    baseTradingFee: "3000000",                        // 0.3% = 0.003 * 1e9 (PRECISION)
    maxLeverage: "10000000000",                       // 10x (10 * PRECISION)
    liquidationThreshold: "1100000000",               // 110% = 1.10 * PRECISION

    // Fee distributions (must each sum to PRECISION=1e9)
    tradingFeeDistribution: {
        lpShare: "300000000",         // 30% to LPs
        liquidatorShare: "0",         // 0% to Liquidators
        protocolShare: "700000000"    // 70% to Protocol
    },
    borrowingFeeDistribution: {
        lpShare: "350000000",         // 35% to LPs
        liquidatorShare: "0",         // 0% to Liquidators
        protocolShare: "650000000"    // 65% to Protocol
    },
    liquidationFeeDistribution: {
        lpShare: "0",                 // 0% to LPs
        liquidatorShare: "400000000", // 40% to Liquidators
        protocolShare: "600000000"    // 60% to Protocol
    },

    // Tier thresholds (token amounts)
    tierThresholds: [
        "100000000000000000000",    // Tier 1: 100 tokens (100e18)
        "1000000000000000000000",   // Tier 2: 1,000 tokens (1000e18)
        "5000000000000000000000",   // Tier 3: 5,000 tokens (5000e18)
        "20000000000000000000000",  // Tier 4: 20,000 tokens (20000e18)
        "100000000000000000000000"  // Tier 5: 100,000 tokens (100000e18)
    ],

    // Tier fee discounts (PRECISION=1e9)
    tierFeeDiscounts: [
        "0",            // Tier 0: 0%
        "100000000",    // Tier 1: 10%
        "200000000",    // Tier 2: 20%
        "300000000",    // Tier 3: 30%
        "400000000",    // Tier 4: 40%
        "500000000"     // Tier 5: 50%
    ],

    // Tier leverage limits (scaled by PRECISION=1e9)
    tierMaxLeverages: [
        "2000000000",  // Tier 0: 2x
        "3000000000",  // Tier 1: 3x
        "4000000000",  // Tier 2: 4x
        "5000000000",  // Tier 3: 5x
        "7000000000",  // Tier 4: 7x
        "10000000000"  // Tier 5: 10x
    ],

    // Governed protocol validator hotkey (bytes32)
    protocolValidatorHotkey: "0x4492d90ca4f56368e7a06ceeaea3859d312f12280df357d790637674b928df67",

    // Function permissions (default)
    functionPermissions: [false, false, false],

    // Max liquidity providers per hotkey
    maxLiquidityProvidersPerHotkey: "5",

    // Subnet manager
    versionKey: "2",
};

export default deployConfig; 
