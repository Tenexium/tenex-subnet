import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

task("multisig:deploy", "Deploy MultiSigWallet")
  .addParam("owners", "Comma-separated owner addresses")
  .addOptionalParam("lock", "Lock period in blocks", 14400, types.int) // default: 2 days, 14400 blocks
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const owners: string[] = (args.owners as string).split(",").map((s) => s.trim());
    const MultiSig = await ethers.getContractFactory("MultiSigWallet");
    const lockPeriod: bigint = BigInt(args.lock ?? 0);
    const ms = await MultiSig.deploy(owners, lockPeriod);
    await ms.waitForDeployment();
    console.log(`MultiSigWallet deployed at: ${await ms.getAddress()}`);
  });

task("multisig:submit", "Submit a transaction from multisig")
  .addParam("multisig", "Address of MultiSigWallet")
  .addParam("to", "Destination address")
  .addOptionalParam("value", "ETH value (wei)", 0, types.string)
  .addParam("data", "Hex calldata")
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const ms = await ethers.getContractAt("MultiSigWallet", args.multisig);
    const tx = await ms.submitTransaction(args.to, BigInt(args.value || 0), args.data);
    console.log(`submit tx: ${tx.hash}`);
    const receipt = await tx.wait();
    const ev = receipt?.logs?.find(() => true);
    console.log("Submitted.");
  });

task("multisig:confirm", "Confirm a transaction")
  .addParam("multisig", "Address of MultiSigWallet")
  .addParam("txid", "Transaction id", undefined, types.int)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const ms = await ethers.getContractAt("MultiSigWallet", args.multisig);
    const tx = await ms.confirmTransaction(Number(args.txid));
    console.log(`confirm tx: ${tx.hash}`);
    await tx.wait();
    console.log("Confirmed.");
  });

task("multisig:revoke", "Revoke a confirmation")
  .addParam("multisig", "Address of MultiSigWallet")
  .addParam("txid", "Transaction id", undefined, types.int)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const ms = await ethers.getContractAt("MultiSigWallet", args.multisig);
    const tx = await ms.revokeConfirmation(Number(args.txid));
    console.log(`revoke tx: ${tx.hash}`);
    await tx.wait();
    console.log("Revoked.");
  });

task("multisig:execute", "Execute a confirmed transaction")
  .addParam("multisig", "Address of MultiSigWallet")
  .addParam("txid", "Transaction id", undefined, types.int)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const ms = await ethers.getContractAt("MultiSigWallet", args.multisig);
    const tx = await ms.executeTransaction(Number(args.txid));
    console.log(`execute tx: ${tx.hash}`);
    await tx.wait();
    console.log("Executed.");
  });

task("multisig:propose-add", "Propose addOwner via multisig self-call")
  .addParam("multisig", "Address of MultiSigWallet")
  .addParam("owner", "New owner address")
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const ms = await ethers.getContractAt("MultiSigWallet", args.multisig);
    const iface = new ethers.Interface(["function addOwner(address)"]);
    const data = iface.encodeFunctionData("addOwner", [args.owner]);
    const tx = await ms.submitTransaction(args.multisig, 0n, data);
    console.log(`submit addOwner tx: ${tx.hash}`);
    await tx.wait();
    console.log("Submitted addOwner proposal.");
  });

task("multisig:propose-remove", "Propose removeOwner via multisig self-call")
  .addParam("multisig", "Address of MultiSigWallet")
  .addParam("owner", "Owner address to remove")
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const ms = await ethers.getContractAt("MultiSigWallet", args.multisig);
    const iface = new ethers.Interface(["function removeOwner(address)"]);
    const data = iface.encodeFunctionData("removeOwner", [args.owner]);
    const tx = await ms.submitTransaction(args.multisig, 0n, data);
    console.log(`submit removeOwner tx: ${tx.hash}`);
    await tx.wait();
    console.log("Submitted removeOwner proposal.");
  });

task("multisig:propose-lock", "Propose setLockPeriod via multisig self-call")
  .addParam("multisig", "Address of MultiSigWallet")
  .addParam("blocks", "New lock period in blocks", 14400, types.int) // default: 2 days, 14400 blocks
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const ms = await ethers.getContractAt("MultiSigWallet", args.multisig);
    const iface = new ethers.Interface(["function setLockPeriod(uint256)"]);
    const data = iface.encodeFunctionData("setLockPeriod", [BigInt(args.blocks)]);
    const tx = await ms.submitTransaction(args.multisig, 0n, data);
    console.log(`submit setLockPeriod tx: ${tx.hash}`);
    await tx.wait();
    console.log("Submitted setLockPeriod proposal.");
  });
