import "./tasks/deploy-final";

import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "dotenv/config";

import {HardhatUserConfig} from "hardhat/config";

const config: HardhatUserConfig = {
  networks: {
    mainnet: {
      url: "https://lite.chain.opentensor.ai",
      accounts: process.env.ETH_PRIVATE_KEY ? [process.env.ETH_PRIVATE_KEY] : []
    },
    testnet: {
      url: "https://test.chain.opentensor.ai",
      accounts: process.env.ETH_PRIVATE_KEY ? [process.env.ETH_PRIVATE_KEY] : []
    },
    local: {
      url: "http://127.0.0.1:9944",
      accounts: process.env.ETH_PRIVATE_KEY ? [process.env.ETH_PRIVATE_KEY] : []
    }
  },
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true,
    },
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v6",
  },
  mocha: {
    timeout: 60000,
  },
};

export default config;