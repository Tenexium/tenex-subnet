import { ethers } from "hardhat";
import utils from "./utils";

async function main() {
    const networkName = process.env.NETWORK_NAME || "mainnet";
    const prKey = process.env.ETH_PRIVATE_KEY || "";
    const { provider, signer, contract: TenexiumProtocol } = await utils.getTenexiumProtocolContract(networkName, prKey);
    const TenexiumProtocolContractAddress = TenexiumProtocol.target;

    console.log("🔍 Testing TenexiumProtocol Liquidation on " + networkName);
    console.log("=" .repeat(80));

    console.log("TenexiumProtocolContractAddress:", TenexiumProtocolContractAddress);
    console.log("RPC URL:", utils.getRpcUrl(networkName));
    console.log("User:", signer.address);
    console.log("User balance:", ethers.formatEther(await provider.getBalance(signer.address)), "TAO");
    console.log("Contract Balance:", ethers.formatEther(await provider.getBalance(TenexiumProtocolContractAddress)), "TAO");

    // Parameters
    const alphaNetuid = 67;
    const maxSlippage = 100; // 1%
    const collateralAmount = ethers.parseEther("0.5");

    // Helper: sleep for N ms
    const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

    // Fetch pair data for validator hotkey
    const pair = await TenexiumProtocol.alphaPairs(alphaNetuid);
    const validatorHotkey: string = pair.validatorHotkey; // bytes32 hex string
    console.log("Validator Hotkey:", validatorHotkey);


    const STAKING_PRECOMPILE_ADDRESS = "0x0000000000000000000000000000000000000805";
    const stakingAbi = [
        "function addStake(bytes32 hotkey, uint256 amount, uint256 netuid) external payable",
        "function removeStakeFull(bytes32 hotkey, uint256 netuid) external",
    ];
    const staking = new ethers.Contract(STAKING_PRECOMPILE_ADDRESS, stakingAbi, signer);

    // 1) Manipulate price (user-specified: addStake). We will also compute health/threshold.
    console.log("\n📈 Manipulating price via IStaking.addStake (precompile)...");

    // Choose a TAO amount to stake to move price a bit
    const stakeTaoWei = ethers.parseEther("100");
    const RAO_DIVISOR = 10n ** 9n; // 1 rao = 1e9 wei
    const amountRao = stakeTaoWei / RAO_DIVISOR;
    if (amountRao === 0n) {
        throw new Error("Stake amount too small after wei->rao conversion");
    }
    try {
        const addStakeTx = await staking.addStake(validatorHotkey, amountRao, BigInt(alphaNetuid));
        console.log("addStake tx:", addStakeTx.hash);
        await addStakeTx.wait();
        console.log("✅ addStake executed");
    } catch (e) {
        console.log("❌ addStake failed:", e);
    }

    // 2) Open position (high leverage -> health closer to threshold)
    // Ensure highest leverage tier by staking under the protocol validator hotkey
    const protocolHotkey: string = await TenexiumProtocol.protocolValidatorHotkey();
    const stakeAmount = ethers.parseUnits("10", 9);
    const tier3MaxLev: bigint = await TenexiumProtocol.tier3MaxLeverage();
    console.log("\n🏗️ Ensuring leverage tier: staking to protocol validator for tier-3...");
    try {
        const stakeTx = await staking.addStake(protocolHotkey, stakeAmount, BigInt(alphaNetuid));
        console.log("tier stake tx:", stakeTx.hash);
        await stakeTx.wait();
        console.log("✅ Tier stake executed (tier-3)", tier3MaxLev.toString());
    } catch (e) {
        console.log("⚠️ Tier stake attempt failed (continuing):", e);
    }

    console.log("\n🚀 Opening position...");
    const nextPositionId: bigint = await TenexiumProtocol.nextPositionId(signer.address);
    const leverage = tier3MaxLev;
    const openTx = await TenexiumProtocol.openPosition(alphaNetuid, leverage, maxSlippage, { value: collateralAmount });
    console.log("open tx:", openTx.hash);
    await openTx.wait();
    console.log("✅ Position opened. positionId:", nextPositionId.toString());

    // 3) Remove stake using IStaking precompile after liquidation
    console.log("\n🧹 Removing stake via IStaking.removeStakeFull...");
    try {
        const removeTx = await staking.removeStakeFull(validatorHotkey, BigInt(alphaNetuid));
        console.log("removeStakeFull tx:", removeTx.hash);
        await removeTx.wait();
        console.log("✅ removeStakeFull executed");
    } catch (e) {
        console.log("⚠️ removeStakeFull failed (may be no stake to remove):", e);
    }

    // Compute health ratio and threshold before liquidation loop
    const ALPHA_PRECOMPILE_ADDRESS = "0x0000000000000000000000000000000000000808";
    const alphaAbi = [
        "function simSwapAlphaForTao(uint16 netuid, uint64 alpha) external view returns (uint256)",
    ];
    const alpha = new ethers.Contract(ALPHA_PRECOMPILE_ADDRESS, alphaAbi, provider);

    async function computeHealth(): Promise<{ ratio: bigint; threshold: bigint; valueWei: bigint; debt: bigint; }>
    {
        const p = await TenexiumProtocol.positions(signer.address, nextPositionId);
        const pairAfter = await TenexiumProtocol.alphaPairs(alphaNetuid);
        const simRao: bigint = await alpha.simSwapAlphaForTao(alphaNetuid, p.alphaAmount);
        
        // Convert rao to wei: 1 rao = 1e9 wei (WEI_PER_RAO = 1e9)
        const valueWei = simRao * 10n ** 9n + p.addedCollateral;
        
        // Calculate dynamic fees using the same logic as smart contract
        // Fee = (currentAccruedBorrowingFees - positionBorrowingFeeDebt) * positionBorrowedAmount / PRECISION
        const accruedBorrowingFees = await TenexiumProtocol.accruedBorrowingFees();
        const feeAccumulator = accruedBorrowingFees - p.borrowingFeeDebt;
        const dynamicFees = (p.borrowed * feeAccumulator) / (10n ** 9n); // PRECISION = 1e9
        
        const totalDebt = p.borrowed + dynamicFees;
        const ratio = totalDebt === 0n ? 0n : (valueWei * (10n ** 9n)) / totalDebt; // use PRECISION=1e9 scale
        return { ratio, threshold: pairAfter.liquidationThreshold, valueWei, debt: totalDebt };
    }

    const health0 = await computeHealth();
    console.log(
        `\n🧪 Health check: ratio=${health0.ratio.toString()} threshold=${health0.threshold.toString()} ` +
        `(valueWei=${ethers.formatEther(health0.valueWei)} debt=${ethers.formatEther(health0.debt)})`
    );
}

main().catch((error) => {
    console.error("❌ Error:", error);
    process.exitCode = 1;
});
