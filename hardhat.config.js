require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      evmVersion: "paris"
    },
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.MAINNET_SCAN_KEY,
      bsc: process.env.BSC_SCAN_KEY,
    }
  },
  sourcify: {
    enabled: true
  },
  networks: {
    hardhat: {
      chainId: 123454321,
    },
    sepolia: {
      url: "https://rpc.sepolia.org",
      accounts: [process.env.SEPOLIA_PK],
      chainId: 11155111,
    },
    bsc_main: {
      url: "https://bsc-dataseed.bnbchain.org",
      accounts: [process.env.SEPOLIA_PK],
      chainId: 56,
    }
  }
};
