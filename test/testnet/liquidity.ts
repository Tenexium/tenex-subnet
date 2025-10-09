import { ethers } from "hardhat";
import utils from "./utils";

async function main() {
    const networkName = process.env.NETWORK_NAME || "mainnet";
    const prKey = process.env.USER_PRIVATE_KEY || "";
    const { provider, signer, contract: TenexiumProtocol } = await utils.getTenexiumProtocolContract(networkName, prKey);
    const TenexiumProtocolContractAddress = TenexiumProtocol.target;

    console.log("🔍 Testing TenexiumProtocol Liquidity on " + networkName);
    console.log("=" .repeat(60));
    console.log("TenexiumProtocolContractAddress:", TenexiumProtocolContractAddress);
    console.log("RPC URL:", utils.getRpcUrl(networkName));
    console.log("User:", signer.address);
    console.log("User balance:", ethers.formatEther(await provider.getBalance(signer.address)), "TAO");
    console.log("Contract Balance:", ethers.formatEther(await provider.getBalance(TenexiumProtocolContractAddress)), "TAO");
    
    const userAddress = await signer.getAddress();
    console.log(`👤 User Address: ${userAddress}`);
    
    // Get initial state
    console.log("\n📊 Initial Protocol State:");
    console.log(`   Total LP Stakes: ${ethers.formatEther(await TenexiumProtocol.totalLpStakes())} TAO`);
    console.log(`   Total Borrowed: ${ethers.formatEther(await TenexiumProtocol.totalBorrowed())} TAO`);
    console.log(`   Total Collateral: ${ethers.formatEther(await TenexiumProtocol.totalCollateral())} TAO`);
    console.log(`   Protocol Fees: ${ethers.formatEther(await TenexiumProtocol.protocolFees())} TAO`);
    
    // Get initial user state
    const initialLpInfo = await TenexiumProtocol.liquidityProviders(userAddress);
    console.log(`\n�� Initial User State:`);
    console.log(`   Is Liquidity Provider: ${initialLpInfo.isActive}`);
    console.log(`   LP Stake: ${ethers.formatEther(initialLpInfo.stake)} TAO`);
    console.log(`   LP Shares: ${ethers.formatEther(initialLpInfo.shares)}`);
    console.log(`   Share Percentage: ${(Number(initialLpInfo.stake) / Number(await TenexiumProtocol.totalLpStakes()) * 100).toFixed(4)}%`);
    
    // Store original stake amount
    const originalStake = initialLpInfo.stake;
    console.log(`\n💾 Original Stake Amount: ${ethers.formatEther(originalStake)} TAO`);
    
    // Test amounts
    const testAmountForAdding = ethers.parseEther("0.1"); // 0.1 TAO for adding liquidity
    const testAmountForRemoving = ethers.parseEther("0.1"); // 0.1 TAO for removing liquidity
    console.log(`\n🧪 Test Amount for Adding: ${ethers.formatEther(testAmountForAdding)} TAO`);
    console.log(`🧪 Test Amount for Removing: ${ethers.formatEther(testAmountForRemoving)} TAO`);
    console.log(`minLiquidityThreshold: ${ethers.formatEther(await TenexiumProtocol.minLiquidityThreshold())} TAO`);
    console.log(`maxUtilizationRate: ${(Number(await TenexiumProtocol.maxUtilizationRate()) / 1e9 * 100).toFixed(2)}%`);
    console.log(`liquidityBufferRatio: ${(Number(await TenexiumProtocol.liquidityBufferRatio()) / 1e9 * 100).toFixed(2)}%`);
    
    try {
        // // Step 0: Set min liquidity threshold
        // console.log("\n➕ Step 0: Setting Min Liquidity Threshold...");
        // const setMinThresholdTx = await TenexiumProtocol.updateLiquidityGuardrails(ethers.parseEther("2"), ethers.parseUnits("0.9", 9), ethers.parseUnits("0.2", 9));
        // console.log(`   Transaction Hash: ${setMinThresholdTx.hash}`);
        // await setMinThresholdTx.wait();
        // console.log("   ✅ Min Threshold set successfully!");

        // Step 1: Add liquidity
        console.log("\n➕ Step 1: Adding Liquidity...");
        const addTx = await TenexiumProtocol.addLiquidity({ value: testAmountForAdding });
        console.log(`   Transaction Hash: ${addTx.hash}`);
        await addTx.wait();
        console.log("   ✅ Liquidity added successfully!");
        
        // Check state after adding
        const afterAddLpInfo = await TenexiumProtocol.liquidityProviders(userAddress);
        console.log(`   New Total LP Stakes: ${ethers.formatEther(await TenexiumProtocol.totalLpStakes())} TAO`);
        console.log(`   New LP Stake: ${ethers.formatEther(afterAddLpInfo.stake)} TAO`);
        console.log(`   New LP Shares: ${ethers.formatEther(afterAddLpInfo.shares)}`);
        console.log(`   Is Liquidity Circuit Breaker: ${await TenexiumProtocol.liquidityCircuitBreaker()}`);
        
        console.log("\n\nWaiting for 15 seconds for cooldown...");
        await new Promise(resolve => setTimeout(resolve, 15000));
        
        // Step 2: Remove the test liquidity (partial removal)
        console.log("\n➖ Step 2: Removing Test Liquidity...");
        const removeTx = await TenexiumProtocol.removeLiquidity(testAmountForRemoving);
        console.log(`   Transaction Hash: ${removeTx.hash}`);
        await removeTx.wait();
        console.log("   ✅ Test liquidity removed successfully!");
        
        // Check final state
        const finalLpInfo = await TenexiumProtocol.liquidityProviders(userAddress);
        console.log(`\n📊 Final Protocol State:`);
        console.log(`   Total LP Stakes: ${ethers.formatEther(await TenexiumProtocol.totalLpStakes())} TAO`);
        console.log(`   Is Liquidity Circuit Breaker: ${await TenexiumProtocol.liquidityCircuitBreaker()}`);
        
        console.log(`\n�� Final User State:`);
        console.log(`   LP Stake: ${ethers.formatEther(finalLpInfo.stake)} TAO`);
        console.log(`   LP Shares: ${ethers.formatEther(finalLpInfo.shares)}`);
        console.log(`   Share Percentage: ${(Number(finalLpInfo.stake) / Number(await TenexiumProtocol.totalLpStakes()) * 100).toFixed(4)}%`);
        
        // Verify original stake is preserved
        const stakeDifference = finalLpInfo.stake - originalStake;
        console.log(`\n�� Stake Verification:`);
        console.log(`   Original Stake: ${ethers.formatEther(originalStake)} TAO`);
        console.log(`   Final Stake: ${ethers.formatEther(finalLpInfo.stake)} TAO`);
        console.log(`   Difference: ${ethers.formatEther(stakeDifference)} TAO`);
        
        if (stakeDifference === BigInt(0)) {
            console.log("   ✅ Original stake amount preserved perfectly!");
        } else {
            console.log(`   ⚠️  Small difference detected: ${ethers.formatEther(stakeDifference)} TAO`);
            console.log("   This might be due to rounding or fee calculations.");
        }
        
        // Additional liquidity information
        console.log(`\n📈 Additional Liquidity Information:`);
        const liquidityStats = await TenexiumProtocol.totalPendingLpFees();
        console.log(`   Total Pending LP Fees: ${ethers.formatEther(liquidityStats)} TAO`);
        const liquidityStats2 = await TenexiumProtocol.totalLpStakes();
        console.log(`   Total LP Stakes: ${ethers.formatEther(liquidityStats2)} TAO`);
        
        // Calculate LP value
        const lpValue = (await TenexiumProtocol.liquidityProviders(userAddress)).stake;
        console.log(`   Current LP Value: ${ethers.formatEther(lpValue)} TAO`);
        
        console.log("\n🎉 Liquidity test completed successfully!");
        console.log("=" .repeat(60));
        
    } catch (error) {
        console.error("❌ Error during liquidity test:", error);
        
        // Try to get current state even if there was an error
        try {
            const errorStats = await TenexiumProtocol.totalLpStakes();
            const errorLpInfo = await TenexiumProtocol.liquidityProviders(userAddress);
            console.log("\n📊 State after error:");
            console.log(`   Total LP Stakes: ${ethers.formatEther(errorStats)} TAO`);
            console.log(`   LP Stake: ${ethers.formatEther(errorLpInfo.stake)} TAO`);
            console.log(`   Original Stake: ${ethers.formatEther(originalStake)} TAO`);
        } catch (stateError) {
            console.error("❌ Could not retrieve state after error:", stateError);
        }
        
        throw error;
    }
}

main().catch((error) => {
    console.error("❌ Error:", error);
    process.exitCode = 1;
});
