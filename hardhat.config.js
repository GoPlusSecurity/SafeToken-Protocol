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
      feeTo: process.env.SEPOLIA_FEE_TO,
      customFeeSigner: process.env.SEPOLIA_FEE_TO,
      nftManager: "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
    },
    sepolia: {
      url: "https://rpc.sepolia.org",
      accounts: [process.env.SEPOLIA_PK],
      feeTo: process.env.SEPOLIA_FEE_TO,
      customFeeSigner: process.env.SEPOLIA_FEE_TO,
      nftManager: "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
      chainId: 11155111,
    },
    bsc_main: {
      url: "https://bsc-dataseed.bnbchain.org",
      accounts: [process.env.BSC_PK],
      feeTo: process.env.BSC_FEE_TO,
      customFeeSigner: process.env.BSC_FEE_TO,
      nftManager: "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
      chainId: 56,
    }
  }
};
