import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

task("multisig:deploy", "Deploy MultiSigWallet")
  .addParam("owners", "Comma-separated owner addresses")
  .addParam("required", "Confirmations required", undefined, types.int)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const owners: string[] = (args.owners as string).split(",").map((s) => s.trim());
    const required: number = Number(args.required);
    const MultiSig = await ethers.getContractFactory("MultiSigWallet");
    const ms = await MultiSig.deploy(owners, required);
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
