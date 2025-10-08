import { ethers } from "hardhat";
import utils from "./utils";

async function main() {
    const networkName = process.env.NETWORK_NAME || "mainnet";
    const prKey = process.env.ETH_PRIVATE_KEY || "";
    const { provider, signer, contract: TenexiumProtocol } = await utils.getTenexiumProtocolContract(networkName, prKey);
    const TenexiumProtocolContractAddress = TenexiumProtocol.target;
    
    console.log("🔍 Testing TenexiumProtocol Getters on " + networkName);
    console.log("=" .repeat(60));
    console.log("TenexiumProtocolContractAddress:", TenexiumProtocolContractAddress);
    console.log("RPC URL:", utils.getRpcUrl(networkName));
    console.log("Signer:", signer.address);
    console.log("Contract Balance:", ethers.formatEther(await provider.getBalance(TenexiumProtocolContractAddress)), "TAO");
    
    try {
        // ==================== CONSTANTS ====================
        console.log("\n📋 CONSTANTS:");
        console.log("-".repeat(40));
        
        const precision = await TenexiumProtocol.PRECISION();
        const tenexNetuid = await TenexiumProtocol.TENEX_NETUID();
        const version = await TenexiumProtocol.VERSION();
        const maxLiquidityProvidersPerHotkey = await TenexiumProtocol.maxLiquidityProvidersPerHotkey();

        console.log("PRECISION:", precision.toString());
        console.log("TENEX_NETUID:", tenexNetuid.toString());
        console.log("VERSION:", version.toString());
        console.log("MAX_LIQUIDITY_PROVIDERS_PER_HOTKEY:", maxLiquidityProvidersPerHotkey.toString());
        
        // Precompile addresses
        const metagraphPrecompile = await TenexiumProtocol.METAGRAPH_PRECOMPILE();
        const neuronPrecompile = await TenexiumProtocol.NEURON_PRECOMPILE();
        const stakingPrecompile = await TenexiumProtocol.STAKING_PRECOMPILE();
        const alphaPrecompile = await TenexiumProtocol.ALPHA_PRECOMPILE();
        
        console.log("METAGRAPH_PRECOMPILE:", metagraphPrecompile);
        console.log("NEURON_PRECOMPILE:", neuronPrecompile);
        console.log("STAKING_PRECOMPILE:", stakingPrecompile);
        console.log("ALPHA_PRECOMPILE:", alphaPrecompile);

        // ==================== CORE PROTOCOL PARAMETERS ====================
        console.log("\n⚙️  CORE PROTOCOL PARAMETERS:");
        console.log("-".repeat(40));
        
        const maxLeverage = await TenexiumProtocol.maxLeverage();
        const liquidationThreshold = await TenexiumProtocol.liquidationThreshold();
        const minLiquidityThreshold = await TenexiumProtocol.minLiquidityThreshold();
        const maxUtilizationRate = await TenexiumProtocol.maxUtilizationRate();
        const liquidityBufferRatio = await TenexiumProtocol.liquidityBufferRatio();
        
        console.log("Max Leverage:", ethers.formatUnits(maxLeverage, 9), "x");
        console.log("Liquidation Threshold:", ethers.formatUnits(liquidationThreshold, 9), "x");
        console.log("Min Liquidity Threshold:", ethers.formatEther(minLiquidityThreshold), "TAO");
        console.log("Max Utilization Rate:", ethers.formatUnits(maxUtilizationRate, 9), "x");
        console.log("Liquidity Buffer Ratio:", ethers.formatUnits(liquidityBufferRatio, 9), "x");

        // ==================== ACTION COOLDOWN PARAMETERS ====================
        console.log("\n⏱️  ACTION COOLDOWN PARAMETERS:");
        console.log("-".repeat(40));
        
        const userActionCooldownBlocks = await TenexiumProtocol.userActionCooldownBlocks();
        const lpActionCooldownBlocks = await TenexiumProtocol.lpActionCooldownBlocks();
        
        console.log("User Action Cooldown Blocks:", userActionCooldownBlocks.toString());
        console.log("LP Action Cooldown Blocks:", lpActionCooldownBlocks.toString());

        // ==================== BUYBACK PARAMETERS ====================
        console.log("\n💰 BUYBACK PARAMETERS:");
        console.log("-".repeat(40));
        
        const buybackRate = await TenexiumProtocol.buybackRate();
        const buybackIntervalBlocks = await TenexiumProtocol.buybackIntervalBlocks();
        const buybackExecutionThreshold = await TenexiumProtocol.buybackExecutionThreshold();
        
        console.log("Buyback Rate:", ethers.formatUnits(buybackRate, 9), "x");
        console.log("Buyback Interval Blocks:", buybackIntervalBlocks.toString());
        console.log("Buyback Execution Threshold:", ethers.formatEther(buybackExecutionThreshold), "TAO");

        // ==================== FEE PARAMETERS ====================
        console.log("\n💸 FEE PARAMETERS:");
        console.log("-".repeat(40));
        
        const tradingFeeRate = await TenexiumProtocol.tradingFeeRate();
        const borrowingFeeRate = await TenexiumProtocol.borrowingFeeRate();
        const liquidationFeeRate = await TenexiumProtocol.liquidationFeeRate();
        
        console.log("Trading Fee Rate:", ethers.formatUnits(tradingFeeRate, 9), "x");
        console.log("Borrowing Fee Rate:", ethers.formatUnits(borrowingFeeRate, 9), "x");
        console.log("Liquidation Fee Rate:", ethers.formatUnits(liquidationFeeRate, 9), "x");

        // ==================== FEE DISTRIBUTION PARAMETERS ====================
        console.log("\n📊 FEE DISTRIBUTION PARAMETERS:");
        console.log("-".repeat(40));
        
        // Trading fee distribution
        const tradingFeeLpShare = await TenexiumProtocol.tradingFeeLpShare();
        const tradingFeeLiquidatorShare = await TenexiumProtocol.tradingFeeLiquidatorShare();
        const tradingFeeProtocolShare = await TenexiumProtocol.tradingFeeProtocolShare();
        
        console.log("Trading Fee - LP Share:", ethers.formatUnits(tradingFeeLpShare, 9), "x");
        console.log("Trading Fee - Liquidator Share:", ethers.formatUnits(tradingFeeLiquidatorShare, 9), "x");
        console.log("Trading Fee - Protocol Share:", ethers.formatUnits(tradingFeeProtocolShare, 9), "x");
        
        // Borrowing fee distribution
        const borrowingFeeLpShare = await TenexiumProtocol.borrowingFeeLpShare();
        const borrowingFeeLiquidatorShare = await TenexiumProtocol.borrowingFeeLiquidatorShare();
        const borrowingFeeProtocolShare = await TenexiumProtocol.borrowingFeeProtocolShare();
        
        console.log("Borrowing Fee - LP Share:", ethers.formatUnits(borrowingFeeLpShare, 9), "x");
        console.log("Borrowing Fee - Liquidator Share:", ethers.formatUnits(borrowingFeeLiquidatorShare, 9), "x");
        console.log("Borrowing Fee - Protocol Share:", ethers.formatUnits(borrowingFeeProtocolShare, 9), "x");
        
        // Liquidation fee distribution
        const liquidationFeeLpShare = await TenexiumProtocol.liquidationFeeLpShare();
        const liquidationFeeLiquidatorShare = await TenexiumProtocol.liquidationFeeLiquidatorShare();
        const liquidationFeeProtocolShare = await TenexiumProtocol.liquidationFeeProtocolShare();
        
        console.log("Liquidation Fee - LP Share:", ethers.formatUnits(liquidationFeeLpShare, 9), "x");
        console.log("Liquidation Fee - Liquidator Share:", ethers.formatUnits(liquidationFeeLiquidatorShare, 9), "x");
        console.log("Liquidation Fee - Protocol Share:", ethers.formatUnits(liquidationFeeProtocolShare, 9), "x");

        // ==================== TIER THRESHOLDS ====================
        console.log("\n🏆 TIER THRESHOLDS:");
        console.log("-".repeat(40));
        
        const tier1Threshold = await TenexiumProtocol.tier1Threshold();
        const tier2Threshold = await TenexiumProtocol.tier2Threshold();
        const tier3Threshold = await TenexiumProtocol.tier3Threshold();
        const tier4Threshold = await TenexiumProtocol.tier4Threshold();
        const tier5Threshold = await TenexiumProtocol.tier5Threshold();
        
        console.log("Tier 1 Threshold:", ethers.formatEther(tier1Threshold), "TAO");
        console.log("Tier 2 Threshold:", ethers.formatEther(tier2Threshold), "TAO");
        console.log("Tier 3 Threshold:", ethers.formatEther(tier3Threshold), "TAO");
        console.log("Tier 4 Threshold:", ethers.formatEther(tier4Threshold), "TAO");
        console.log("Tier 5 Threshold:", ethers.formatEther(tier5Threshold), "TAO");

        // ==================== TIER FEE DISCOUNTS ====================
        console.log("\n🎯 TIER FEE DISCOUNTS:");
        console.log("-".repeat(40));
        
        const tier0FeeDiscount = await TenexiumProtocol.tier0FeeDiscount();
        const tier1FeeDiscount = await TenexiumProtocol.tier1FeeDiscount();
        const tier2FeeDiscount = await TenexiumProtocol.tier2FeeDiscount();
        const tier3FeeDiscount = await TenexiumProtocol.tier3FeeDiscount();
        const tier4FeeDiscount = await TenexiumProtocol.tier4FeeDiscount();
        const tier5FeeDiscount = await TenexiumProtocol.tier5FeeDiscount();
        
        console.log("Tier 0 Fee Discount:", ethers.formatUnits(tier0FeeDiscount, 9), "x");
        console.log("Tier 1 Fee Discount:", ethers.formatUnits(tier1FeeDiscount, 9), "x");
        console.log("Tier 2 Fee Discount:", ethers.formatUnits(tier2FeeDiscount, 9), "x");
        console.log("Tier 3 Fee Discount:", ethers.formatUnits(tier3FeeDiscount, 9), "x");
        console.log("Tier 4 Fee Discount:", ethers.formatUnits(tier4FeeDiscount, 9), "x");
        console.log("Tier 5 Fee Discount:", ethers.formatUnits(tier5FeeDiscount, 9), "x");

        // ==================== TIER MAX LEVERAGES ====================
        console.log("\n🚀 TIER MAX LEVERAGES:");
        console.log("-".repeat(40));
        
        const tier0MaxLeverage = await TenexiumProtocol.tier0MaxLeverage();
        const tier1MaxLeverage = await TenexiumProtocol.tier1MaxLeverage();
        const tier2MaxLeverage = await TenexiumProtocol.tier2MaxLeverage();
        const tier3MaxLeverage = await TenexiumProtocol.tier3MaxLeverage();
        const tier4MaxLeverage = await TenexiumProtocol.tier4MaxLeverage();
        const tier5MaxLeverage = await TenexiumProtocol.tier5MaxLeverage();
        
        console.log("Tier 0 Max Leverage:", ethers.formatUnits(tier0MaxLeverage, 9), "x");
        console.log("Tier 1 Max Leverage:", ethers.formatUnits(tier1MaxLeverage, 9), "x");
        console.log("Tier 2 Max Leverage:", ethers.formatUnits(tier2MaxLeverage, 9), "x");
        console.log("Tier 3 Max Leverage:", ethers.formatUnits(tier3MaxLeverage, 9), "x");
        console.log("Tier 4 Max Leverage:", ethers.formatUnits(tier4MaxLeverage, 9), "x");
        console.log("Tier 5 Max Leverage:", ethers.formatUnits(tier5MaxLeverage, 9), "x");

        // ==================== PROTOCOL CONFIGURATION ====================
        console.log("\n🔧 PROTOCOL CONFIGURATION:");
        console.log("-".repeat(40));
        
        const protocolValidatorHotkey = await TenexiumProtocol.protocolValidatorHotkey();
        const protocolSs58Address = await TenexiumProtocol.protocolSs58Address();
        const treasury = await TenexiumProtocol.treasury();
        const owner = await TenexiumProtocol.owner();
        
        console.log("Protocol Validator Hotkey:", protocolValidatorHotkey);
        console.log("Protocol SS58 Address:", protocolSs58Address);
        console.log("Treasury:", treasury);
        console.log("Owner:", owner);

        // ==================== EMERGENCY STATE ====================
        console.log("\n🚨 EMERGENCY STATE:");
        console.log("-".repeat(40));
        
        const liquidityCircuitBreaker = await TenexiumProtocol.liquidityCircuitBreaker();
        const paused = await TenexiumProtocol.paused();
        
        console.log("Liquidity Circuit Breaker:", liquidityCircuitBreaker);
        console.log("Paused:", paused);

        // ==================== FUNCTION PERMISSIONS ====================
        console.log("\n🔒 FUNCTION PERMISSIONS:");
        console.log("-".repeat(40));
        
        const openPositionPermission = await TenexiumProtocol.functionPermissions(0);
        const closePositionPermission = await TenexiumProtocol.functionPermissions(1);
        const addCollateralPermission = await TenexiumProtocol.functionPermissions(2);
        console.log("Open Position Permission:", openPositionPermission);
        console.log("Close Position Permission:", closePositionPermission);
        console.log("Add Collateral Permission:", addCollateralPermission);

        // ==================== PROTOCOL STATE ====================
        console.log("\n📈 PROTOCOL STATE:");
        console.log("-".repeat(40));
        
        const totalCollateral = await TenexiumProtocol.totalCollateral();
        const totalBorrowed = await TenexiumProtocol.totalBorrowed();
        const totalVolume = await TenexiumProtocol.totalVolume();
        const totalTrades = await TenexiumProtocol.totalTrades();
        const protocolFees = await TenexiumProtocol.protocolFees();
        
        console.log("Total Collateral:", ethers.formatEther(totalCollateral), "TAO");
        console.log("Total Borrowed:", ethers.formatEther(totalBorrowed), "TAO");
        console.log("Total Volume:", ethers.formatEther(totalVolume), "TAO");
        console.log("Total Trades:", totalTrades.toString());
        console.log("Protocol Fees:", ethers.formatEther(protocolFees), "TAO");

        // ==================== BUYBACK STATE ====================
        console.log("\n🔄 BUYBACK STATE:");
        console.log("-".repeat(40));
        
        const buybackPool = await TenexiumProtocol.buybackPool();
        const lastBuybackBlock = await TenexiumProtocol.lastBuybackBlock();
        const totalTaoUsedForBuybacks = await TenexiumProtocol.totalTaoUsedForBuybacks();
        const totalAlphaBought = await TenexiumProtocol.totalAlphaBought();
        
        console.log("Buyback Pool:", ethers.formatEther(buybackPool), "TAO");
        console.log("Last Buyback Block:", lastBuybackBlock.toString());
        console.log("Total TAO Used for Buybacks:", ethers.formatEther(totalTaoUsedForBuybacks), "TAO");
        console.log("Total Alpha Bought:", ethers.formatEther(totalAlphaBought), "Alpha");

        // ==================== FEE TRACKING STATE ====================
        console.log("\n📊 FEE TRACKING STATE:");
        console.log("-".repeat(40));
        
        const totalTradingFees = await TenexiumProtocol.totalTradingFees();
        const totalBorrowingFees = await TenexiumProtocol.totalBorrowingFees();
        const totalLiquidationFees = await TenexiumProtocol.totalLiquidationFees();
        const lastAccruedBorrowingFeesUpdate = await TenexiumProtocol.lastAccruedBorrowingFeesUpdate();
        
        console.log("Total Trading Fees:", ethers.formatEther(totalTradingFees), "TAO");
        console.log("Total Borrowing Fees:", ethers.formatEther(totalBorrowingFees), "TAO");
        console.log("Total Liquidation Fees:", ethers.formatEther(totalLiquidationFees), "TAO");
        console.log("Last Fee Distribution Block:", lastAccruedBorrowingFeesUpdate.toString());

        // ==================== LP AND LIQUIDATOR STATE ====================
        console.log("\n👥 LP AND LIQUIDATOR STATE:");
        console.log("-".repeat(40));
        
        const totalPendingLpFees = await TenexiumProtocol.totalPendingLpFees();
        const totalLpStakes = await TenexiumProtocol.totalLpStakes();
        const totalLiquidations = await TenexiumProtocol.totalLiquidations();
        const totalLiquidationValue = await TenexiumProtocol.totalLiquidationValue();
        const accLpFeesPerShare = await TenexiumProtocol.accLpFeesPerShare();
        const accruedBorrowingFees = await TenexiumProtocol.accruedBorrowingFees();
        
        console.log("Total Pending LP Fees:", ethers.formatEther(totalPendingLpFees), "TAO");
        console.log("Total LP Stakes:", ethers.formatEther(totalLpStakes), "TAO");
        console.log("Total Liquidations:", totalLiquidations.toString());
        console.log("Total Liquidation Value:", ethers.formatEther(totalLiquidationValue), "TAO");
        console.log("Acc LP Fees Per Share:", accLpFeesPerShare.toString());
        console.log("Accrued Borrowing Fees:", ethers.formatEther(accruedBorrowingFees), "TAO");

        // ==================== COMPLEX GETTER FUNCTIONS ====================
        console.log("\n🔍 COMPLEX GETTER FUNCTIONS:");
        console.log("-".repeat(40));
        
        // Get protocol stats
        console.log("Protocol Stats:");
        console.log("  - Total Collateral Amount:", ethers.formatEther(await TenexiumProtocol.totalCollateral()), "TAO");
        console.log("  - Total Borrowed Amount:", ethers.formatEther(await TenexiumProtocol.totalBorrowed()), "TAO");
        console.log("  - Total Volume Amount:", ethers.formatEther(await TenexiumProtocol.totalVolume()), "TAO");
        console.log("  - Total Trades Count:", (await TenexiumProtocol.totalTrades()).toString());
        console.log("  - Protocol Fees Amount:", ethers.formatEther(await TenexiumProtocol.protocolFees()), "TAO");
        console.log("  - Total LP Stakes Amount:", ethers.formatEther(await TenexiumProtocol.totalLpStakes()), "TAO");

        // Get user stats for the signer
        console.log("User Stats for", signer.address, ":");
        console.log("  - Total Collateral User:", ethers.formatEther(await TenexiumProtocol.userCollateral(signer.address)), "TAO");
        console.log("  - Total Borrowed User:", ethers.formatEther(await TenexiumProtocol.userTotalBorrowed(signer.address)), "TAO");
        console.log("  - Total Volume User:", ethers.formatEther(await TenexiumProtocol.userTotalVolume(signer.address)), "TAO");
        console.log("  - Is Liquidity Provider:", (await TenexiumProtocol.liquidityProviders(signer.address)).isActive);
        console.log("  - LP Stake:", ethers.formatEther((await TenexiumProtocol.liquidityProviders(signer.address)).stake), "TAO");
        console.log("  - LP Shares:", ethers.formatEther((await TenexiumProtocol.liquidityProviders(signer.address)).shares), "x");

        // Get user position (should be empty for new user)
        const userPosition = await TenexiumProtocol.positions(signer.address, tenexNetuid);
        console.log("User Position for netuid " + tenexNetuid.toString() + ":");
        console.log("  - Collateral:", ethers.formatEther(userPosition.collateral), "TAO");
        console.log("  - Borrowed:", ethers.formatEther(userPosition.borrowed), "TAO");
        console.log("  - Alpha Amount:", ethers.formatEther(userPosition.alphaAmount), "Alpha");
        console.log("  - Leverage:", ethers.formatUnits(userPosition.leverage, 9), "x");
        console.log("  - Entry Price:", ethers.formatEther(userPosition.entryPrice), "TAO");
        console.log("  - Last Update Block:", userPosition.lastUpdateBlock.toString());
        console.log("  - Accrued Fees:", ethers.formatEther(userPosition.accruedFees), "TAO");
        console.log("  - Is Active:", userPosition.isActive);
        console.log("  - Validator Hotkey:", userPosition.validatorHotkey);

        // ==================== VALIDATION CHECKS ====================
        console.log("\n✅ VALIDATION CHECKS:");
        console.log("-".repeat(40));
        
        // Check fee distributions sum to PRECISION
        const tradingFeeSum = tradingFeeLpShare + tradingFeeLiquidatorShare + tradingFeeProtocolShare;
        const borrowingFeeSum = borrowingFeeLpShare + borrowingFeeLiquidatorShare + borrowingFeeProtocolShare;
        const liquidationFeeSum = liquidationFeeLpShare + liquidationFeeLiquidatorShare + liquidationFeeProtocolShare;
        
        console.log("Trading Fee Distribution Sum:", ethers.formatUnits(tradingFeeSum, 9), "(should equal PRECISION)");
        console.log("Borrowing Fee Distribution Sum:", ethers.formatUnits(borrowingFeeSum, 9), "(should equal PRECISION)");
        console.log("Liquidation Fee Distribution Sum:", ethers.formatUnits(liquidationFeeSum, 9), "(should equal PRECISION)");
        
        // Check tier thresholds are in ascending order
        const tierThresholds = [tier1Threshold, tier2Threshold, tier3Threshold, tier4Threshold, tier5Threshold];
        let tierOrderValid = true;
        for (let i = 1; i < tierThresholds.length; i++) {
            if (tierThresholds[i] <= tierThresholds[i-1]) {
                tierOrderValid = false;
                break;
            }
        }
        console.log("Tier Thresholds in Ascending Order:", tierOrderValid);
        
        // Check tier max leverages are in ascending order
        const tierMaxLeverages = [tier0MaxLeverage, tier1MaxLeverage, tier2MaxLeverage, tier3MaxLeverage, tier4MaxLeverage, tier5MaxLeverage];
        let leverageOrderValid = true;
        for (let i = 1; i < tierMaxLeverages.length; i++) {
            if (tierMaxLeverages[i] <= tierMaxLeverages[i-1]) {
                leverageOrderValid = false;
                break;
            }
        }
        console.log("Tier Max Leverages in Ascending Order:", leverageOrderValid);
        
        console.log("\n🎉 All getter tests completed successfully!");
        
    } catch (error) {
        console.error("❌ Error testing getters:", error);
        throw error;
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
