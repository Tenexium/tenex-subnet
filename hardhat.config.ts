import "hardhat-storage-layout"
import "hardhat-storage-layout-changes";
import "./tasks/deploy-final";
import "./tasks/multisig";
import "./tasks/insurance-manager";
import "./tasks/staking-wrapper";

import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "dotenv/config";

import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  networks: {
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "https://lite.chain.opentensor.ai",
      accounts: process.env.ETH_PRIVATE_KEY ? [process.env.ETH_PRIVATE_KEY] : []
    },
    testnet: {
      url: process.env.TESTNET_RPC_URL || "https://test.chain.opentensor.ai",
      accounts: process.env.ETH_PRIVATE_KEY ? [process.env.ETH_PRIVATE_KEY] : []
    },
    local: {
      url: process.env.LOCAL_RPC_URL || "http://127.0.0.1:8545",
      accounts: process.env.ETH_PRIVATE_KEY ? [process.env.ETH_PRIVATE_KEY] : []
    },
    // hardhat: {
    //   forking: {
    //     url: "https://lite.chain.opentensor.ai",
    //     blockNumber: 6366360
    //     ,
    //   },
    // },
    taostats: {
      url: "https://evm.taostats.io/api/eth-rpc",
    }
  },
  etherscan: {
    apiKey: {
      taostats: "tenexium",
    },
    customChains: [
      {
        network: "taostats",
        chainId: 964,
        urls: {
          apiURL: "https://evm.taostats.io/api/api",
          browserURL: "https://evm.taostats.io"
        }
      }
    ]
  },
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          optimizer: { enabled: true, runs: 1 },
          viaIR: true,
          debug: { revertStrings: "strip" },
          evmVersion: "paris",
        },
      },
    ],
    overrides: {
      "contracts/libraries/AddressConversion.sol": {
        version: "0.8.28",
        settings: {
          optimizer: { enabled: true, runs: 200 },
          viaIR: false,
          debug: { revertStrings: "strip" },
          evmVersion: "paris",
        },
      },
    },
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v6",
  },
  mocha: {
    timeout: 60000,
  },
  paths: {
    storageLayouts: ".storage-layouts",
  },
  storageLayoutChanges: {
    contracts: ["TenexiumStorage", "TenexiumProtocol", "PositionManager", "LiquidityManager", "FeeManager", "BuybackManager", "LiquidationManager", "SubnetManager", "PrecompileAdapter"],
    fullPath: false,
  },
};

export default config;
