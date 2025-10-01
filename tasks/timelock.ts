import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { keccak256, toUtf8Bytes, Interface } from "ethers";

function toBytes32Salt(input: string): string {
  // ethers v6 keccak256 of string
  return keccak256(toUtf8Bytes(input));
}

task("timelock:deploy", "Deploy TimelockController (multisig-controlled)")
  .addParam("safe", "Gnosis Safe (multisig) address controlling the timelock")
  .addOptionalParam("delay", "Minimum delay in seconds", 172800, types.int)
  .addFlag("includedeployer", "Also grant proposer/executor/canceller to the current deployer (bootstrap)")
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const delay: number = Number(args.delay);
    const safe: string = args.safe;
    const includeDeployer: boolean = Boolean(args.includedeployer);

    const [deployer] = await ethers.getSigners();
    console.log(`Deployer: ${deployer.address}`);

    const proposers: string[] = [safe];
    const executors: string[] = [safe];
    if (includeDeployer) {
      proposers.push(deployer.address);
      executors.push(deployer.address);
    }

    const Timelock = await ethers.getContractFactory("TenexiumTimelock");
    const timelock = await Timelock.deploy(delay, proposers, executors, safe);
    await timelock.waitForDeployment();
    const timelockAddr = await timelock.getAddress();

    console.log(`Timelock deployed at: ${timelockAddr}`);
    console.log(`MinDelay: ${await timelock.getMinDelay()}`);
    console.log(`Admin: SAFE (${safe}) with DEFAULT_ADMIN_ROLE`);
    if (includeDeployer) {
      console.log("Bootstrap enabled: deployer has proposer/executor/canceller roles");
    }
  });

task("timelock:transfer-ownership", "Transfer proxy ownership to timelock")
  .addParam("proxy", "UUPS proxy address of TenexiumProtocol")
  .addParam("timelock", "TimelockController address")
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const proxy = args.proxy;
    const timelock = args.timelock;

    const protocol = await ethers.getContractAt("TenexiumProtocol", proxy);
    const currentOwner = await protocol.owner();
    console.log(`Current owner: ${currentOwner}`);

    const tx = await protocol.transferOwnership(timelock);
    console.log(`transferOwnership tx: ${tx.hash}`);
    await tx.wait();
    console.log(`New owner: ${await protocol.owner()}`);
  });

task("timelock:encode-upgrade", "Encode UUPS upgrade calldata for timelock.schedule/execute")
  .addParam("newimpl", "New implementation address")
  .addOptionalParam("initdata", "Hex-encoded initializer data for upgradeToAndCall", "0x", types.string)
  .setAction(async (args) => {
    const iface = new Interface([
      "function upgradeTo(address newImplementation)",
      "function upgradeToAndCall(address newImplementation, bytes data)"
    ]);
    const newImpl: string = args.newimpl;
    const initData: string = args.initdata || "0x";
    if (initData === "0x" || initData === "0x0") {
      const data = iface.encodeFunctionData("upgradeTo", [newImpl]);
      console.log(`method: upgradeTo`);
      console.log(`data: ${data}`);
    } else {
      const data = iface.encodeFunctionData("upgradeToAndCall", [newImpl, initData]);
      console.log(`method: upgradeToAndCall`);
      console.log(`data: ${data}`);
    }
  });

task("timelock:schedule", "Schedule a timelock operation")
  .addParam("timelock", "TimelockController address")
  .addParam("target", "Target contract address")
  .addOptionalParam("value", "ETH value (wei)", 0, types.string)
  .addParam("data", "Hex-encoded calldata")
  .addOptionalParam("salt", "Arbitrary salt string", "", types.string)
  .addOptionalParam("delay", "Delay override in seconds (>= minDelay)", undefined, types.int)
  .addOptionalParam("predecessor", "Predecessor op id (bytes32)", "0x0000000000000000000000000000000000000000000000000000000000000000", types.string)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const tl = await ethers.getContractAt("TenexiumTimelock", args.timelock);
    const saltBytes32 = args.salt && args.salt !== "" ? toBytes32Salt(args.salt) : "0x0000000000000000000000000000000000000000000000000000000000000000";
    const value = BigInt(args.value || 0);
    const minDelay = await tl.getMinDelay();
    const delay = args.delay != null ? Number(args.delay) : Number(minDelay);
    console.log(`Using delay: ${delay}s (minDelay=${minDelay})`);

    const tx = await tl.schedule(args.target, value, args.data, args.predecessor, saltBytes32, delay);
    console.log(`schedule tx: ${tx.hash}`);
    const opId = await tl.hashOperation(args.target, value, args.data, args.predecessor, saltBytes32);
    console.log(`operation id: ${opId}`);
  });

task("timelock:execute", "Execute a scheduled timelock operation")
  .addParam("timelock", "TimelockController address")
  .addParam("target", "Target contract address")
  .addOptionalParam("value", "ETH value (wei)", 0, types.string)
  .addParam("data", "Hex-encoded calldata")
  .addOptionalParam("salt", "Arbitrary salt string used when scheduling", "", types.string)
  .addOptionalParam("predecessor", "Predecessor op id (bytes32)", "0x0000000000000000000000000000000000000000000000000000000000000000", types.string)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const tl = await ethers.getContractAt("TenexiumTimelock", args.timelock);
    const saltBytes32 = args.salt && args.salt !== "" ? toBytes32Salt(args.salt) : "0x0000000000000000000000000000000000000000000000000000000000000000";
    const value = BigInt(args.value || 0);
    const opId = await tl.hashOperation(args.target, value, args.data, args.predecessor, saltBytes32);
    console.log(`operation id: ${opId}`);

    const tx = await tl.execute(args.target, value, args.data, args.predecessor, saltBytes32);
    console.log(`execute tx: ${tx.hash}`);
    await tx.wait();
    console.log(`Executed.`);
  });
