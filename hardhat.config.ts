require("dotenv").config();
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      forking: {
        url: process.env.POLYGON_MAINNET!,
        blockNumber: 43686999,
      },
      chainId: 137,
    }
  },
  solidity:{
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  }
};

export default config;
